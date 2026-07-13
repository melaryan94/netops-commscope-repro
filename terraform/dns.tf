# --- Private DNS zones for the PaaS private endpoints ---
locals {
  private_dns_zones = {
    web      = "privatelink.azurewebsites.net"
    postgres = "privatelink.postgres.database.azure.com"
    vault    = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "zones" {
  for_each              = azurerm_private_dns_zone.zones
  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

# --- Custom internal domain: netops.commscope.com -> App Gateway private IP ---
locals {
  # zone = "commscope.com", record = "netops"
  domain_parts = split(".", var.custom_domain)
  domain_host  = local.domain_parts[0]
  domain_zone  = join(".", slice(local.domain_parts, 1, length(local.domain_parts)))
}

resource "azurerm_private_dns_zone" "custom" {
  name                = local.domain_zone
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "custom" {
  name                  = "link-custom"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.custom.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "netops" {
  name                = local.domain_host
  zone_name           = azurerm_private_dns_zone.custom.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 60
  records             = [local.appgw_private_ip]
}

# --- DNS Private Resolver (so VPN clients resolve the private zones) ---
resource "azurerm_private_dns_resolver" "resolver" {
  name                = local.names.resolver
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  virtual_network_id  = azurerm_virtual_network.vnet.id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "inbound" {
  name                    = "inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = "10.50.4.4"
    subnet_id                    = azurerm_subnet.dnsr_inbound.id
  }
}
