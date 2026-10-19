# Run in an Administrator PowerShell. Configure only the EG4D20 wired adapter.
# Confirm the cable is connected to EG4D20 before running this script.
$ErrorActionPreference = 'Stop'
$egIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$egPrincipal = [Security.Principal.WindowsPrincipal]::new($egIdentity)
if (-not $egPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as Administrator, then run this script again.'
}
$egAdapter = @(Get-NetAdapter -Physical | Where-Object InterfaceDescription -eq 'Realtek Gaming 2.5GbE Family Controller')
if ($egAdapter.Count -ne 1) { throw 'Expected exactly one Realtek physical adapter; check adapter identity.' }
$egIndex = $egAdapter[0].InterfaceIndex
$egBackup = Join-Path $PSScriptRoot ('network_before_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmssfff') + '.json')
[ordered]@{ Adapter = $egAdapter[0] | Select-Object Name,InterfaceDescription,InterfaceIndex,MacAddress; IPInterface = Get-NetIPInterface -InterfaceIndex $egIndex -AddressFamily IPv4 | Select-Object Dhcp; Addresses = @(Get-NetIPAddress -InterfaceIndex $egIndex -AddressFamily IPv4 | Select-Object IPAddress,PrefixLength); DNS = Get-DnsClientServerAddress -InterfaceIndex $egIndex -AddressFamily IPv4 | Select-Object ServerAddresses } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -LiteralPath $egBackup
if (-not (Get-NetIPAddress -InterfaceIndex $egIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq '192.168.50.1' -and $_.PrefixLength -eq 24 })) {
    New-NetIPAddress -InterfaceIndex $egIndex -IPAddress '192.168.50.1' -PrefixLength 24 -AddressFamily IPv4 | Out-Null
}
Write-Host "Configured wired adapter 192.168.50.1/24. Backup: $egBackup"
Get-NetAdapter | Where-Object InterfaceIndex -eq $egIndex | Format-Table Name,Status,LinkSpeed
