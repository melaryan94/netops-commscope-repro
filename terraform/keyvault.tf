variable "deployer_ip" {
  description = "Public IP of the machine running Terraform, allowed to create the KV cert. Set by deploy.ps1."
  type        = string
  default     = ""
}

resource "azurerm_key_vault" "kv" {
  name                          = local.names.kv
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true
  purge_protection_enabled      = false
  public_network_access_enabled = true
  tags                          = var.tags

  network_acls {
    default_action             = "Allow" # repro: allow provisioning writes. Production: "Deny" + PE-only / firewall.
    bypass                     = "AzureServices"
    ip_rules                   = var.deployer_ip != "" ? [var.deployer_ip] : []
    virtual_network_subnet_ids = [azurerm_subnet.appgw.id, azurerm_subnet.app_integration.id]
  }
}

# App identity can read KV secrets at runtime over the private endpoint.
resource "azurerm_role_assignment" "kv_app_secrets" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# --- Private endpoint for Key Vault (the app resolves KV privately) ---
resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-${var.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["vault"].id]
  }
}
