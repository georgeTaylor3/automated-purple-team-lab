# windows-workstation.pkr.hcl
#
# This file describes HOW Packer constructs the Windows workstation image.
#
# Picture Overview:
#
#     Google Windows Server 2022 image
#                    |
#                    v
#          temporary private VM
#                    |
#              Packer / WinRM
#                    |
#                    v
#          PowerShell provisioning
#                    |
#                    v
#             custom image
#
# During smoke test/ primative functions check, the last step is deliberately disabled with:
#     skip_create_image = true
#
# skip_create_image defaults to false: a normal build produces a persistent
# custom image. Set skip_create_image=true to exercise the builder lifecycle
# (IAM, networking, IAP, WinRM, cleanup) without creating an image artifact —
# useful for validating changes to this pipeline without accumulating image
# storage cost each time.
#
# This proves that IAM, Compute Engine, networking, IAP, Windows
# credential generation, WinRM, and cleanup work before the perminant artificat/image 
# is created
#
# Identity separation:
#
#     packer-deployer
#         Google Cloud API identity used by Packer
#
#     packer-builder-sa
#         runtime identity attached to the temporary Windows VM
#
#     workstation-target-sa
#         NOT used here; it will belong to the permanent VM created later by
#         Terraform.
#
# No service-account keys, Windows passwords, CALDERA credentials, Elastic
# tokens, or other secrets belong in this file.

