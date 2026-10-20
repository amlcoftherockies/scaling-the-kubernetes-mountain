terraform {
  required_version = ">= 1.5"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0"
    }
  }
}

# Terraform authenticates as YOU, using the profile that `oci setup bootstrap`
# wrote to ~/.oci/config. No keys or OCIDs go in this repo.
provider "oci" {
  region              = var.region
  config_file_profile = var.oci_profile
}
