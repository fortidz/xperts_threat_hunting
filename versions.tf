terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    fortios = {
      source  = "fortinetdev/fortios"
      version = "~> 1.22"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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

provider "aws" {
  region     = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

provider "fortios" {
  hostname = local.fortigate_api_host
  token    = var.fortigate_api_token
  insecure = false # valid Let's Encrypt wildcard cert injected at bootstrap
}