locals {
  # GCE custom image names must be unique.
  #
  # Once image creation is enabled, this timestamp will allow each image build
  # to remain a distinct artifact rather than overwriting an existing image.
  build_timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "googlecompute" "windows_workstation" {
  # -------------------------------------------------------------------------
  # Google Cloud identity
  # -------------------------------------------------------------------------
  #
  # Packer starts with local Application Default Credentials representing the
  # authenticated human operator.
  #
  # It then obtains short-lived credentials for packer-deployer.
  #

  project_id = var.project_id

  impersonate_service_account = var.packer_deployer_service_account

  # -------------------------------------------------------------------------
  # Base operating system
  # -------------------------------------------------------------------------
  #
  # Start from Google's maintained Windows Server 2022 image family.
  #
  # An image family means the next image build can automatically use Google's
  # current non-deprecated Windows Server 2022 image instead of hardcoding
  # one historical image version.
  source_image_family = "windows-2022"

  source_image_project_id = [
    "windows-cloud"
  ]

  # -------------------------------------------------------------------------
  # Temporary builder location
  # -------------------------------------------------------------------------
  #
  # The temporary VM is placed in control-subnet.
  #
  # This is image-factory infrastructure, not a permanent workstation.
  #
  # control-subnet already has Cloud NAT, giving the builder an outbound path
  # for HTTPS dependencies while firewall policy restricts its permitted
  # traffic.
  region             = var.region
  zone               = var.zone
  subnetwork         = var.control_subnet
  network_project_id = var.project_id

  machine_type = var.machine_type
  disk_size    = var.disk_size
  disk_type    = "pd-balanced"

  # -------------------------------------------------------------------------
  # Private networking
  # -------------------------------------------------------------------------
  #
  # NO IPV4 address given to the image builder.
  omit_external_ip = true

  # Because the VM has no external address, Packer considers its private
  # interface to be the machine's usable interface. I think.
  use_internal_ip = true

  # Packer does not need direct routing from this laptop to the private VM
  # as packer invokes gcloud IAP to establish an authenticated IAP tunnel.
  use_iap = true

  # -------------------------------------------------------------------------
  # Builder runtime identity
  # -------------------------------------------------------------------------
  #
  # This service account is attached to Windows machine.
  #
  # It is deliberately different from packer-deployer.
  service_account_email = var.packer_builder_service_account

  # The temporary builder currently needs no broad Google API access.
  #
  # Keep its OAuth scope narrow. Network access such as HTTPS and Windows KMS
  # does not require Compute Admin or Storage Admin permissions.
  scopes = [
    "https://www.googleapis.com/auth/cloud-platform"
  ]

  # -------------------------------------------------------------------------
  # Shielded VM features
  # -------------------------------------------------------------------------

  enable_secure_boot          = true
  enable_vtpm                 = true
  enable_integrity_monitoring = true

  # -------------------------------------------------------------------------
  # Windows first-boot bootstrap
  # -------------------------------------------------------------------------
  #
  # Google's sysprep specialize script runs during the initial boot of a new
  # Windows instance.
  #
  # It prepares the guest-side WinRM HTTPS listener before Packer attempts to
  # provision the VM.
  metadata = {
    "sysprep-specialize-script-ps1" = file("${path.root}/scripts/bootstrap-winrm.ps1")
  }

  # -------------------------------------------------------------------------
  # Packer communicator
  # -------------------------------------------------------------------------
  #
  # Packer communicates with Windows using:
  #
  #     Packer
  #        |
  #        v
  #     IAP tunnel
  #        |
  #        v
  #     WinRM HTTPS :5986
  communicator = "winrm"

  # Google's Windows credential mechanism can create this temporary account
  # and return an automatically generated password to Packer.
  winrm_username = "packer"

  winrm_use_ssl = true

  # The builder certificate is deliberately self-signed because the VM exists
  # only during image construction. Therefore Packer cannot validate it
  # against a public certificate authority.
  #
  # Traffic is nevertheless encrypted with TLS.
  winrm_insecure = true

  # Use NTLMv2 rather than enabling WinRM Basic authentication.
  winrm_use_ntlm = true

  winrm_timeout            = "20m"
  windows_password_timeout = "10m"

  # -------------------------------------------------------------------------
  # Resulting image
  # -------------------------------------------------------------------------

  image_name = "purple-windows-workstation-${local.build_timestamp}"

  image_family = "purple-windows-workstation"

  image_description = "Windows Server 2022 workstation-style baseline for the automated purple-team lab."

  # TRUE for our first test.
  #
  # The VM and communicator lifecycle run, but Packer does not produce a
  # durable custom image.
  skip_create_image = var.skip_create_image
}

build {
  name = "windows-workstation-image-build"

  sources = [
    "source.googlecompute.windows_workstation"
  ]

  # This provisioner intentionally makes no persistent configuration change.
  #
  # Success proves that Packer reached Windows and executed PowerShell over
  # our private IAP + WinRM path.
  provisioner "powershell" {
    inline = [
      "Write-Host 'Packer WinRM smoke test succeeded.'",
      "$os = Get-CimInstance -ClassName Win32_OperatingSystem",
      "Write-Host ('Operating system: ' + $os.Caption)",
      "Write-Host ('Computer name: ' + $env:COMPUTERNAME)"
    ]
  }
  provisioner "powershell" {
    environment_vars = [
      "ELASTIC_AGENT_VERSION=9.5.2"
    ]

    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host \"Installing Elastic Agent version $env:ELASTIC_AGENT_VERSION\"",
      "$zipName = \"elastic-agent-$env:ELASTIC_AGENT_VERSION-windows-x86_64.zip\"",
      "$downloadUrl = \"https://artifacts.elastic.co/downloads/beats/elastic-agent/$zipName\"",
      "$destDir = 'C:\\Program Files\\Elastic'",
      "New-Item -ItemType Directory -Force -Path $destDir | Out-Null",
      "Invoke-WebRequest -Uri $downloadUrl -OutFile \"$env:TEMP\\$zipName\" -UseBasicParsing",
      "Expand-Archive -Path \"$env:TEMP\\$zipName\" -DestinationPath $destDir -Force",
      "$extractedFolder = Get-ChildItem -Path $destDir -Directory | Where-Object { $_.Name -like 'elastic-agent-*' } | Select-Object -First 1",
      "Rename-Item -Path $extractedFolder.FullName -NewName 'elastic-agent'",
      "Remove-Item \"$env:TEMP\\$zipName\" -Force",
      "Write-Host 'Elastic Agent binary installed. Enrollment deferred to boot-time startup script.'"
    ]
  }
}
