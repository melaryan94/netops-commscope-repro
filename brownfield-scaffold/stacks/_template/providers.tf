terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    # azapi is handy for resources/properties the azurerm provider doesn't cover
    # (e.g. policy-locked storage, newer resource types). Remove if unused.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 1.15"
    }
  }
}

provider "azurerm" {
  features {}
  # In CI the subscription comes from the OIDC service connection; locally from az.
  subscription_id = var.subscription_id != "" ? var.subscription_id : null
}

provider "azapi" {}
