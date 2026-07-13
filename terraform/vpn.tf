resource "azurerm_public_ip" "vpngw" {
  name                = local.names.vpngw_pip
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

resource "azurerm_virtual_network_gateway" "vpngw" {
  name                = local.names.vpngw
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location

  type          = "Vpn"
  vpn_type      = "RouteBased"
  sku           = "VpnGw1AZ"
  generation    = "Generation1"
  active_active = false
  enable_bgp    = false
  tags          = var.tags

  ip_configuration {
    name                          = "vpngw-ipcfg"
    public_ip_address_id          = azurerm_public_ip.vpngw.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  # P2S config is added once the root cert is generated (scripts/gen-vpn-certs.ps1).
  dynamic "vpn_client_configuration" {
    for_each = var.vpn_root_cert_data != "" ? [1] : []
    content {
      address_space        = [var.vpn_client_address_pool]
      vpn_client_protocols = ["OpenVPN"]

      root_certificate {
        name             = var.vpn_root_cert_name
        public_cert_data = var.vpn_root_cert_data
      }
    }
  }
}
