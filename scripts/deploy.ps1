<#
.SYNOPSIS
  Provisions the NetOps Command Center repro with Terraform, builds and pushes
  the backend image to ACR, and flips the VNet DNS to the Private Resolver.

.EXAMPLE
  ./scripts/deploy.ps1 -SubscriptionId <sub-id>
  ./scripts/deploy.ps1 -AutoApprove
#>
[CmdletBinding()]
param(
  [string]$SubscriptionId,
  [switch]$AutoApprove,
  [switch]$SkipVpnCerts
)

$ErrorActionPreference = "Stop"

$root  = Split-Path -Parent $PSScriptRoot
$tfDir = Join-Path $root "terraform"
$appDir = Join-Path $root "app"
$frontendDir = Join-Path $root "frontend"

# --- Azure context ---
Write-Host "Checking Azure CLI login..." -ForegroundColor Cyan
$acct = az account show 2>$null | ConvertFrom-Json
if (-not $acct) { throw "Not logged in. Run 'az login' first." }
if ($SubscriptionId) {
  az account set --subscription $SubscriptionId | Out-Null
  $env:ARM_SUBSCRIPTION_ID = $SubscriptionId
} else {
  $env:ARM_SUBSCRIPTION_ID = $acct.id
}
Write-Host "Using subscription: $($env:ARM_SUBSCRIPTION_ID)" -ForegroundColor Green

# --- VPN certs (for P2S) ---
$genTfvars = Join-Path $tfDir "generated.auto.tfvars"
if (-not $SkipVpnCerts -and -not (Test-Path $genTfvars)) {
  Write-Host "Generating P2S VPN certificates..." -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot "gen-vpn-certs.ps1")
}

# --- App Gateway TLS cert ---
$genTls = Join-Path $tfDir "generated-tls.auto.tfvars"
if (-not (Test-Path $genTls)) {
  Write-Host "Generating App Gateway TLS certificate..." -ForegroundColor Cyan
  & (Join-Path $PSScriptRoot "gen-tls-cert.ps1")
}

# --- Allow this machine's IP to create the Key Vault cert ---
$myIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
$env:TF_VAR_deployer_ip = $myIp
Write-Host "Deployer public IP: $myIp" -ForegroundColor Green

# --- Terraform ---
Push-Location $tfDir
try {
  terraform init -input=false
  if ($AutoApprove) {
    terraform apply -input=false -auto-approve
  } else {
    terraform apply -input=false
  }

  $rg           = terraform output -raw resource_group
  $acrName      = terraform output -raw acr_name
  $appName      = terraform output -raw app_name
  $frontendName = terraform output -raw frontend_app_name
  $resolverIp   = terraform output -raw dns_resolver_inbound_ip
} finally {
  Pop-Location
}

$vnetName = (az network vnet list -g $rg --query "[0].name" -o tsv)

# --- Build & push both images ---
Write-Host "Building and pushing backend image to $acrName..." -ForegroundColor Cyan
az acr build --registry $acrName --image "netops-backend:latest" $appDir | Out-Host

Write-Host "Building and pushing frontend image to $acrName..." -ForegroundColor Cyan
az acr build --registry $acrName --image "netops-frontend:latest" $frontendDir | Out-Host

Write-Host "Restarting the web apps to pull the new images..." -ForegroundColor Cyan
az webapp restart -g $rg -n $appName | Out-Null
az webapp restart -g $rg -n $frontendName | Out-Null

# --- Flip VNet DNS to the Private Resolver (so VPN clients resolve private zones) ---
Write-Host "Setting VNet DNS to the Private Resolver inbound IP ($resolverIp)..." -ForegroundColor Cyan
az network vnet update -g $rg -n $vnetName --dns-servers $resolverIp | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Download the P2S VPN client profile:"
Write-Host "     az network vnet-gateway vpn-client generate -g $rg -n (terraform output vpn_gateway_name)"
Write-Host "  2. Install the profile (Azure VPN Client), connect."
Write-Host "  3. Browse to the custom domain output (accept the self-signed cert warning)."
