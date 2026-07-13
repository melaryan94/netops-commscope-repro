resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  short = replace(var.prefix, "-", "")
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# --- Network ---
# Separate CI/CD VNet (distinct range from the app VNet 10.50.0.0/16 so the two
# can be peered later if you ever want the agent to reach app private endpoints;
# for terraform plan/apply the agent only needs the ARM control plane + the
# private STATE storage endpoint below).
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.80.0.0/16"]
  tags                = var.tags
}

# Agent subnet for the Managed DevOps Pool (VNet injection). Created via azapi
# because the pinned azurerm provider doesn't yet allow the
# Microsoft.DevOpsInfrastructure/pools delegation value.
resource "azapi_resource" "agent_subnet" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-11-01"
  name      = "snet-agent"
  parent_id = azurerm_virtual_network.vnet.id

  schema_validation_enabled = false

  body = jsonencode({
    properties = {
      addressPrefix = "10.80.1.0/24"
      natGateway    = { id = azurerm_nat_gateway.nat.id }
      delegations = [
        {
          name = "mdp"
          properties = {
            serviceName = "Microsoft.DevOpsInfrastructure/pools"
          }
        }
      ]
    }
  })

  # Azure serializes subnet writes within a VNet; sequence after the PE subnet.
  depends_on = [
    azurerm_subnet.pe,
    azurerm_nat_gateway_public_ip_association.nat
  ]
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.80.2.0/24"]
}

# --- NAT Gateway for agent outbound (download agent + reach dev.azure.com / ARM) ---
resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags

  lifecycle {
    ignore_changes = [ip_tags, zones]
  }
}

resource "azurerm_nat_gateway" "nat" {
  name                = "nat-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

# NAT association for the agent subnet is defined inside azapi_resource.agent_subnet.
