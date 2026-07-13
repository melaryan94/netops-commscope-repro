# --- Private state storage account ---
# On locked-down subscriptions, Azure Policy commonly forces:
#   * publicNetworkAccess = Disabled
#   * allowSharedKeyAccess = false
# The azurerm storage resource performs a post-create blob-service DATA-PLANE
# poll that then fails (403 KeyBasedAuthenticationNotPermitted). Managing the
# account via azapi keeps Terraform on the ARM control plane only, so it works.
resource "azapi_resource" "state" {
  type      = "Microsoft.Storage/storageAccounts@2023-01-01"
  name      = substr("sttf${local.short}${random_string.suffix.result}", 0, 24)
  parent_id = azurerm_resource_group.rg.id
  location  = var.location
  tags      = var.tags

  schema_validation_enabled = false

  body = jsonencode({
    sku  = { name = "Standard_LRS" }
    kind = "StorageV2"
    properties = {
      minimumTlsVersion        = "TLS1_2"
      supportsHttpsTrafficOnly = true
      allowBlobPublicAccess    = false
      allowSharedKeyAccess     = false
      publicNetworkAccess      = "Disabled"
    }
  })
}

# Container created via the ARM control plane (works even though the account is private).
resource "azapi_resource" "tfstate_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01"
  name      = "tfstate"
  parent_id = "${azapi_resource.state.id}/blobServices/default"
  body = jsonencode({
    properties = { publicAccess = "None" }
  })
}

# --- Private endpoint + private DNS so the in-VNet agent can reach blob storage ---
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "state" {
  name                = "pe-state-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-state"
    private_connection_resource_id = azapi_resource.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}
