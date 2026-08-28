# versions.pkr.hcl
#
# Same Packer version and plugin pin as the other pipelines, so all
# builds stay reproducible together.

packer {
  required_version = "~> 1.16.0"

  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = "= 1.2.7"
    }
  }
}
