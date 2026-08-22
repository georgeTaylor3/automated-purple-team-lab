# versions.pkr.hcl
#
# This file defines the Packer version and external plugin versions expected
# by the Windows workstation image-building project.
#
# Packer itself provides the core workflow:
#
#     read template
#         |
#         v
#     coordinate build
#         |
#         v
#     run provisioners
#
# Cloud-specific builders are provided by plugins. In this project, the
# Google Compute plugin teaches Packer how to interact with Google Compute
# Engine.
#
# Keeping these requirements in source control makes the image pipeline more
# reproducible. Someone cloning the repository can determine which tooling
# versions the project was designed and tested against.
#
# This file contains no credentials, project IDs, service-account addresses,
# passwords, or other environment-specific values.

packer {
  # This project is being developed and tested with Packer 1.16.x.
  #
  # "~> 1.16.0" allows compatible patch releases such as:
  #
  #     1.16.0
  #     1.16.1
  #     1.16.2
  #
  # but prevents an automatic move to a future minor release such as 1.17.0.
  #
  # That gives us patch-level bug fixes without silently changing the Packer
  # generation used by the project.
  required_version = "~> 1.16.0"

  required_plugins {
    # The Google Compute plugin supplies the "googlecompute" builder used in
    # windows-workstation.pkr.hcl.
    #
    # Without this plugin, Packer understands its own HCL language but does
    # not know how to create temporary Compute Engine VMs or GCE images.
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "= 1.2.7"
    }
  }
}
