<#
.SYNOPSIS
  Tears down the NetOps Command Center repro.
#>
[CmdletBinding()]
param(
  [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"

$tfDir = Join-Path (Split-Path -Parent $PSScriptRoot) "terraform"

Push-Location $tfDir
try {
  if ($AutoApprove) {
    terraform destroy -input=false -auto-approve
  } else {
    terraform destroy -input=false
  }
} finally {
  Pop-Location
}

Write-Host "Destroyed. Note: the VPN Gateway can take several minutes to delete." -ForegroundColor Green
