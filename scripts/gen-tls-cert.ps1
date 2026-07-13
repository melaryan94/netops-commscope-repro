<#
.SYNOPSIS
  Generates a self-signed PFX for the App Gateway HTTPS listener and writes its
  base64 + password into terraform/generated-tls.auto.tfvars.

.NOTES
  Windows only. The listener cert is self-signed for the internal custom domain,
  so browsers will show a trust warning (expected for a private repro).
#>
[CmdletBinding()]
param(
  [string]$Domain      = "netops.commscope.com",
  [string]$PfxPassword = ""
)

$ErrorActionPreference = "Stop"

# Generate a random PFX password if none supplied (avoids hardcoded secrets).
if (-not $PfxPassword) { $PfxPassword = [Guid]::NewGuid().ToString('N') }

$tfDir  = Join-Path (Split-Path -Parent $PSScriptRoot) "terraform"
$outFile = Join-Path $tfDir "generated-tls.auto.tfvars"

Write-Host "Creating self-signed TLS cert for CN=$Domain ..." -ForegroundColor Cyan
$cert = New-SelfSignedCertificate `
  -DnsName $Domain `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -KeyExportPolicy Exportable `
  -KeyLength 2048 `
  -NotAfter (Get-Date).AddYears(1)

$pwd     = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText
$pfxPath = Join-Path $env:TEMP "netops-tls.pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $pwd | Out-Null

$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfxPath))
Remove-Item $pfxPath -Force

@"
tls_pfx_base64   = "$b64"
tls_pfx_password = "$PfxPassword"
"@ | Set-Content -Path $outFile -Encoding ascii

Write-Host "Wrote App Gateway PFX to $outFile" -ForegroundColor Green
