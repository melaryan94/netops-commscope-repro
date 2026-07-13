resource "random_password" "pg" {
  length           = 24
  special          = true
  override_special = "!#$%*-_"
}

locals {
  pg_password = var.pg_admin_password != "" ? var.pg_admin_password : random_password.pg.result
}

resource "azurerm_postgresql_flexible_server" "pg" {
  name                          = local.names.pg
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.location
  version                       = "16"
  administrator_login           = var.pg_admin_login
  administrator_password        = local.pg_password
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  zone                          = "1"
  public_network_access_enabled = false

  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.zones["postgres"].id

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.zones]
}

resource "azurerm_postgresql_flexible_server_database" "appdb" {
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.pg.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
