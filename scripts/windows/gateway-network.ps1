<#
.SYNOPSIS
  Prepare Windows so the Power BI on-premises data gateway service can reach
  the POC's PostgreSQL container running in WSL.

.DESCRIPTION
  Run in an Administrator PowerShell after ./scripts/setup.sh.
  1. Trusts the POC's self-signed PostgreSQL certificate (LocalMachine\Root).
  2. -PortProxy (Windows 10 / WSL NAT networking only): forwards
     127.0.0.1:5432 to <WSL eth0 IP>:15432 with netsh portproxy, because the
     gateway service cannot use WSL's per-user localhost forwarding.
     Re-run with -PortProxy after every reboot or `wsl --shutdown`
     (the WSL IP address changes).
  3. Restarts the gateway service.

.EXAMPLE
  .\gateway-network.ps1 -RepoPath ~/sources/powerbi-vault-poc -PortProxy
#>
param(
  [Parameter(Mandatory = $true)][string]$RepoPath,   # repository path inside WSL
  [string]$Distro = "",                               # WSL distribution; default distro if empty
  [switch]$PortProxy
)
$ErrorActionPreference = "Stop"

function Invoke-Wsl([string]$command) {
  if ($Distro) { wsl -d $Distro -e sh -c $command } else { wsl -e sh -c $command }
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw "Run this script in an Administrator PowerShell."
}

# 1. Trust the PostgreSQL certificate
$pem = (Invoke-Wsl "cat $RepoPath/postgres/tls/server.crt") -join "`n"
if (-not $pem.Contains("BEGIN CERTIFICATE")) { throw "Certificate not found; run ./scripts/setup.sh in WSL first." }
$certFile = Join-Path $env:TEMP "pbi-poc-postgres.crt"
Set-Content -Path $certFile -Value $pem -Encoding ascii
$cert = Import-Certificate -FilePath $certFile -CertStoreLocation Cert:\LocalMachine\Root
Remove-Item $certFile
Write-Host "Trusted PostgreSQL certificate $($cert.Subject) ($($cert.Thumbprint))"

# 2. Port forwarding for WSL NAT networking
if ($PortProxy) {
  $ip = (Invoke-Wsl "ip -4 -o addr show eth0 | awk '{print `$4}' | cut -d/ -f1").Trim()
  if (-not $ip) { throw "Could not determine the WSL eth0 address." }
  netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=5432 2>$null | Out-Null
  netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=5432 connectaddress=$ip connectport=15432 | Out-Null
  Write-Host "Forwarding 127.0.0.1:5432 -> ${ip}:15432"
  $test = Test-NetConnection -ComputerName $ip -Port 15432 -WarningAction SilentlyContinue
  if (-not $test.TcpTestSucceeded) {
    Write-Warning "WSL PostgreSQL is not reachable at ${ip}:15432. Check POSTGRES_PUBLISH=0.0.0.0:15432 in .env and 'docker compose up -d'."
  }
}

# 3. Restart the gateway so it picks up the trusted certificate
Restart-Service PBIEgwService
Write-Host "Gateway service restarted."
