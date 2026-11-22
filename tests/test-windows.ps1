# Offline tests for install.ps1. Runs in Windows PowerShell 5.1 and PowerShell 7.
# Every helper reads USERPROFILE / LOCALAPPDATA at call time, so both point at
# a temporary folder for the whole run: real user settings are never read.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repo 'install.ps1'

$fake = Join-Path ([System.IO.Path]::GetTempPath()) ('cpa-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fake
$realProfile = $env:USERPROFILE
$realLocal = $env:LOCALAPPDATA
$env:USERPROFILE = Join-Path $fake 'home'
$env:LOCALAPPDATA = Join-Path $fake 'local'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $env:USERPROFILE '.claude'), (Join-Path $env:USERPROFILE '.codex'), (Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary')
$env:CPA_API_KEY = $null
$env:CPA_INSTALL_SOURCE_ONLY = '1'

$failures = 0
function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    # Values are never printed: a mistake here must not leak a real key.
    if ([string]$Actual -ne [string]$Expected) {
        Write-Host ("FAIL: {0}: unexpected value (length {1}, expected length {2})" -f $Name, ([string]$Actual).Length, ([string]$Expected).Length) -ForegroundColor Red
        $script:failures++
    } else { Write-Host ("ok   {0}" -f $Name) }
}
function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { Write-Host ("FAIL: {0}" -f $Name) -ForegroundColor Red; $script:failures++ }
    else { Write-Host ("ok   {0}" -f $Name) }
}
function Write-TestFile {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

try {
    # Read as UTF-8 explicitly: Windows PowerShell 5.1 would otherwise use the
    # ANSI code page for a file without a BOM.
    $text = [System.IO.File]::ReadAllText($installer, [System.Text.Encoding]::UTF8)
    . ([scriptblock]::Create($text))

    # --- parsing, encoding and help --------------------------------------------
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    Assert-True 'install.ps1 parses without errors' ($errors.Count -eq 0)
    $raw = [System.IO.File]::ReadAllBytes($installer)
    Assert-True 'install.ps1 has no BOM (a BOM breaks `irm | iex`)' (-not ($raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF))

    $helpText = (& { Show-CpaUsage } 6>&1 | Out-String)
    foreach ($needle in @('-Check', '-DryRun', '-ConfigureOnly', '-AskKey', '-Yes', '-BaseUrl', 'CPA_API_KEY', 'irm ', 'scriptblock')) {
        Assert-True ("help mentions $needle") ($helpText.Contains($needle))
    }

    # `irm | iex` hands the whole text to Invoke-Expression.
    $null = Invoke-Expression $text
    Assert-True 'script text loads through Invoke-Expression' ($null -ne (Get-Command Get-CpaPublisherId -ErrorAction SilentlyContinue))

    # --- static invariants ----------------------------------------------------
    Assert-Equal 'pinned package family' $script:CpaConst.PackageFamily 'Claude_pzs8sxrjxfjjc'
    Assert-True 'no hardcoded API key' (-not ($text -match 'sk-(clb|ant)-[A-Za-z0-9_-]{20,}'))

    # --- helpers ----------------------------------------------------------------
    Assert-Equal 'publisher id algorithm (Microsoft reference)' (Get-CpaPublisherId 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US') '8wekyb3d8bbwe'
    Assert-Equal 'url host' (Get-CpaUrlHost 'https://User@CPA.2brain.pro:443/v1/') 'cpa.2brain.pro'
    Assert-Equal 'url host of garbage' (Get-CpaUrlHost 'not a url') ''
    Assert-True 'version compare' ((ConvertTo-CpaVersion '6.28899.7') -gt (ConvertTo-CpaVersion '6.28899.6.0'))
    Assert-True 'same version is not newer' (-not ((ConvertTo-CpaVersion '6.28899.6') -gt (ConvertTo-CpaVersion '6.28899.6.0')))

    $manifest = @"
PackageIdentifier: Anthropic.Claude
PackageVersion: 6.28899.6
Installers:
- Platform:
  - Windows.Desktop
  MinimumOSVersion: 10.0.19041.0
  Architecture: x64
  InstallerType: msix
  InstallerUrl: https://downloads.claude.ai/releases/win32/x64/6.28899.6/Claude-abc.msix
  InstallerSha256: AAAA
  PackageFamilyName: Claude_pzs8sxrjxfjjc
- Platform:
  - Windows.Desktop
  Architecture: arm64
  InstallerType: msix
  InstallerUrl: https://downloads.claude.ai/releases/win32/arm64/6.28899.6/Claude-abc.msix
  InstallerSha256: BBBB
- Architecture: x64
  InstallerType: exe
  Scope: user
  InstallerUrl: https://downloads.claude.ai/releases/win32/x64/6.28899.6/Claude-abc.exe
  InstallerSha256: CCCC
  InstallerSwitches:
    Silent: --silent
ManifestType: installer
"@
    $entries = @(ConvertFrom-CpaWingetInstaller $manifest)
    Assert-Equal 'winget manifest: installer count' $entries.Count 3
    $x64 = $entries | Where-Object { $_['Architecture'] -eq 'x64' -and $_['InstallerType'] -eq 'msix' } | Select-Object -First 1
    Assert-Equal 'winget manifest: x64 msix sha' $x64['InstallerSha256'] 'AAAA'
    $arm = $entries | Where-Object { $_['Architecture'] -eq 'arm64' -and $_['InstallerType'] -eq 'msix' } | Select-Object -First 1
    Assert-Equal 'winget manifest: arm64 msix url' $arm['InstallerUrl'] 'https://downloads.claude.ai/releases/win32/arm64/6.28899.6/Claude-abc.msix'

    # --- key discovery: only keys tied to the CPA host are used ---------------
    $cpaHost = 'cpa.2brain.pro'
    $claudeSettings = Join-Path $env:USERPROFILE '.claude\settings.json'
    Write-TestFile $claudeSettings '{"env": {"ANTHROPIC_API_KEY": "direct-anthropic-key"}}'
    Assert-Equal 'claude settings without CPA base' (Get-CpaKeyFromClaudeSetting $cpaHost) ''
    Write-TestFile $claudeSettings '{"env": {"ANTHROPIC_BASE_URL": "https://api.anthropic.com", "ANTHROPIC_AUTH_TOKEN": "other-key"}}'
    Assert-Equal 'claude settings with other base' (Get-CpaKeyFromClaudeSetting $cpaHost) ''
    Write-TestFile $claudeSettings '{"env": {"ANTHROPIC_BASE_URL": "https://cpa.2brain.pro", "ANTHROPIC_AUTH_TOKEN": "cpa-key-from-claude"}}'
    Assert-Equal 'claude settings with CPA base' (Get-CpaKeyFromClaudeSetting $cpaHost) 'cpa-key-from-claude'

    $codex = Join-Path $env:USERPROFILE '.codex\config.toml'
    Write-TestFile $codex "api_key = `"top-level-openai-key`"`n`n[model_providers.openai]`nbase_url = `"https://api.openai.com/v1`"`napi_key = `"openai-key`"`n"
    Assert-Equal 'codex without CPA provider' (Get-CpaKeyFromCodex $cpaHost) ''
    Write-TestFile $codex "[model_providers.openai]`nbase_url = `"https://api.openai.com/v1`"`napi_key = `"openai-key`"`n`n[model_providers.cpa]`nname = `"CPA`"`nbase_url = `"https://cpa.2brain.pro/v1`"`n`n[model_providers.cpa.http_headers]`n`"X-Api-Key`" = `"cpa-key-from-codex`"`n"
    Assert-Equal 'codex with CPA provider (header table)' (Get-CpaKeyFromCodex $cpaHost) 'cpa-key-from-codex'
    Write-TestFile $codex "[model_providers.cpa]`nbase_url = `"https://cpa.2brain.pro/v1`"`nexperimental_bearer_token = `"cpa-bearer`"`n"
    Assert-Equal 'codex with CPA provider (bearer)' (Get-CpaKeyFromCodex $cpaHost) 'cpa-bearer'

    Assert-Equal 'support dir defaults to %LOCALAPPDATA%\Claude-3p' (Get-CpaSupportDir) (Join-Path $env:LOCALAPPDATA 'Claude-3p')
    $lib = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
    Write-TestFile (Join-Path $lib '_meta.json') '{"appliedId": "p1", "entries": [{"id": "p1", "name": "Other"}]}'
    Write-TestFile (Join-Path $lib 'p1.json') '{"inferenceGatewayBaseUrl": "https://gw.example.com", "inferenceGatewayApiKey": "gw-key"}'
    Assert-Equal 'profile with other gateway' (Get-CpaKeyFromProfile $cpaHost) ''
    Write-TestFile (Join-Path $lib 'p1.json') '{"inferenceGatewayBaseUrl": "https://cpa.2brain.pro", "inferenceGatewayApiKey": "cpa-key-from-profile"}'
    Assert-Equal 'profile with CPA gateway' (Get-CpaKeyFromProfile $cpaHost) 'cpa-key-from-profile'

    # --- key resolution without network (validation and prompts are stubbed) --
    function Test-CpaKey { param([string]$ApiKey) return ($ApiKey -eq 'new-key') }
    function Test-CpaInteractive { return $script:fakeInteractive }
    function Read-CpaSecret { param([string]$Prompt) return 'new-key' }

    $script:fakeInteractive = $false
    $script:Opt.AskKey = $true; $script:Opt.Yes = $true
    $message = ''
    try { $null = Resolve-CpaKey } catch { $message = $_.Exception.Message }
    Assert-True '-AskKey with -Yes refuses to run' ($message -match '-AskKey')

    $script:Opt.AskKey = $false; $script:Opt.Yes = $false; $script:Opt.Force = $false
    $message = ''
    try { $null = Resolve-CpaKey } catch { $message = $_.Exception.Message }
    Assert-True 'a rejected stored key points the user to -AskKey' ($message -match '-AskKey')

    $script:fakeInteractive = $true
    $script:CpaKey = ''; $script:CpaKeySource = ''
    $null = Resolve-CpaKey 6>$null
    Assert-Equal 'rejected stored key falls back to a prompt' ($script:CpaKey + '|' + $script:CpaKeySource) 'new-key|interactive'

    # --- configuration writing ---------------------------------------------------
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Claude-3p') -Recurse -Force
    $script:CpaKey = 'test-key-1'
    $script:Opt.BaseUrl = 'https://cpa.2brain.pro'
    $script:Opt.WithChat = $false
    Write-CpaConfig 6>$null
    $support = Join-Path $env:LOCALAPPDATA 'Claude-3p'
    $meta = Get-Content -Raw -LiteralPath (Join-Path $support 'configLibrary\_meta.json') | ConvertFrom-Json
    $profilePath = Join-Path $support ('configLibrary\' + $meta.appliedId + '.json')
    $profileText = Get-Content -Raw -LiteralPath $profilePath
    $profileData = $profileText | ConvertFrom-Json
    $desktop = Get-Content -Raw -LiteralPath (Join-Path $support 'claude_desktop_config.json') | ConvertFrom-Json
    Assert-Equal 'meta entries is a list with one CPA entry' (@($meta.entries).Count) 1
    Assert-True 'meta entries is serialized as a JSON array' ((Get-Content -Raw -LiteralPath (Join-Path $support 'configLibrary\_meta.json')) -match '"entries":\s*\[')
    Assert-Equal 'meta entry name' (@($meta.entries)[0].name) 'CPA'
    Assert-Equal 'profile provider' $profileData.inferenceProvider 'gateway'
    Assert-Equal 'profile base url' $profileData.inferenceGatewayBaseUrl 'https://cpa.2brain.pro'
    Assert-Equal 'profile key' $profileData.inferenceGatewayApiKey 'test-key-1'
    Assert-Equal 'profile auth scheme' $profileData.inferenceGatewayAuthScheme 'x-api-key'
    Assert-Equal 'profile models' ((@($profileData.inferenceModels) | ForEach-Object { $_.name }) -join ',') 'claude-sonnet-5-5,claude-opus-5-5,claude-haiku-5-5'
    Assert-True 'egress hosts is a JSON array' ($profileText -match '"coworkEgressAllowedHosts":\s*\[\s*"\*"\s*\]')
    Assert-Equal 'chat tab disabled' ([string]$profileData.chatTabEnabled) 'False'
    Assert-Equal 'deploymentMode' $desktop.deploymentMode '3p'
    Assert-Equal 'sidebar mode seeded' $desktop.preferences.sidebarMode 'code'
    $firstBytes = [System.IO.File]::ReadAllBytes($profilePath)
    Assert-True 'profile is written without a BOM' (-not ($firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB))

    # Running again reuses the same profile and keeps existing preferences.
    $desktop.preferences.sidebarMode = 'epitaxy'
    Write-TestFile (Join-Path $support 'claude_desktop_config.json') (ConvertTo-Json -InputObject $desktop -Depth 10)
    $script:CpaKey = 'test-key-2'
    Write-CpaConfig 6>$null
    $meta2 = Get-Content -Raw -LiteralPath (Join-Path $support 'configLibrary\_meta.json') | ConvertFrom-Json
    $profile2 = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
    $desktop2 = Get-Content -Raw -LiteralPath (Join-Path $support 'claude_desktop_config.json') | ConvertFrom-Json
    Assert-Equal 'second run reuses the profile id' $meta2.appliedId $meta.appliedId
    Assert-Equal 'second run keeps one entry' (@($meta2.entries).Count) 1
    Assert-Equal 'second run updates the key' $profile2.inferenceGatewayApiKey 'test-key-2'
    Assert-Equal 'second run keeps the sidebar choice' $desktop2.preferences.sidebarMode 'epitaxy'
    Assert-True 'backups are created' ((Get-ChildItem -LiteralPath (Join-Path $support '.cpa-backups') -Directory).Count -ge 1)

    $state = Get-CpaConfigState
    Assert-Equal 'config state: provider' $state.provider 'gateway'
    Assert-Equal 'config state: base matches' $state.base_matches 'yes'
    Assert-Equal 'config state: key kind' $state.key_kind 'direct'
    Assert-Equal 'config state: deploymentMode' $state.deploymentMode '3p'
} finally {
    $env:USERPROFILE = $realProfile
    $env:LOCALAPPDATA = $realLocal
    $env:CPA_INSTALL_SOURCE_ONLY = $null
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host ("{0} test(s) failed" -f $failures) -ForegroundColor Red
    exit 1
}
Write-Host 'windows tests OK'
