output "resource_group" {
  value = azurerm_resource_group.rg.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "app_name" {
  value = azurerm_linux_web_app.app.name
}

output "frontend_app_name" {
  value = azurerm_linux_web_app.frontend.name
}

output "app_default_hostname" {
  description = "App Service private hostname (resolves to the private endpoint inside the VNet)."
  value       = azurerm_linux_web_app.app.default_hostname
}

output "appgw_private_ip" {
  value = local.appgw_private_ip
}

output "custom_domain" {
  description = "Browse here from a VPN-connected client once DNS is flipped."
  value       = "https://${var.custom_domain}"
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.pg.fqdn
}

output "dns_resolver_inbound_ip" {
  description = "Set the VNet/VPN client DNS to this so private zones resolve over VPN."
  value       = "10.50.4.4"
}

output "vpn_gateway_name" {
  value = azurerm_virtual_network_gateway.vpngw.name
}
