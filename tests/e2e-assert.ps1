# Assertions for the windows-e2e workflow (ASCII only: no BOM, Windows PowerShell 5.1).
# Run after install.ps1 has installed Claude and configured it against the
# fake CPA from tests/mock-cpa-server.py.
param(
    [Parameter(Mandatory)][string]$MockLog,
    [ValidateSet('first', 'second')][string]$Stage = 'first'
)
$ErrorActionPreference = 'Stop'

$expectedModels = 'claude-sonnet-5-5,claude-opus-5-5,claude-haiku-5-5,sonnet-4-5-cpa,haiku-4-5-cpa'

$base = Join-Path $env:LOCALAPPDATA 'Claude-3p'
$packaged = Join-Path $env:LOCALAPPDATA 'Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\Claude-3p'
$support = $base
if (-not (Test-Path (Join-Path $base 'configLibrary\_meta.json'))) { $support = $packaged }
Write-Host "stage: $Stage; support dir: $support"

# The package is installed for this user.
$pkg = Get-AppxPackage -Name Claude | Where-Object PackageFamilyName -eq 'Claude_pzs8sxrjxfjjc'
if (-not $pkg) { throw 'Claude MSIX is not installed' }
Write-Host "package: Claude $($pkg.Version) at $($pkg.InstallLocation)"

# The 3P profile points at the fake CPA and lists exactly the reachable models.
$meta = Get-Content -Raw (Join-Path $support 'configLibrary\_meta.json') | ConvertFrom-Json
$prof = Get-Content -Raw (Join-Path $support ('configLibrary\' + $meta.appliedId + '.json')) | ConvertFrom-Json
$desktop = Get-Content -Raw (Join-Path $support 'claude_desktop_config.json') | ConvertFrom-Json
$names = (@($prof.inferenceModels) | ForEach-Object { $_.name }) -join ','
Write-Host "models: $names"
if ($names -ne $expectedModels) { throw "unexpected models: $names" }
if ($prof.inferenceProvider -ne 'gateway') { throw 'provider is not gateway' }
if ($prof.inferenceGatewayBaseUrl -ne 'http://127.0.0.1:8787') { throw 'wrong gateway url' }
if ($desktop.deploymentMode -ne '3p') { throw 'deploymentMode is not 3p' }

# What the installer asked the fake CPA, and that every request used the right key.
$entries = @(Get-Content $MockLog | ForEach-Object { $_ | ConvertFrom-Json })
$entries | Group-Object method, path, model, key_ok | ForEach-Object { Write-Host ('  {0}  x{1}' -f $_.Name, $_.Count) }
if (@($entries | Where-Object { -not $_.key_ok }).Count -gt 0) { throw 'a request reached the fake CPA with a wrong key' }
$probed = @($entries | Where-Object { $_.method -eq 'POST' } | ForEach-Object { $_.model })
foreach ($alias in 'sonnet-4-5-cpa', 'haiku-4-5-cpa', 'opus-6-2-astra-cpa', 'sonnet-6-2-sol-cpa', 'haiku-6-luna-cpa', 'sonnet-4-argon-cpa', 'claude-haiku-5-5') {
    if ($probed -notcontains $alias) { throw "the installer never probed $alias" }
}

# Claude is running and reported the gateway in its own log.
$procs = @(Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object {
        $path = $null
        try { $path = $_.Path } catch { $path = $null }
        $path -and $path -like '*\WindowsApps\Claude_*'
    })
if ($procs.Count -eq 0) { throw 'Claude is not running' }
Write-Host "claude processes: $($procs.Count)"
$log = Join-Path $support 'Logs\main.log'
if (-not (Test-Path $log)) { throw "no Claude log at $log" }
if (-not (Select-String -Path $log -SimpleMatch "provider: 'gateway'" -Quiet)) {
    Get-Content $log -Tail 40 | ForEach-Object { Write-Host "  log: $_" }
    throw "Claude's log has no provider: 'gateway' line"
}
Write-Host 'OK: configuration, probes and the running app match what is expected.'
