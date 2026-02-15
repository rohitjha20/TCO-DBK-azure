terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.50.0"
    }    
    databricks = {
      source = "databricks/databricks"
      version = "1.85.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "databricks" {
  host = var.databricks_host
  azure_use_msi = true
}