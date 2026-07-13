<#
.SYNOPSIS
  Generates a self-signed root + client certificate for Point-to-Site VPN and
  writes the root public data into terraform/generated.auto.tfvars.

.NOTES
  Windows only (uses New-SelfSignedCertificate). Run once before deploy.ps1.
  The client cert is left in your CurrentUser\My store for the Azure VPN client.
#>
[CmdletBinding()]
param(
  [string]$RootName   = "netops-p2s-root",
  [string]$RootSubject = "NetOpsP2SRoot",
  [string]$ClientSubject = "NetOpsP2SClient"
)

$ErrorActionPreference = "Stop"

$tfDir  = Join-Path (Split-Path -Parent $PSScriptRoot) "terraform"
$outFile = Join-Path $tfDir "generated.auto.tfvars"

Write-Host "Creating self-signed P2S root certificate..." -ForegroundColor Cyan
$root = New-SelfSignedCertificate `
  -Type Custom -KeySpec Signature `
  -Subject "CN=$RootSubject" `
  -KeyExportPolicy Exportable `
  -HashAlgorithm sha256 -KeyLength 2048 `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyUsageProperty Sign -KeyUsage CertSign

Write-Host "Creating client certificate signed by the root..." -ForegroundColor Cyan
$null = New-SelfSignedCertificate `
  -Type Custom -KeySpec Signature `
  -Subject "CN=$ClientSubject" `
  -KeyExportPolicy Exportable `
  -HashAlgorithm sha256 -KeyLength 2048 `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -Signer $root `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")

$rootBytes = $root.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$rootB64   = [System.Convert]::ToBase64String($rootBytes)

@"
vpn_root_cert_name = "$RootName"
vpn_root_cert_data = "$rootB64"
"@ | Set-Content -Path $outFile -Encoding ascii

Write-Host "Wrote root cert data to $outFile" -ForegroundColor Green
Write-Host "Root thumbprint: $($root.Thumbprint)"
Write-Host "Client cert installed in Cert:\CurrentUser\My (used by the Azure VPN client)."
