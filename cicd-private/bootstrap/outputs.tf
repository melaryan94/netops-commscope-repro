output "state_storage_account_name" {
  description = "Paste into cicd-private/backend.tf (storage_account_name) for the app pipeline."
  value       = azapi_resource.state.name
}

output "state_resource_group" {
  value = azurerm_resource_group.rg.name
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}

output "agent_subnet_id" {
  description = "Select this subnet when creating the Managed DevOps Pool (VNet injection)."
  value       = azapi_resource.agent_subnet.id
}

output "mdp_pool_name_to_create" {
  value = var.ado_pool
}
