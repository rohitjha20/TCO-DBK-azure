locals {
  external_location_url = format("abfss://%s@%s.dfs.core.windows.net", var.container_name, var.storage_account_name)
  catalog_location_url = join("", [local.external_location_url, "/catalog_default/"])
  volume_location_url = join("", [local.external_location_url, "/export/"])  
}

resource "azurerm_storage_account" "azure_billing" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  allow_nested_items_to_be_public = false 
}

resource "azurerm_storage_container" "container" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.azure_billing.id
}

resource "azurerm_databricks_access_connector" "access_connector" {
  name                = "azure_billing_access_connector"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "role_assignment" {
  scope               = azurerm_storage_account.azure_billing.id
  role_definition_name  = "Storage Blob Data Contributor"
  principal_id        = azurerm_databricks_access_connector.access_connector.identity[0].principal_id
}

resource "databricks_storage_credential" "external_mi" {
  name = "mi_credential"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.access_connector.id
  }
}

resource "databricks_external_location" "azure_billing_external_location" {
  name = "azure_billing_external_location"
  url = local.external_location_url
  credential_name = databricks_storage_credential.external_mi.id

  depends_on = [ azurerm_storage_container.container ]
}

resource "databricks_catalog" "billing_catalog" {
  name = var.catalog_name
  storage_root = local.catalog_location_url
}

resource "databricks_schema" "billing_schema" {
  catalog_name = databricks_catalog.billing_catalog.name
  name = var.schema_name
}

resource "databricks_volume" "cost_export" {
  name             = "cost_export"
  catalog_name     = databricks_catalog.billing_catalog.name
  schema_name      = databricks_schema.billing_schema.name
  volume_type      = "EXTERNAL"
  storage_location = local.volume_location_url
}