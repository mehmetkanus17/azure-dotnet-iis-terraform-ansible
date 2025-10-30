# providers.tf
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.37.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "acec3773-00d6-4b7a-bde2-fd1d223a56a3"
}

# azure cli ile login olunmalı
# az login
 