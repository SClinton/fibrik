terraform {
  required_version = ">= 1.8"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0, < 8.0"
    }
  }
}

provider "oci" {
  region = var.region
}
