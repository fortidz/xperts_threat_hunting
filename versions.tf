terraform {
  required_version = ">= 1.5, < 2.0"

  # Remote state in Azure Storage — required for GitHub Actions.
  # Create the storage account + container first (see README), then uncomment:
  #
  # backend "azurerm" {
  #   resource_group_name  = "tfstate-rg"
  #   storage_account_name = "yourorgterraformstate"
  #   container_name       = "tfstate"
  #   key                  = "xperts-threat-hunting.tfstate"
  #   use_oidc             = true
  # }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    fortios = {
      source  = "fortinetdev/fortios"
      version = "~> 1.22"
    }
  }
}

provider "azurerm" {
  features {
    virtual_machine {
      # Remove OS disk automatically when VM is deleted
      delete_os_disk_on_deletion = true
    }
  }
}

provider "fortios" {
  hostname = "${var.fortigate_api_hostname}:${local.fgt_port_admin_https}"
  token    = var.fortigate_api_token
  insecure = true
}
