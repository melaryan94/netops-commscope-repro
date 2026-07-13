<#
.SYNOPSIS
  Bootstraps a hardened Azure Storage account + container for Terraform remote state
  (AAD-only, no shared keys, versioning + soft delete), and grants the current user
  Storage Blob Data Contributor.

.NOTES
  Run once. Then copy cicd/backend.tf.example into your infra/ folder and fill in the
  storage account name printed below. Grant your pipeline's service-connection identity
  the same 'Storage Blob Data Contributor' role on this account.
#>
[CmdletBinding()]
param(
  [string]$Location       = "centralus",
  [string]$ResourceGroup  = "rg-tfstate",
  [string]$Container       = "tfstate",
  [string]$StorageAccount  = "sttfstatenetops$((Get-Random -Maximum 99999))"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating resource group $ResourceGroup..." -ForegroundColor Cyan
az group create -n $ResourceGroup -l $Location | Out-Null

Write-Host "Creating storage account $StorageAccount (AAD-only, no public blob)..." -ForegroundColor Cyan
az storage account create -n $StorageAccount -g $ResourceGroup -l $Location `
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 `
  --allow-blob-public-access false --allow-shared-key-access false | Out-Null

Write-Host "Enabling blob versioning + soft delete..." -ForegroundColor Cyan
az storage account blob-service-properties update --account-name $StorageAccount -g $ResourceGroup `
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 | Out-Null

Write-Host "Creating container $Container..." -ForegroundColor Cyan
az storage container create -n $Container --account-name $StorageAccount --auth-mode login | Out-Null

$saId = az storage account show -n $StorageAccount -g $ResourceGroup --query id -o tsv
az role assignment create --assignee (az ad signed-in-user show --query id -o tsv) `
  --role "Storage Blob Data Contributor" --scope $saId | Out-Null

Write-Host ""
Write-Host "State backend ready. Put these into backend.tf:" -ForegroundColor Green
Write-Host "  resource_group_name  = `"$ResourceGroup`""
Write-Host "  storage_account_name = `"$StorageAccount`""
Write-Host "  container_name       = `"$Container`""
Write-Host "  use_azuread_auth     = true"
Write-Host ""
Write-Host "Also grant your pipeline's service-connection identity 'Storage Blob Data Contributor' on this account." -ForegroundColor Yellow
