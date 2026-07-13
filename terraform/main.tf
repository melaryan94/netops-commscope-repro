data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result

  # Short token for globally-unique / length-limited names (KV<=24, ACR alnum).
  short = replace(var.prefix, "-", "")

  rg_name          = "rg-${var.prefix}-repro"
  appgw_private_ip = "10.50.1.10"

  names = {
    vnet         = "vnet-${var.prefix}"
    nat          = "nat-${var.prefix}"
    nat_pip      = "pip-nat-${var.prefix}"
    resolver     = "dnspr-${var.prefix}"
    vpngw        = "vpngw-${var.prefix}"
    vpngw_pip    = "pip-vpngw-${var.prefix}"
    kv           = substr("kv${local.short}${local.suffix}", 0, 24)
    acr          = substr("acr${local.short}${local.suffix}", 0, 50)
    pg           = "psql-${var.prefix}-${local.suffix}"
    plan         = "plan-${var.prefix}"
    app          = "app-${var.prefix}-${local.suffix}"
    frontend     = "app-fe-${var.prefix}-${local.suffix}"
    appgw        = "agw-${var.prefix}"
    appgw_pip    = "pip-agw-${var.prefix}"
    waf_policy   = replace("waf${var.prefix}", "-", "")
    app_identity = "id-app-${var.prefix}"
    agw_identity = "id-agw-${var.prefix}"
  }
}

resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}

# User-assigned identities (app pulls from ACR; App Gateway reads TLS cert from KV)
resource "azurerm_user_assigned_identity" "app" {
  name                = local.names.app_identity
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "agw" {
  name                = local.names.agw_identity
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = var.tags
}
