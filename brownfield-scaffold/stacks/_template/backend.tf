# Terraform for a single resource group ("stack"). Copy this folder per RG.
#
# Instantiate:
#   1. Copy  brownfield-scaffold/stacks/_template  ->  brownfield-scaffold/stacks/<rg-name>
#   2. In backend.tf below: set a UNIQUE `key` ("<rg-name>.tfstate") and the real
#      storage_account_name (bootstrap output `state_storage_account_name`).
#   3. Import the existing RG into THIS folder's state with aztfexport (see main.tf).
#   4. `terraform plan` until it says "No changes".
#
# Uses AAD auth (no storage keys) against the PRIVATE state account created by
# cicd-private/bootstrap. Run from a VNet-connected host / the MDP agent.

terraform {
  backend "azurerm" {
    resource_group_name  = "rg-netops-cicd"   # cicd platform RG (bootstrap output state_resource_group)
    storage_account_name = "REPLACE_STATE_SA" # bootstrap output state_storage_account_name
    container_name       = "tfstate"
    key                  = "REPLACE_STACK.tfstate" # e.g. rg-network.tfstate — MUST be unique per stack
    use_azuread_auth     = true
  }
}
