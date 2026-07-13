resource "azurerm_virtual_network" "vnet" {
  name                = local.names.vnet
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  address_space       = ["10.50.0.0/16"]
  tags                = var.tags
}

# --- Subnets ---
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.1.0/24"]
  service_endpoints    = ["Microsoft.KeyVault"]
}

resource "azurerm_subnet" "app_integration" {
  name                 = "snet-app-integration"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.2.0/24"]
  service_endpoints    = ["Microsoft.KeyVault"]

  delegation {
    name = "webapp"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-privateendpoints"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.3.0/24"]
}

resource "azurerm_subnet" "dnsr_inbound" {
  name                 = "snet-dnsr-inbound"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.4.0/28"]

  delegation {
    name = "dnsresolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.5.0/24"]

  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.50.255.0/27"]
}

# --- NAT Gateway (stable outbound IP for vendor allow-lists) ---
resource "azurerm_public_ip" "nat" {
  name                = local.names.nat_pip
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

resource "azurerm_nat_gateway" "nat" {
  name                    = local.names.nat
  resource_group_name     = azurerm_resource_group.rg.name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# App outbound (VNet integration) egresses via NAT.
resource "azurerm_subnet_nat_gateway_association" "app_integration" {
  subnet_id      = azurerm_subnet.app_integration.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}
