# Offline tests for install.ps1. Runs in Windows PowerShell 5.1 and PowerShell 7.
# Every helper reads USERPROFILE / LOCALAPPDATA at call time, so both point at
# a temporary folder for the whole run: real user settings are never read.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'Users start the installer with `irm | iex`; the test reproduces exactly that.')]
[CmdletBinding()]
param()
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
    foreach ($needle in @('-Check', '-DryRun', '-ConfigureOnly', '-AskKey', '-Yes', '-BaseUrl', '-AddModel', '-RemoveModel', '-ListModels', '-ClaudeOnly', 'CPA_API_KEY', 'irm ', 'scriptblock')) {
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
    function Read-CpaSecret { param([string]$Prompt) $null = $Prompt; return 'new-key' }

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

    # --- key input ---------------------------------------------------------------------
    # This file is ASCII only: build the lookalike with a character code.
    $esc = [string][char]27
    Assert-Equal 'clean key strips paste markers, control characters and spaces' (ConvertTo-CpaCleanKey ($esc + '[200~  sk-abc-123 ' + [char]9 + $esc + '[201~' + [char]13)) 'sk-abc-123'
    Assert-Equal 'clean key keeps the inside of a key' (ConvertTo-CpaCleanKey 'sk-ab c') 'sk-ab c'
    Assert-Equal 'clean key of nothing is empty' (ConvertTo-CpaCleanKey $null) ''

    $diag = (& { Write-CpaKeyDiagnostic 'sk-clb-abc' } 6>&1 | Out-String)
    Assert-True 'diagnostic reports length and fingerprint' ($diag -match ': 10, [^:]+: [0-9a-f]{8}\.')
    Assert-True 'diagnostic never prints the key' (-not $diag.Contains('sk-clb-abc'))
    Assert-True 'a plain key gets no extra hint' ((([regex]::Matches($diag, 'WARN')).Count -eq 1))
    $lookalike = 'sk-' + [char]0x0441 + 'lb-abc'
    $diag = (& { Write-CpaKeyDiagnostic $lookalike } 6>&1 | Out-String)
    Assert-True 'diagnostic flags a Cyrillic lookalike' (($diag -match '\u043d\u0435\u0432\u0438\u0434\u0438\u043c\u044b\u0435') -and -not ($diag -match '\u043f\u0440\u043e\u0431\u0435\u043b'))
    Assert-Equal 'a lookalike key counts its UTF-8 bytes' ([regex]::Match($diag, ': (\d+),').Groups[1].Value) '11'
    $diag = (& { Write-CpaKeyDiagnostic 'sk-clb abc' } 6>&1 | Out-String)
    Assert-True 'diagnostic mentions a space inside the key' (($diag -match '\u043f\u0440\u043e\u0431\u0435\u043b') -and -not ($diag -match '\u043d\u0435\u0432\u0438\u0434\u0438\u043c\u044b\u0435'))

    # --- models --------------------------------------------------------------------
    Assert-True 'main models are on by default' ([bool]$script:Opt.MainModels)
    $modelFile = Get-CpaModelFile
    Assert-Equal 'models file lives under %LOCALAPPDATA%' $modelFile (Join-Path $env:LOCALAPPDATA 'claude-desktop-cpa\models.json')

    # Parity with install.sh: the same main models and the same vendor filter.
    $sh = [System.IO.File]::ReadAllText((Join-Path $repo 'install.sh'), [System.Text.Encoding]::UTF8)
    $specBlock = ($sh -split 'MAIN_MODEL_SPECS=\(')[1].Split(')')[0]
    $shSpecs = @([regex]::Matches($specBlock, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
    $psSpecs = @($script:CpaConst.MainModels | ForEach-Object { '{0}={1}={2}' -f $_.name, $_.label, $_.behavesAs })
    Assert-True 'install.sh lists main models' ($shSpecs.Count -ge 1)
    Assert-Equal 'main models match install.sh' ($psSpecs -join '|') ($shSpecs -join '|')
    $regexBlock = ($sh -split 'NON_ANTHROPIC = re\.compile\(')[1].Split([string[]]@('re.I,'), [StringSplitOptions]::None)[0]
    $shPattern = -join @([regex]::Matches($regexBlock, 'r"([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
    Assert-Equal 'vendor-name filter matches install.sh' $script:CpaConst.NonAnthropicRegex.ToString() $shPattern

    # Claude Desktop drops names with another vendor's keyword, so they are rejected.
    $message = ''
    try { Update-CpaModelFile -Mode add -Spec 'opencode-go/deepseek-v4-pro=DeepSeek V4 Pro' } catch { $message = $_.Exception.Message }
    Assert-True 'a non-Anthropic model ID is rejected' ($message -match 'deepseek')
    Assert-True 'a rejected model is not written' (-not (Test-Path -LiteralPath $modelFile))

    Update-CpaModelFile -Mode add -Spec 'claude-opus-4-8=Opus 4.8', 'acme-sonnet-cpa=Acme Sonnet', 'opencode-go/claude-sonnet-4-5-cpa=DeepSeek V4 Pro=claude-sonnet-5' 6>$null
    $saved = @(Read-CpaModelFile)
    Assert-Equal 'saved model count' $saved.Count 3
    Assert-Equal 'tier from the model ID' $saved[0]['anthropicFamilyTier'] 'opus'
    Assert-Equal 'label is kept' $saved[0]['labelOverride'] 'Opus 4.8'
    Assert-Equal 'tier from a family name inside the ID' $saved[1]['anthropicFamilyTier'] 'sonnet'
    Assert-Equal 'behavesAs is saved' $saved[2]['behavesAs'] 'claude-sonnet-5'
    Assert-Equal 'tier follows behavesAs' $saved[2]['anthropicFamilyTier'] 'sonnet'
    Assert-True 'models.json is a JSON array' ((Get-Content -Raw -LiteralPath $modelFile).TrimStart().StartsWith('['))

    Update-CpaModelFile -Mode add -Spec 'claude-opus-4-8=Opus 4.8 (CPA)' 6>$null
    $saved = @(Read-CpaModelFile)
    Assert-Equal 'the same ID is updated in place' $saved.Count 3
    Assert-Equal 'updated label' $saved[0]['labelOverride'] 'Opus 4.8 (CPA)'

    # The config writer keeps the built-in models first and appends extras.
    $script:CpaKey = 'test-key-3'
    Write-CpaConfig 6>$null
    $profileData = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
    Assert-Equal 'extras follow the three built-ins' ((@($profileData.inferenceModels) | ForEach-Object { $_.name }) -join ',') 'claude-sonnet-5-5,claude-opus-5-5,claude-haiku-5-5,claude-opus-4-8,acme-sonnet-cpa,opencode-go/claude-sonnet-4-5-cpa'

    # A hand-edited models.json cannot inject unknown keys, duplicates or nameless entries.
    Write-TestFile $modelFile '[{"name":"claude-haiku-x","evil":"1","anthropicFamilyTier":"bogus"},{"name":"claude-sonnet-5-5"},{"nope":1},"text"]'
    Write-CpaConfig 6>$null
    $profileData = Get-Content -Raw -LiteralPath $profilePath | ConvertFrom-Json
    $custom = @($profileData.inferenceModels) | Where-Object { $_.name -eq 'claude-haiku-x' }
    Assert-Equal 'only one valid extra model is written' (@($profileData.inferenceModels).Count) 4
    Assert-True 'unknown keys are dropped' (-not $custom.PSObject.Properties['evil'])
    Assert-Equal 'an invalid tier is recomputed' $custom.anthropicFamilyTier 'haiku'

    Remove-Item -LiteralPath $modelFile -Force
    Update-CpaModelFile -Mode add -Spec 'a-sonnet=A', 'b-opus=B' 6>$null
    Update-CpaModelFile -Mode remove -Spec 'a-sonnet' 6>$null
    Assert-Equal 'remove keeps the other models' ((@(Read-CpaModelFile) | ForEach-Object { $_['name'] }) -join ',') 'b-opus'
    Update-CpaModelFile -Mode remove -Spec 'b-opus' 6>$null
    # Windows PowerShell 5.1 puts line breaks inside the empty array, so ignore whitespace.
    Assert-Equal 'removing everything leaves an empty JSON array' ((Get-Content -Raw -LiteralPath $modelFile) -replace '\s', '') '[]'

    # Main models and -ListModels, with the HTTP layer stubbed.
    $script:stubStatus = @{}
    function Invoke-CpaHttp {
        param([string]$Method = 'GET', [string]$Url, [hashtable]$Headers = @{}, [string]$Body = $null, [int]$TimeoutSec = 25)
        $null = $Method, $Headers, $TimeoutSec
        if ($Url.EndsWith('/v1/models')) {
            return @{ Status = 200; Body = '{"data":[{"id":"claude-sonnet-5-5"},{"id":"Claude-Opus-4-8"},{"id":"gpt-x"}]}' }
        }
        $model = ''
        if ($Body) { $model = [string](($Body | ConvertFrom-Json).model) }
        $code = 401
        if ($script:stubStatus.ContainsKey($model)) { $code = $script:stubStatus[$model] }
        $reply = '{"type":"error"}'
        if ($code -eq 200) { $reply = '{"type":"message"}' }
        return @{ Status = $code; Body = $reply }
    }
    $script:CpaKey = 'new-key'
    Remove-Item -LiteralPath $modelFile -Force
    $script:stubStatus = @{ 'sonnet-4-5-cpa' = 200; 'haiku-4-5-cpa' = 429; 'opus-6-2-astra-cpa' = 503; 'sonnet-6-2-sol-cpa' = 401 }
    Add-CpaMainModel 6>$null
    $added = @(Read-CpaModelFile)
    Assert-Equal 'only reachable main models are added (429 and 5xx count as reachable)' (($added | ForEach-Object { $_['name'] }) -join ',') 'sonnet-4-5-cpa,haiku-4-5-cpa,opus-6-2-astra-cpa'
    Assert-Equal 'main model label' $added[0]['labelOverride'] 'DeepSeek V4 Pro'
    Assert-Equal 'main model behavesAs' $added[0]['behavesAs'] 'claude-sonnet-5'

    Remove-Item -LiteralPath $modelFile -Force
    $script:stubStatus = @{}
    Add-CpaMainModel 6>$null
    Assert-True 'nothing is written when no main model is reachable' (-not (Test-Path -LiteralPath $modelFile))

    $env:CPA_API_KEY = 'new-key'
    $script:Opt.Key = ''
    $listing = (Show-CpaModelList 6>&1 | Out-String)
    $env:CPA_API_KEY = $null
    Assert-True '-ListModels shows Claude models' ($listing.Contains('claude-sonnet-5-5') -and $listing.Contains('Claude-Opus-4-8'))
    # This file has no BOM, so it must stay ASCII (Windows PowerShell 5.1 reads it as ANSI).
    Assert-True '-ListModels counts the other models' ($listing -match ': 1\. ')
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
