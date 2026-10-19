param([string]$TdExe = 'D:\New Folder\bin\td_commands_prompt.exe')
$ErrorActionPreference = 'Stop'
$egRoot = Split-Path -Parent $PSScriptRoot
$egBank = Join-Path (Split-Path -Parent $egRoot) 'bank\eg4d_udp_20261019'
$egOutput = Join-Path $egRoot 'output'
if (-not (Test-Path -LiteralPath $TdExe)) { throw "TD executable not found: $TdExe" }
New-Item -ItemType Directory -Force -Path $egBank,$egOutput | Out-Null
# Remove the advertised output before starting; preserve it as a previous image.
$egPublished = Join-Path $egOutput 'eg4d20_udp_loop.bit'
if (Test-Path -LiteralPath $egPublished) {
    Move-Item -LiteralPath $egPublished -Destination (Join-Path $egBank ('published_previous_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmssfff') + '.bit'))
}
$egStart = Get-Date
$egLog = Join-Path $egBank 'build.log'
& $TdExe ((Join-Path $PSScriptRoot 'build.tcl') -replace '\\','/') *> $egLog
$egBit = Join-Path $egBank 'fpga\eg4d20_udp_loop.bit'
if (-not (Select-String -LiteralPath $egLog -Pattern '^EG4D20_UDP_BUILD_COMPLETE$' -Quiet)) {
    throw "Build failed; inspect $egLog"
}
if (-not (Test-Path -LiteralPath $egBit)) { throw 'No generated bitstream' }
if ((Get-Item -LiteralPath $egBit).LastWriteTime -lt $egStart) { throw 'Stale bitstream' }
Copy-Item -LiteralPath $egBit -Destination $egPublished
Copy-Item -LiteralPath (Join-Path $egBank 'fpga\final_timing.rpt'),(Join-Path $egBank 'fpga\final.area') -Destination $egOutput
$egHash = (Get-FileHash -LiteralPath $egPublished -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Encoding ascii -LiteralPath (Join-Path $egOutput 'SHA256.txt') -Value "$egHash  eg4d20_udp_loop.bit"
# A previous simulation/hardware report must not be presented as proof for a new build.
$egSources = [ordered]@{}
Get-Content -LiteralPath (Join-Path $PSScriptRoot 'sources.txt') | Where-Object { $_.Trim() } | ForEach-Object {
    $egSources[$_] = (Get-FileHash -LiteralPath (Join-Path $egRoot $_) -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach ($egConstraint in @('uisrc/04_pin/fpga_pin.adc','uisrc/04_pin/timing.sdc')) {
    $egSources[$egConstraint] = (Get-FileHash -LiteralPath (Join-Path $egRoot $egConstraint) -Algorithm SHA256).Hash.ToLowerInvariant()
}
[ordered]@{ built_at = (Get-Date).ToString('o'); bit_sha256 = $egHash; source_sha256 = $egSources; timing_report = 'final_timing.rpt'; simulation = 'Run tests/run_gmii.py for this source revision'; hardware = 'Not verified by this build'; full_logs = $egBank } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $egOutput 'validation.json')
Write-Host "BUILD PASS: $egPublished"
Write-Host "SHA256: $egHash"
