# bootstrap-winrm.ps1
#
# This script runs during the initial boot of the temporary Windows Server
# image-builder VM.
#
# Currently its here to prepare a secure-enough temporary WinRM
# management channel so that Packer can connect through Google IAP.
#
# This will change. this is only a test for network cons to KMS and IAP
# Also tests correct service account relationships
#
# Network path:
#
#     Packer
#        |
#        | authenticated IAP tunnel
#        v
#     Google IAP
#     35.235.240.0/20
#        |
#        | TCP 5986
#        v
#     Windows WinRM HTTPS listener
#
# Security decisions:
#
#   - HTTPS WinRM uses TCP 5986.
#   - HTTP WinRM on TCP 5985 is not used.
#   - Basic authentication is disabled.
#   - Packer will use NTLMv2.
#   - Unencrypted WinRM is disabled.
#   - The Windows firewall independently limits the source to Google's
#     documented IAP TCP-forwarding range.
#   - The certificate is temporary and self-signed.
#
# The GCP VPC firewall already restricts this traffic to VMs running with
# packer-builder-sa. This Windows firewall rule provides a second layer.
#
# No passwords or other credentials are embedded in this file.

$ErrorActionPreference = "Stop"

Write-Host "Beginning temporary Packer WinRM configuration."

# ---------------------------------------------------------------------------
# Start and configure WinRM.
# ---------------------------------------------------------------------------

Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# Initialize PowerShell remoting.
Enable-PSRemoting -SkipNetworkProfileCheck -Force

# ---------------------------------------------------------------------------
# Remove existing WinRM listeners.
# ---------------------------------------------------------------------------
#
# Starting from a known listener configuration helps make the build
# repeatable. We do not want an inherited HTTP listener accidentally exposing
# TCP 5985.

Get-ChildItem -Path WSMan:\localhost\Listener |
    Remove-Item -Recurse -Force

# ---------------------------------------------------------------------------
# Create a temporary TLS certificate.
# ---------------------------------------------------------------------------
#
# This certificate exists only to encrypt the temporary Packer provisioning
# channel. It is not a production identity certificate and will not
# be trusted outside this brief build process.

$certificate = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddDays(2)

# Create an HTTPS WinRM listener on TCP 5986.
New-Item `
    -Path WSMan:\localhost\Listener `
    -Transport HTTPS `
    -Address * `
    -CertificateThumbPrint $certificate.Thumbprint `
    -Force |
    Out-Null

# ---------------------------------------------------------------------------
# Configure authentication.
# ---------------------------------------------------------------------------

# Do not permit Basic authentication.
Set-Item `
    -Path WSMan:\localhost\Service\Auth\Basic `
    -Value $false

# Allow Windows Negotiate authentication, which supports the NTLMv2
# communicator configuration from Packer.
Set-Item `
    -Path WSMan:\localhost\Service\Auth\Negotiate `
    -Value $true

# Never permit plaintext WinRM sessions.
Set-Item `
    -Path WSMan:\localhost\Service\AllowUnencrypted `
    -Value $false

# ---------------------------------------------------------------------------
# Permit administrative remote execution for the temporary Packer account.
# ---------------------------------------------------------------------------
#
# Google Compute Engine's Windows account manager creates the temporary Packer
# user when Packer requests Windows credentials. Newly created users are
# normally added to the local Administrators group by the Google guest agent.
#
# LocalAccountTokenFilterPolicy prevents Windows from stripping the remote
# administrative token from a local administrator during provisioning.

$systemPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

New-ItemProperty `
    -Path $systemPolicy `
    -Name "LocalAccountTokenFilterPolicy" `
    -PropertyType DWord `
    -Value 1 `
    -Force |
    Out-Null

# ---------------------------------------------------------------------------
# Windows Defender Firewall
# ---------------------------------------------------------------------------
#
# The GCP VPC firewall already permits only:
#
#     Google IAP range -> packer-builder-sa -> TCP 5986
#
# We repeat the IAP source restriction inside Windows as defense in depth.

Get-NetFirewallRule `
    -DisplayName "Packer WinRM HTTPS" `
    -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule

New-NetFirewallRule `
    -DisplayName "Packer WinRM HTTPS" `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort 5986 `
    -RemoteAddress "35.235.240.0/20" `
    -Profile Any |
    Out-Null

Restart-Service -Name WinRM

Write-Host "Temporary Packer WinRM HTTPS configuration complete."
