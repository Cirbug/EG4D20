# Read-only diagnostics. Does not change IP addresses or firewall rules.
$ErrorActionPreference = 'Stop'
Get-NetAdapter -Physical | Format-Table Name, InterfaceDescription, Status, LinkSpeed
Get-NetIPAddress -AddressFamily IPv4 |
    Select-Object InterfaceAlias, IPAddress, PrefixLength, AddressState |
    Format-Table -AutoSize
$localAddress = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object IPAddress -eq '192.168.50.1'
if (-not $localAddress) {
    Write-Host 'Configure only the wired adapter: 192.168.50.1 / 255.255.255.0, no gateway/DNS.'
} else {
    Write-Host 'Expected local IPv4 address is present. Confirm its adapter has a 1 Gbps link.'
}
