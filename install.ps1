<#
  claude-desktop-cpa (Windows)

  Installs or updates Claude Desktop (MSIX) on Windows and configures its
  native "third-party inference" (3P) mode to use CPA.

  Design notes:
  - 3P data lives in %LOCALAPPDATA%\Claude-3p (Anthropic docs). With the MSIX
    package on Windows builds before 22000 it can instead be at
    %LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\Claude-3p.
  - Gateway config: Claude-3p\configLibrary\<uuid>.json, selected by
    configLibrary\_meta.json:appliedId. Claude-3p\claude_desktop_config.json
    holds deploymentMode = "3p".
  - Install source: the official MSIX from downloads.claude.ai. The URL and
    SHA256 come from the winget manifest (microsoft/winget-pkgs). The package
    must be named "Claude" and its publisher must hash to the Anthropic
    publisher ID pzs8sxrjxfjjc; Windows verifies the signature on install.
  - Never downgrades. A legacy .exe install is left alone (it updates itself).
  - The CPA key is never printed and never passed on a command line. Keys
    from Claude Code / Codex settings are reused only when those settings
    already point at the same CPA host.
  - Works in Windows PowerShell 5.1 and PowerShell 7. Safe for `irm | iex`:
    it never calls `exit` in that case, so the user's window stays open.
  - Encoding: this file is UTF-8 WITHOUT a BOM. `irm` decodes it correctly
    (GitHub serves charset=utf-8), while a BOM would reach `iex` as a stray
    character and break parsing. Windows PowerShell 5.1 reads a BOM-less
    file in the ANSI code page, so a downloaded copy must be run as:
      & ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1)))
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$DryRun,
    [switch]$ConfigureOnly,
    [switch]$NoUpdate,
    [switch]$NoRestart,
    [switch]$WithChat,
    [switch]$Force,
    [switch]$Yes,
    [switch]$AskKey,
    [switch]$WithMainModels,
    [switch]$ClaudeOnly,
    [switch]$ListModels,
    [switch]$VerifyDownload,
    [switch]$Help,
    [string[]]$AddModel = @(),
    [string[]]$RemoveModel = @(),
    [string]$Key = '',
    [string]$BaseUrl = 'https://cpa.2brain.pro'
)

# Claude Desktop silently drops inferenceModels whose names contain another
# vendor's name. Keep in sync with NON_ANTHROPIC in install.sh (a test checks it).
$script:CpaNonAnthropicPattern = 'ark-code|astron|command-r|deepseek|doubao|gemini|gemma|glm|gpt|grok|' +
    'hermes|hy3|kimi|lfm|\bling\b|llama|longcat|mimo|minimax|mistral|' +
    'mixtral|moonshot|nemotron|openai|phi-|qianfan|qwen|tc-code|\bunic\b|' +
    'yi-|stepfun|step-3|seed-|bytedance|hunyuan|granite|amazon\.nova|nova-|' +
    'devstral|ministral|ernie|codex|arcee|trinity|abab|phi\d|\bk2\.|\bm2\.|' +
    'jamba|arctic|solar|mercury|zamba|kat-coder|\bds-|dpsk/'

$script:CpaConst = @{
    PackageName   = 'Claude'
    PublisherId   = 'pzs8sxrjxfjjc'
    PackageFamily = 'Claude_pzs8sxrjxfjjc'
    ProfileName   = 'CPA'
    ModelHaiku    = 'claude-haiku-5-5'
    Models        = @(
        @{ name = 'claude-sonnet-5-5'; label = 'Claude Sonnet 5.5'; tier = 'sonnet' },
        @{ name = 'claude-opus-5-5';   label = 'Claude Opus 5.5';   tier = 'opus' },
        @{ name = 'claude-haiku-5-5';  label = 'Claude Haiku 5.5';  tier = 'haiku' }
    )
    ModelTiers    = @('fable', 'mythos', 'opus', 'haiku', 'sonnet')
    ModelKeys     = @('name', 'labelOverride', 'supports1m', 'prefer1m', 'anthropicFamilyTier', 'isFamilyDefault', 'behavesAs', 'maxEffort')
    NonAnthropicRegex = [regex]::new($script:CpaNonAnthropicPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    # Main non-Claude models. Keep in sync with MAIN_MODEL_SPECS in install.sh
    # and scripts/sync-cpa-main-models.py (a test checks install.sh).
    MainModels    = @(
        @{ name = 'sonnet-4-5-cpa';      label = 'DeepSeek V4 Pro';     behavesAs = 'claude-sonnet-5' },
        @{ name = 'haiku-4-5-cpa';       label = 'DeepSeek V4.1 Flash'; behavesAs = 'claude-haiku-5-5' },
        @{ name = 'opus-6-2-astra-cpa';  label = 'GPT 6.2 Astra';       behavesAs = 'claude-opus-5-5' },
        @{ name = 'sonnet-6-2-sol-cpa';  label = 'GPT 6.2 Sol';         behavesAs = 'claude-sonnet-5' },
        @{ name = 'haiku-6-luna-cpa';    label = 'GPT-6 Luna';          behavesAs = 'claude-haiku-5-5' },
        @{ name = 'sonnet-4-argon-cpa';  label = 'Gemini 4 Argon';      behavesAs = 'claude-sonnet-5' }
    )
    CaskUrl       = 'https://formulae.brew.sh/api/cask/claude.json'
    WingetRaw     = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/a/Anthropic/Claude'
    WingetApi     = 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/a/Anthropic/Claude'
    DownloadHost  = 'downloads.claude.ai'
}

$script:Opt = @{
    Check          = [bool]$Check
    DryRun         = [bool]$DryRun
    ConfigureOnly  = [bool]$ConfigureOnly
    NoUpdate       = [bool]$NoUpdate
    NoRestart      = [bool]$NoRestart
    WithChat       = [bool]$WithChat
    Force          = [bool]$Force
    Yes            = [bool]$Yes
    AskKey         = [bool]$AskKey
    MainModels     = $(if ($WithMainModels) { $true } else { -not $ClaudeOnly })
    ListModels     = [bool]$ListModels
    AddModel       = @($AddModel | Where-Object { $_ })
    RemoveModel    = @($RemoveModel | Where-Object { $_ })
    VerifyDownload = [bool]$VerifyDownload
    Help           = [bool]$Help
    Key            = [string]$Key
    BaseUrl        = [string]$BaseUrl
}

$script:CpaKey = ''
$script:CpaKeySource = ''

# --- output ------------------------------------------------------------------

function Write-CpaLog {
    param([string]$Message = '')
    Write-Host $Message
}

function Write-CpaWarn {
    param([string]$Message)
    Write-Host ('WARN: ' + $Message) -ForegroundColor Yellow
}

function Stop-Cpa {
    param([string]$Message)
    throw [System.InvalidOperationException]::new($Message)
}

function Show-CpaUsage {
    Write-Host @'
claude-desktop-cpa — установка/обновление Claude Desktop на Windows и настройка CPA.

Запуск одной командой (PowerShell):
  irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 | iex

Запуск с параметрами без скачивания файла:
  & ([scriptblock]::Create((irm <адрес install.ps1>))) -Check

Запуск скачанной копии (так PowerShell правильно прочитает русский текст):
  & ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1))) -Check

Параметры:
  -Check           Только проверить состояние, ничего не менять.
  -DryRun          Показать план действий, ничего не менять.
  -ConfigureOnly   Не устанавливать и не обновлять приложение.
  -NoUpdate        Не обновлять приложение.
  -NoRestart       Записать настройку, но не запускать Claude.
  -WithChat        Показать вкладку Chat (ей нужен вход в claude.ai).
  -WithMainModels  Добавить основные модели CPA (включено по умолчанию).
  -ClaudeOnly      Не добавлять основные модели CPA (DeepSeek, GPT, Gemini).
                   Модели, добавленные раньше, остаются в списке; чтобы
                   убрать их, используйте -RemoveModel.
  -ListModels      Показать модели Claude, доступные ключу CPA.
  -AddModel SPEC   Добавить модель в список Claude. SPEC: ID, ID=Подпись
                   или ID=Подпись=Claude-модель. Можно несколько через запятую.
                   Пример: -AddModel 'claude-opus-4-8=Opus 4.8'
  -RemoveModel ID  Убрать модель, добавленную через -AddModel.
  -Yes             Не задавать вопросов (если ключ уже найден).
  -AskKey          Не искать сохранённый ключ, а спросить новый
                   (например, после замены или отзыва ключа).
  -Force           Записать настройку, даже если проверка ключа не прошла.
  -Key KEY         CPA API-ключ. Ключ, набранный в команде, остаётся
                   в истории PowerShell; безопаснее ввести его по запросу.
  -BaseUrl URL     Адрес CPA (по умолчанию https://cpa.2brain.pro).
  -VerifyDownload  Только скачать и проверить установщик (для проверок CI).
  -Help            Эта справка.

Ключ ищется в таком порядке:
  1. -Key
  2. переменная окружения CPA_API_KEY
  3. текущий профиль Claude-3p, если он смотрит на тот же адрес CPA
  4. %USERPROFILE%\.claude\settings.json (ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY),
     только если ANTHROPIC_BASE_URL указывает на тот же адрес CPA
  5. %USERPROFILE%\.codex\config.toml, только из раздела провайдера, у которого
     base_url указывает на тот же адрес CPA
  6. ввод по запросу
Ключи для других сервисов (например, прямые ключи Anthropic или OpenAI)
не используются и никуда не отправляются.

Список моделей:
  - по умолчанию: claude-sonnet-5-5, claude-opus-5-5, claude-haiku-5-5;
  - -AddModel добавляет модель в inferenceModels и сохраняет выбор в
    %LOCALAPPDATA%\claude-desktop-cpa\models.json, поэтому повторный запуск
    установщика его не потеряет;
  - для моделей не от Anthropic нужен alias с «claude-» или названием
    семейства (sonnet, haiku) в имени, опубликованный в CPA; третий элемент
    задаёт Claude-модель, чьи лимиты и уровни effort использовать:
    ID=Подпись=claude-sonnet-5;
  - по умолчанию добавляются основные модели CPA (DeepSeek V4 Pro/Flash,
    GPT 6.2 Astra/Sol, GPT-6 Luna, Gemini 4 Argon), но только те, к которым
    есть доступ у ключа; alias для них администратор создаёт один раз на
    сервере скриптом scripts/sync-cpa-main-models.py;
  - после изменения списка Claude нужно перезапустить.

Что настраивается:
  %LOCALAPPDATA%\Claude-3p\configLibrary\<uuid>.json
  %LOCALAPPDATA%\Claude-3p\configLibrary\_meta.json
  %LOCALAPPDATA%\Claude-3p\claude_desktop_config.json

Важно:
  - Chat в Claude Desktop по-прежнему требует аккаунт claude.ai.
  - Для Claude Code используется вкладка Code; она работает через CPA.
'@
}

# --- small helpers -------------------------------------------------------------

function Get-CpaUrlHost {
    param([string]$Url)
    if (-not $Url) { return '' }
    try { return ([uri]$Url).Host.ToLowerInvariant() } catch { return '' }
}

function Get-CpaFingerprint {
    param([string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
    } finally { $sha.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8)
}

# Windows package publisher ID: Crockford base32 of the first 8 bytes of
# SHA-256 over the UTF-16LE publisher string (65 bits, zero-padded).
function Get-CpaPublisherId {
    param([string]$Publisher)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::Unicode.GetBytes($Publisher))
    } finally { $sha.Dispose() }
    $bits = ''
    for ($i = 0; $i -lt 8; $i++) { $bits += [Convert]::ToString($hash[$i], 2).PadLeft(8, '0') }
    $bits += '0'
    $alphabet = '0123456789abcdefghjkmnpqrstvwxyz'
    $out = ''
    for ($i = 0; $i -lt 65; $i += 5) { $out += $alphabet[[Convert]::ToInt32($bits.Substring($i, 5), 2)] }
    return $out
}

function ConvertTo-CpaVersion {
    param([string]$Text)
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text, '\d+(\.\d+){1,3}')
    if (-not $m.Success) { return $null }
    try { return [version]$m.Value } catch { return $null }
}

function Test-CpaInteractive {
    try {
        return ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
    } catch { return $false }
}

function Read-CpaSecret {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Read-CpaJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if (-not $text -or -not $text.Trim()) { return $null }
        return ($text | ConvertFrom-Json)
    } catch { return $null }
}

function Set-CpaProp {
    param($Object, [string]$Name, $Value)
    if ($Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Write-CpaJsonFile {
    param([string]$Path, $Object)
    $json = ConvertTo-Json -InputObject $Object -Depth 20
    $tmp = $Path + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Initialize-CpaNetwork {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { Write-Verbose 'TLS 1.2 is already the default.' }
    Add-Type -AssemblyName System.Net.Http
}

# Returns @{ Status = <int>; Body = <string> }. Status 0 means a network error.
function Invoke-CpaHttp {
    param(
        [string]$Method = 'GET',
        [string]$Url,
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [int]$TimeoutSec = 25
    )
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)
    try {
        $request = New-Object System.Net.Http.HttpRequestMessage ([System.Net.Http.HttpMethod]::new($Method)), $Url
        $null = $request.Headers.TryAddWithoutValidation('User-Agent', 'claude-desktop-cpa-onboarding')
        foreach ($name in $Headers.Keys) { $null = $request.Headers.TryAddWithoutValidation($name, [string]$Headers[$name]) }
        if ($null -ne $Body -and $Body -ne '') {
            $request.Content = New-Object System.Net.Http.StringContent $Body, ([System.Text.Encoding]::UTF8), 'application/json'
        }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return @{ Status = [int]$response.StatusCode; Body = $text }
    } catch {
        return @{ Status = 0; Body = '' }
    } finally {
        $client.Dispose()
    }
}

# --- platform and app detection -------------------------------------------------

function Test-CpaPlatform {
    $onWindows = ($env:OS -eq 'Windows_NT')
    if (-not $onWindows) { Stop-Cpa 'Этот скрипт предназначен для Windows. Для macOS используйте install.sh.' }
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 19041) {
        Stop-Cpa ("Нужна Windows 10 версии 2004 (сборка 19041) или новее; у вас сборка $build.")
    }
}

function Get-CpaArch {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

$script:CpaAppxReady = $false
function Initialize-CpaAppx {
    if ($script:CpaAppxReady) { return }
    try {
        $null = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction Stop
    } catch {
        # PowerShell 7 on some Windows builds can only load Appx through the
        # Windows PowerShell compatibility layer.
        Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
    }
    $script:CpaAppxReady = $true
}

function Get-CpaMsixPackage {
    try {
        Initialize-CpaAppx
        return (Get-AppxPackage -Name $script:CpaConst.PackageName -ErrorAction Stop |
            Where-Object { $_.PackageFamilyName -eq $script:CpaConst.PackageFamily } |
            Select-Object -First 1)
    } catch { return $null }
}

function Get-CpaLegacyInstall {
    $exe = Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $null }
    $version = $null
    try {
        $reg = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AnthropicClaude' -ErrorAction Stop
        $version = ConvertTo-CpaVersion $reg.DisplayVersion
    } catch { $version = $null }
    if (-not $version) { $version = ConvertTo-CpaVersion (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion }
    return @{ Kind = 'legacy'; Version = $version; Path = $exe; Package = $null }
}

# Returns @{ Kind = 'msix' | 'legacy'; Version; Path; Package } or $null.
function Get-CpaInstalledApp {
    $pkg = Get-CpaMsixPackage
    if ($pkg) {
        return @{ Kind = 'msix'; Version = (ConvertTo-CpaVersion ([string]$pkg.Version)); Path = $pkg.InstallLocation; Package = $pkg }
    }
    return (Get-CpaLegacyInstall)
}

function Get-CpaSupportDir {
    $local = Join-Path $env:LOCALAPPDATA 'Claude-3p'
    $packaged = Join-Path $env:LOCALAPPDATA ('Packages\' + $script:CpaConst.PackageFamily + '\LocalCache\Local\Claude-3p')
    foreach ($dir in @($local, $packaged)) {
        if (Test-Path -LiteralPath (Join-Path $dir 'configLibrary')) { return $dir }
    }
    foreach ($dir in @($local, $packaged)) {
        if (Test-Path -LiteralPath $dir) { return $dir }
    }
    if ([Environment]::OSVersion.Version.Build -lt 22000 -and (Get-CpaMsixPackage)) { return $packaged }
    return $local
}

# --- install source ------------------------------------------------------------------

# Parses the "Installers:" list of a winget installer manifest.
function ConvertFrom-CpaWingetInstaller {
    param([string]$Text)
    $entries = New-Object System.Collections.ArrayList
    $current = $null
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw
        if ($line -match '^- ') {
            if ($current) { $null = $entries.Add($current) }
            $current = @{}
            $line = '  ' + $line.Substring(2)
        }
        if ($null -ne $current -and $line -match '^ {2}([A-Za-z0-9]+):\s*(.*)$') {
            $current[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
    if ($current) { $null = $entries.Add($current) }
    return $entries.ToArray()
}

# Returns @{ Version; Url; Sha256; Source } for the newest official MSIX.
function Get-CpaLatestArtifact {
    $arch = Get-CpaArch
    $version = $null
    $cask = Invoke-CpaHttp -Url $script:CpaConst.CaskUrl -TimeoutSec 20
    if ($cask.Status -eq 200) {
        try { $version = ([string]($cask.Body | ConvertFrom-Json).version).Split(',')[0] } catch { $version = $null }
    }

    $manifest = $null
    if ($version) {
        $r = Invoke-CpaHttp -Url ('{0}/{1}/Anthropic.Claude.installer.yaml' -f $script:CpaConst.WingetRaw, $version) -TimeoutSec 20
        if ($r.Status -eq 200) { $manifest = $r.Body }
    }
    if (-not $manifest) {
        $list = Invoke-CpaHttp -Url $script:CpaConst.WingetApi -TimeoutSec 20
        if ($list.Status -eq 200) {
            try {
                $latest = @($list.Body | ConvertFrom-Json) |
                    Where-Object { $_.type -eq 'dir' -and (ConvertTo-CpaVersion $_.name) } |
                    Sort-Object { ConvertTo-CpaVersion $_.name } -Descending |
                    Select-Object -First 1
                if ($latest) {
                    $version = $latest.name
                    $r = Invoke-CpaHttp -Url ('{0}/{1}/Anthropic.Claude.installer.yaml' -f $script:CpaConst.WingetRaw, $version) -TimeoutSec 20
                    if ($r.Status -eq 200) { $manifest = $r.Body }
                }
            } catch { $manifest = $null }
        }
    }

    if ($manifest) {
        $entry = ConvertFrom-CpaWingetInstaller $manifest |
            Where-Object { $_['Architecture'] -eq $arch -and $_['InstallerType'] -eq 'msix' } |
            Select-Object -First 1
        if ($entry -and $entry['InstallerUrl'] -and (Get-CpaUrlHost $entry['InstallerUrl']) -eq $script:CpaConst.DownloadHost -and $entry['InstallerUrl'].StartsWith('https://')) {
            return @{ Version = (ConvertTo-CpaVersion $version); Url = $entry['InstallerUrl']; Sha256 = $entry['InstallerSha256']; Source = 'winget' }
        }
    }

    # Official download link without a published checksum: the package
    # identity and signature checks below still apply.
    return @{ Version = $null; Url = ('https://claude.ai/api/desktop/win32/{0}/msix/latest/redirect' -f $arch); Sha256 = $null; Source = 'claude.ai' }
}

function Get-CpaMsixIdentity {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxManifest.xml')
        if (-not $entry) { Stop-Cpa 'В установщике нет AppxManifest.xml: это не пакет MSIX.' }
        $reader = New-Object System.IO.StreamReader ($entry.Open())
        try { [xml]$xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    $id = $xml.Package.Identity
    return @{
        Name         = [string]$id.Name
        Publisher    = [string]$id.Publisher
        Version      = (ConvertTo-CpaVersion ([string]$id.Version))
        Architecture = [string]$id.ProcessorArchitecture
    }
}

# Throws unless the file is the official Anthropic Claude MSIX.
function Test-CpaArtifact {
    param([string]$Path, [string]$Sha256)
    if ($Sha256) {
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($actual -ne $Sha256) { Stop-Cpa 'Контрольная сумма установщика не совпала; установка отменена.' }
        Write-CpaLog '  Контрольная сумма SHA256: OK'
    } else {
        Write-CpaWarn 'Для этого файла нет опубликованной контрольной суммы; проверяю подпись и издателя.'
    }

    $identity = Get-CpaMsixIdentity $Path
    if ($identity.Name -ne $script:CpaConst.PackageName) {
        Stop-Cpa ("Установщик не похож на Claude Desktop (пакет: $($identity.Name)).")
    }
    $publisherId = Get-CpaPublisherId $identity.Publisher
    if ($publisherId -ne $script:CpaConst.PublisherId) {
        Stop-Cpa ("Установщик выпущен не Anthropic (издатель: $($identity.Publisher)).")
    }
    Write-CpaLog ('  Издатель: ' + $identity.Publisher + ' — OK')

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    switch ([string]$signature.Status) {
        'Valid' {
            $subject = [string]$signature.SignerCertificate.Subject
            if ($subject -notmatch 'Anthropic') { Stop-Cpa ("Установщик подписан не Anthropic ($subject).") }
            Write-CpaLog '  Цифровая подпись: OK'
        }
        { $_ -in @('NotSigned', 'HashMismatch', 'NotTrusted') } {
            Stop-Cpa ("Цифровая подпись установщика не прошла проверку ($($signature.Status)).")
        }
        default {
            Write-CpaLog '  Цифровую подпись Windows проверит при установке пакета.'
        }
    }
    return $identity
}

function Save-CpaArtifact {
    param([string]$Url, [string]$Directory)
    $file = Join-Path $Directory 'Claude.msix'
    Write-CpaLog ('Скачиваю Claude Desktop: ' + $Url)
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $file -UseBasicParsing -TimeoutSec 1800
    } catch {
        Stop-Cpa ('Не удалось скачать установщик: ' + $_.Exception.Message)
    } finally { $ProgressPreference = $old }
    return $file
}

function New-CpaTempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('claude-cpa-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    return $dir
}

function Install-CpaApp {
    $app = Get-CpaInstalledApp
    if ($app -and $script:Opt.NoUpdate) {
        Write-CpaLog ("Claude Desktop $($app.Version) установлен; обновление отключено.")
        return
    }
    if ($app -and $app.Kind -eq 'legacy') {
        Write-CpaWarn 'Установлена старая версия Claude Desktop (установщик .exe). Она обновляется сама, поэтому скрипт её не трогает.'
        Write-CpaWarn 'Режим Cowork работает только в версии MSIX. Чтобы перейти на неё, удалите Claude в «Параметры → Приложения» и запустите скрипт снова.'
        return
    }

    $latest = Get-CpaLatestArtifact
    if ($app -and $latest.Version -and $app.Version -and -not ($latest.Version -gt $app.Version)) {
        Write-CpaLog ("Установлено $($app.Version), последняя версия $($latest.Version) — обновление не требуется.")
        return
    }

    $tmp = New-CpaTempDir
    try {
        $file = Save-CpaArtifact -Url $latest.Url -Directory $tmp
        Write-CpaLog 'Проверяю подлинность установщика...'
        $identity = Test-CpaArtifact -Path $file -Sha256 $latest.Sha256
        if ($app -and $app.Version -and $identity.Version -and -not ($identity.Version -gt $app.Version)) {
            Write-CpaLog ("Установлено $($app.Version), в установщике $($identity.Version) — обновление не требуется.")
            return
        }
        if ($app) { Write-CpaLog ("Обновляю Claude Desktop: $($app.Version) -> $($identity.Version)") }
        else { Write-CpaLog ("Устанавливаю Claude Desktop $($identity.Version)...") }

        Initialize-CpaAppx
        try {
            Add-AppxPackage -Path $file -ForceApplicationShutdown -ErrorAction Stop
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '0x80073CFF') {
                Stop-Cpa 'Windows запрещает устанавливать приложения не из Microsoft Store (ошибка 0x80073CFF). Попросите администратора разрешить установку доверенных приложений и запустите скрипт снова.'
            }
            Stop-Cpa ('Windows не смогла установить Claude Desktop: ' + $msg)
        }
        $installed = Get-CpaMsixPackage
        if (-not $installed) { Stop-Cpa 'После установки пакет Claude не найден.' }
        Write-CpaLog ("Claude Desktop установлен: $($installed.Version).")
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- running app ---------------------------------------------------------------

function Get-CpaAppProcess {
    $legacyRoot = Join-Path $env:LOCALAPPDATA 'AnthropicClaude'
    $familySuffix = '__' + $script:CpaConst.PublisherId
    return @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
        $path = $null
        try { $path = $_.Path } catch { $path = $null }
        $path -and (($path -like ('*\WindowsApps\Claude_*' + $familySuffix + '\*')) -or ($path -like ($legacyRoot + '\*')))
    })
}

function Stop-CpaApp {
    $procs = Get-CpaAppProcess
    if ($procs.Count -eq 0) { return }
    Write-CpaLog 'Закрываю Claude...'
    foreach ($p in $procs) {
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $null = $p.CloseMainWindow() }
    }
    for ($i = 0; $i -lt 20; $i++) {
        if ((Get-CpaAppProcess).Count -eq 0) { return }
        Start-Sleep -Milliseconds 500
    }
    Get-CpaAppProcess | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20; $i++) {
        if ((Get-CpaAppProcess).Count -eq 0) { return }
        Start-Sleep -Milliseconds 500
    }
    Stop-Cpa 'Не удалось закрыть Claude. Закройте его вручную (в том числе значок у часов) и запустите скрипт снова.'
}

function Start-CpaApp {
    Write-CpaLog 'Запускаю Claude...'
    $app = Get-CpaInstalledApp
    if ($app -and $app.Kind -eq 'legacy') {
        Start-Process -FilePath $app.Path
    } else {
        $appId = $null
        try {
            $manifest = Get-AppxPackageManifest -Package $app.Package.PackageFullName -ErrorAction Stop
            $appId = @($manifest.Package.Applications.Application)[0].Id
        } catch { $appId = $null }
        if ($appId) { Start-Process ('shell:AppsFolder\{0}!{1}' -f $script:CpaConst.PackageFamily, $appId) }
        else { Start-Process 'claude://' }
    }
    for ($i = 0; $i -lt 40; $i++) {
        if ((Get-CpaAppProcess).Count -gt 0) { break }
        Start-Sleep -Milliseconds 500
    }
    if ((Get-CpaAppProcess).Count -eq 0) {
        Write-CpaWarn 'Claude не запустился сам. Откройте его из меню «Пуск».'
        return
    }
    Write-CpaLog 'Claude запущен. Жду, пока он подключится к CPA...'
    $log = Join-Path (Get-CpaSupportDir) 'Logs\main.log'
    for ($i = 0; $i -lt 45; $i++) {
        if ((Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log -Tail 200 -ErrorAction SilentlyContinue | Select-String -SimpleMatch "provider: 'gateway'" -Quiet)) {
            Write-CpaLog 'Подключение к CPA активно.'
            return
        }
        Start-Sleep -Seconds 1
    }
    Write-CpaWarn 'Claude запущен, но подтверждения подключения пока нет. Первый запуск может докачивать компоненты; откройте вкладку Code.'
}

function Get-CpaVmPlatformState {
    try {
        $feature = Get-CimInstance -ClassName Win32_OptionalFeature -Filter "Name='VirtualMachinePlatform'" -ErrorAction Stop
        if (-not $feature) { return 'unknown' }
        if ($feature.InstallState -eq 1) { return 'enabled' }
        return 'disabled'
    } catch { return 'unknown' }
}

function Show-CpaVmPlatformHint {
    if ((Get-CpaVmPlatformState) -ne 'disabled') { return }
    Write-CpaWarn 'Компонент Windows «Платформа виртуальной машины» выключен. Он нужен для режима Cowork.'
    Write-CpaWarn 'Чтобы включить: «Пуск» → «Включение или отключение компонентов Windows» → «Платформа виртуальной машины», затем перезагрузите компьютер.'
}

# --- keys ---------------------------------------------------------------------------

function Get-CpaKeyFromProfile {
    param([string]$WantHost)
    $support = Get-CpaSupportDir
    $meta = Read-CpaJson (Join-Path $support 'configLibrary\_meta.json')
    if (-not $meta -or -not $meta.appliedId) { return '' }
    $profileData = Read-CpaJson (Join-Path $support ('configLibrary\' + $meta.appliedId + '.json'))
    if (-not $profileData) { return '' }
    if ((Get-CpaUrlHost ([string]$profileData.inferenceGatewayBaseUrl)) -ne $WantHost) { return '' }
    $value = [string]$profileData.inferenceGatewayApiKey
    # After the first launch the app encrypts the key (DPAPI) and stores a
    # long opaque value instead. Only short/direct keys can be validated.
    if ($value.Trim() -and $value.Trim().Length -le 100) { return $value.Trim() }
    return ''
}

function Get-CpaKeyFromClaudeSetting {
    param([string]$WantHost)
    $settings = Read-CpaJson (Join-Path $env:USERPROFILE '.claude\settings.json')
    if (-not $settings -or -not $settings.env) { return '' }
    $envBlock = $settings.env
    if ((Get-CpaUrlHost ([string]$envBlock.ANTHROPIC_BASE_URL)) -ne $WantHost) { return '' }
    foreach ($name in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY')) {
        $value = [string]$envBlock.$name
        if ($value.Trim()) { return $value.Trim() }
    }
    return ''
}

# Line-based reader: a key is taken only from a provider whose base_url points
# at the CPA host; [model_providers.X.http_headers] belongs to provider X.
function Get-CpaKeyFromCodex {
    param([string]$WantHost)
    $path = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $lines = Get-Content -LiteralPath $path -Encoding UTF8
    $groups = [ordered]@{}
    $group = ''
    $keyPatterns = @(
        '^\s*experimental_bearer_token\s*=\s*"([^"]+)"',
        '(?i)"?X-Api-Key"?\s*=\s*"([^"]+)"',
        '^\s*api_key\s*=\s*"([^"]+)"'
    )
    foreach ($line in $lines) {
        if ($line -match '^\s*\[+\s*([^\]]+?)\s*\]+\s*$') {
            $parts = @($Matches[1].Split('.') | ForEach-Object { $_.Trim().Trim('"') })
            if ($parts[0] -eq 'model_providers') { $group = ($parts | Select-Object -First 2) -join '.' }
            else { $group = $parts -join '.' }
            continue
        }
        if (-not $groups.Contains($group)) { $groups[$group] = @{ Base = $null; Keys = New-Object System.Collections.ArrayList } }
        if ($line -match '^\s*base_url\s*=\s*"([^"]+)"') { $groups[$group].Base = $Matches[1]; continue }
        foreach ($pattern in $keyPatterns) {
            if ($line -match $pattern) { $null = $groups[$group].Keys.Add($Matches[1].Trim()); break }
        }
    }
    foreach ($g in $groups.Values) {
        if ($g.Base -and (Get-CpaUrlHost $g.Base) -eq $WantHost -and $g.Keys.Count -gt 0) { return [string]$g.Keys[0] }
    }
    return ''
}

function Test-CpaKey {
    param([string]$ApiKey)
    $base = $script:Opt.BaseUrl
    $headers = @{ 'x-api-key' = $ApiKey }
    $models = Invoke-CpaHttp -Url ($base + '/v1/models') -Headers $headers -TimeoutSec 25
    if ($models.Status -ne 200) {
        Write-CpaWarn ("CPA /v1/models вернул HTTP $($models.Status) — ключ не принят.")
        return $false
    }
    try {
        $ids = @((($models.Body | ConvertFrom-Json).data) | ForEach-Object { $_.id })
        $summary = ($script:CpaConst.Models | ForEach-Object { '{0}={1}' -f $_.name, $(if ($ids -contains $_.name) { 'yes' } else { 'no' }) }) -join '; '
        Write-CpaLog ("  models=$($ids.Count); $summary")
    } catch { Write-Verbose 'Model list is not JSON.' }

    $body = '{"model":"' + $script:CpaConst.ModelHaiku + '","max_tokens":8,"messages":[{"role":"user","content":"ping"}]}'
    $headers['anthropic-version'] = '2023-06-01'
    $msg = Invoke-CpaHttp -Method 'POST' -Url ($base + '/v1/messages') -Headers $headers -Body $body -TimeoutSec 40
    if ($msg.Status -eq 200) {
        try {
            if ((($msg.Body | ConvertFrom-Json).type) -eq 'message') {
                Write-CpaLog ("  Claude-модель $($script:CpaConst.ModelHaiku): OK")
                return $true
            }
        } catch { Write-Verbose 'Message response is not JSON.' }
        Write-CpaWarn 'Ответ /v1/messages не похож на ответ Claude.'
        return $false
    }
    if ($msg.Status -eq 429 -or ($msg.Status -ge 500 -and $msg.Status -lt 600)) {
        Write-CpaWarn ("Claude-модель вернула HTTP $($msg.Status) (временная ошибка или лимит); настройку можно записать, но проверьте позже.")
        return $true
    }
    Write-CpaWarn ("Ключ принят для /v1/models, но Claude-модель вернула HTTP $($msg.Status).")
    Write-CpaWarn 'Проверьте, что для этого ключа в CPA включён доступ к моделям Claude.'
    return $false
}

function Read-CpaKeyInteractive {
    if (-not (Test-CpaInteractive)) { Stop-Cpa 'Нет окна для ввода ключа. Передайте ключ через переменную CPA_API_KEY.' }
    for ($i = 0; $i -lt 3; $i++) {
        $candidate = Read-CpaSecret 'CPA API key (символы не отображаются)'
        if (-not $candidate) { continue }
        $candidate = $candidate.Trim()
        if (Test-CpaKey $candidate) {
            $script:CpaKey = $candidate
            $script:CpaKeySource = 'interactive'
            Write-CpaLog ("Использую CPA-ключ (fingerprint $(Get-CpaFingerprint $candidate)).")
            return
        }
        Write-CpaWarn 'Ключ не прошёл проверку. Попробуйте ещё раз.'
    }
    Stop-Cpa 'Не удалось получить рабочий CPA-ключ.'
}

# Sets $script:CpaKey / $script:CpaKeySource. Returns $true on success; in
# -Check / -DryRun returns $false instead of failing.
function Resolve-CpaKey {
    $readOnly = ($script:Opt.Check -or $script:Opt.DryRun)

    # An explicitly supplied key is authoritative.
    $explicit = @()
    if ($script:Opt.Key) { $explicit += , @('-Key', $script:Opt.Key) }
    elseif ($env:CPA_API_KEY) { $explicit += , @('CPA_API_KEY', $env:CPA_API_KEY) }
    if ($explicit.Count -gt 0) {
        $source = $explicit[0][0]; $value = $explicit[0][1]
        Write-CpaLog ("Проверяю ключ из $source...")
        if (Test-CpaKey $value) {
            $script:CpaKey = $value; $script:CpaKeySource = $source
            Write-CpaLog ("Использую CPA-ключ из $source (fingerprint $(Get-CpaFingerprint $value)).")
            return $true
        }
        if ($readOnly) { Write-CpaWarn ("Ключ из $source не прошёл проверку."); return $false }
        if (-not $script:Opt.Force) { Stop-Cpa ("Ключ из $source не прошёл проверку.") }
        $script:CpaKey = $value; $script:CpaKeySource = $source
        Write-CpaWarn ("Записываю настройку с ключом из $source несмотря на ошибку проверки (-Force).")
        return $true
    }

    if ($script:Opt.AskKey -and -not $readOnly) {
        if ($script:Opt.Yes) { Stop-Cpa '-AskKey требует ввода ключа, а -Yes запрещает вопросы.' }
        Write-CpaLog 'Введите новый CPA-ключ.'
        Read-CpaKeyInteractive
        return $true
    }

    $wantHost = Get-CpaUrlHost $script:Opt.BaseUrl
    $candidates = New-Object System.Collections.ArrayList
    foreach ($pair in @(
            @('Claude-3p profile', (Get-CpaKeyFromProfile $wantHost)),
            @('Claude CLI settings', (Get-CpaKeyFromClaudeSetting $wantHost)),
            @('Codex config', (Get-CpaKeyFromCodex $wantHost)))) {
        if ($pair[1] -and -not (@($candidates | ForEach-Object { $_[1] }) -contains $pair[1])) { $null = $candidates.Add($pair) }
    }

    if ($candidates.Count -eq 0) {
        if ($readOnly) { Write-CpaWarn 'CPA-ключ не найден.'; return $false }
        if ($script:Opt.Yes) { Stop-Cpa 'CPA-ключ не найден, а -Yes запрещает вопросы. Передайте ключ через CPA_API_KEY.' }
        Read-CpaKeyInteractive
        return $true
    }

    foreach ($pair in $candidates) {
        Write-CpaLog ("Проверяю ключ из $($pair[0])...")
        if (Test-CpaKey $pair[1]) {
            $script:CpaKey = $pair[1]; $script:CpaKeySource = $pair[0]
            Write-CpaLog ("Использую CPA-ключ из $($pair[0]) (fingerprint $(Get-CpaFingerprint $pair[1])).")
            return $true
        }
    }

    if ($readOnly) { Write-CpaWarn 'Ни один найденный ключ не прошёл проверку.'; return $false }

    # A stored key that no longer works was most likely revoked or replaced.
    if (-not $script:Opt.Yes -and (Test-CpaInteractive)) {
        Write-CpaWarn 'Сохранённый CPA-ключ не подошёл (возможно, его заменили или отозвали).'
        Read-CpaKeyInteractive
        return $true
    }
    if (-not $script:Opt.Force) {
        Stop-Cpa 'Ни один CPA-ключ не прошёл проверку. Передайте новый ключ через CPA_API_KEY или запустите скрипт в PowerShell с -AskKey.'
    }
    $script:CpaKey = $candidates[0][1]; $script:CpaKeySource = $candidates[0][0]
    Write-CpaWarn ("Записываю настройку с ключом из $($script:CpaKeySource) несмотря на ошибку проверки (-Force).")
    return $true
}

# --- models --------------------------------------------------------------------------

# Extra models are stored outside the 3P profile, because the profile is
# rewritten on every run. Only model IDs and labels live here; keys never do.
function Get-CpaModelFile {
    return (Join-Path $env:LOCALAPPDATA 'claude-desktop-cpa\models.json')
}

function Get-CpaModelTier {
    param([string]$Name)
    $low = $Name.ToLowerInvariant()
    foreach ($tier in $script:CpaConst.ModelTiers) {
        if ($low.Contains($tier)) { return $tier }
    }
    return 'sonnet'
}

# Returns the saved extra models as ordered hashtables with known keys only.
function Read-CpaModelFile {
    $result = New-Object System.Collections.ArrayList
    foreach ($entry in @(Read-CpaJson (Get-CpaModelFile))) {
        if ($null -eq $entry) { continue }
        $name = $entry.PSObject.Properties['name']
        if (-not $name -or $name.Value -isnot [string] -or -not $name.Value.Trim()) { continue }
        $item = [ordered]@{}
        foreach ($key in $script:CpaConst.ModelKeys) {
            $prop = $entry.PSObject.Properties[$key]
            if ($prop) { $item[$key] = $prop.Value }
        }
        $null = $result.Add($item)
    }
    return $result.ToArray()
}

function Get-CpaModelSummary {
    return ((@(Read-CpaModelFile) | ForEach-Object { $_['name'] }) -join ', ')
}

# Adds or removes models in the saved list. A spec is ID, ID=Label or
# ID=Label=ClaudeModel (the Claude model whose limits and effort levels apply).
function Update-CpaModelFile {
    param(
        [ValidateSet('add', 'remove')][string]$Mode,
        [string[]]$Spec
    )
    if (-not $Spec -or $Spec.Count -eq 0) { return }
    $path = Get-CpaModelFile
    $data = New-Object System.Collections.ArrayList
    foreach ($item in @(Read-CpaModelFile)) { $null = $data.Add($item) }

    if ($Mode -eq 'add') {
        foreach ($raw in $Spec) {
            $parts = $raw.Split([char[]]'=', 3)
            $name = $parts[0].Trim()
            $label = ''
            if ($parts.Count -gt 1) { $label = $parts[1].Trim() }
            $behaves = ''
            if ($parts.Count -gt 2) { $behaves = $parts[2].Trim() }
            if (-not $name) { Stop-Cpa 'пустой ID модели' }
            $bad = $script:CpaConst.NonAnthropicRegex.Match($name)
            if ($bad.Success) {
                Stop-Cpa ('Claude Desktop отбросит «{0}»: в имени есть «{1}». Опубликуйте модель в CPA под alias с «claude-» или названием семейства (sonnet, haiku) в имени, например sonnet-4-5-cpa, и добавьте этот alias.' -f $name, $bad.Value)
            }
            if (-not $label) { $label = $name }
            $tierSource = $name
            if ($behaves) { $tierSource = $behaves }
            $entry = [ordered]@{
                name                = $name
                supports1m          = $false
                labelOverride       = $label
                anthropicFamilyTier = (Get-CpaModelTier $tierSource)
            }
            # Lets Claude Desktop apply Claude's limits and effort levels to an
            # alias it cannot identify, such as a DeepSeek gateway ID.
            if ($behaves) { $entry['behavesAs'] = $behaves }
            $index = -1
            for ($i = 0; $i -lt $data.Count; $i++) {
                if ($data[$i]['name'] -ceq $name) { $index = $i; break }
            }
            if ($index -ge 0) { $data[$index] = $entry } else { $null = $data.Add($entry) }
            Write-CpaLog ('добавлена модель: ' + $name)
        }
    } else {
        $removing = @($Spec | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $before = $data.Count
        for ($i = $data.Count - 1; $i -ge 0; $i--) {
            if ($removing -ccontains $data[$i]['name']) { $data.RemoveAt($i) }
        }
        Write-CpaLog ('удалено моделей: ' + ($before - $data.Count))
    }

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
    Write-CpaJsonFile $path ([object[]]$data.ToArray())
}

# One cheap request to see whether the current CPA key can use an alias.
function Test-CpaModelAccess {
    param([string]$Model)
    $headers = @{ 'x-api-key' = $script:CpaKey; 'anthropic-version' = '2023-06-01' }
    $body = ConvertTo-Json -Compress -InputObject ([ordered]@{
            model      = $Model
            max_tokens = 16
            messages   = @(, [ordered]@{ role = 'user'; content = 'ping' })
        })
    $r = Invoke-CpaHttp -Method 'POST' -Url ($script:Opt.BaseUrl + '/v1/messages') -Headers $headers -Body $body -TimeoutSec 45
    if ($r.Status -eq 200) {
        try { return ((($r.Body | ConvertFrom-Json).type) -eq 'message') } catch { return $false }
    }
    if ($r.Status -eq 429 -or ($r.Status -ge 500 -and $r.Status -lt 600)) { return $true }
    return $false
}

# Adds only the main models that the configured CPA key can actually use.
function Add-CpaMainModel {
    $good = New-Object System.Collections.ArrayList
    $skipped = New-Object System.Collections.ArrayList
    Write-CpaLog 'Проверяю основные модели CPA...'
    foreach ($spec in $script:CpaConst.MainModels) {
        if (Test-CpaModelAccess $spec.name) {
            $null = $good.Add(('{0}={1}={2}' -f $spec.name, $spec.label, $spec.behavesAs))
            Write-CpaLog ('  ' + $spec.name + ': OK')
        } else {
            $null = $skipped.Add($spec.name)
        }
    }
    if ($good.Count -eq 0) {
        Write-CpaWarn 'Основные модели CPA недоступны этому ключу; добавляю только Claude.'
        Write-CpaWarn 'Если нужны только Claude-модели, используйте -ClaudeOnly.'
        return
    }
    if ($skipped.Count -gt 0) { Write-CpaWarn ('Пропущены модели без доступа: ' + ($skipped -join ' ')) }
    Update-CpaModelFile -Mode add -Spec ([string[]]$good)
}

function Show-CpaModelList {
    if (-not (Resolve-CpaKey)) { Stop-Cpa 'Не удалось получить рабочий CPA-ключ.' }
    $r = Invoke-CpaHttp -Url ($script:Opt.BaseUrl + '/v1/models') -Headers @{ 'x-api-key' = $script:CpaKey } -TimeoutSec 30
    if ($r.Status -ne 200) { Stop-Cpa ('CPA /v1/models вернул HTTP ' + $r.Status) }
    try {
        $ids = @((($r.Body | ConvertFrom-Json).data) | ForEach-Object { $_.id } | Where-Object { $_ } | Sort-Object -Unique)
    } catch {
        Stop-Cpa 'не удалось разобрать ответ /v1/models'
    }
    $claude = @($ids | Where-Object { $_.ToLowerInvariant().StartsWith('claude') })
    $other = @($ids | Where-Object { $claude -notcontains $_ })
    Write-CpaLog 'Модели Claude, доступные ключу CPA:'
    foreach ($id in $claude) { Write-CpaLog ('  ' + $id) }
    Write-CpaLog ''
    Write-CpaLog ('Прочие модели: {0}. Через CPA они возможны, но в Claude Desktop' -f $other.Count)
    Write-CpaLog 'не тестировались: приложение отправляет Anthropic-формат запросов.'
    Write-CpaLog ''
    Write-CpaLog 'Пример: -AddModel ''claude-opus-4-8=Opus 4.8'' -ConfigureOnly'
}

# --- configuration ---------------------------------------------------------------------

function Write-CpaConfig {
    if (-not $script:CpaKey) { Stop-Cpa 'Пустой CPA-ключ.' }
    $support = Get-CpaSupportDir
    $library = Join-Path $support 'configLibrary'
    $null = New-Item -ItemType Directory -Path $library -Force

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Join-Path $support '.cpa-backups'
    $backupDir = Join-Path $backupRoot $stamp
    $n = 1
    while (Test-Path -LiteralPath $backupDir) { $backupDir = Join-Path $backupRoot ($stamp + '-' + $n); $n++ }
    $null = New-Item -ItemType Directory -Path $backupDir -Force

    $metaPath = Join-Path $library '_meta.json'
    $desktopPath = Join-Path $support 'claude_desktop_config.json'
    foreach ($p in @($metaPath, $desktopPath)) {
        if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination $backupDir }
    }

    $meta = Read-CpaJson $metaPath
    if (-not $meta) { $meta = [pscustomobject]@{} }
    $entries = @()
    if ($meta.PSObject.Properties['entries'] -and $meta.entries) { $entries = @($meta.entries) }

    $base = $script:Opt.BaseUrl.TrimEnd('/')
    $wantHost = Get-CpaUrlHost $base
    $chosen = $entries | Where-Object { $_.name -eq $script:CpaConst.ProfileName -and $_.id } | Select-Object -First 1
    if (-not $chosen) {
        foreach ($e in $entries) {
            if (-not $e.id) { continue }
            $p = Read-CpaJson (Join-Path $library ($e.id + '.json'))
            if ($p -and (Get-CpaUrlHost ([string]$p.inferenceGatewayBaseUrl)) -eq $wantHost) {
                $chosen = $e
                if (-not $e.name) { Set-CpaProp $e 'name' $script:CpaConst.ProfileName }
                break
            }
        }
    }
    if (-not $chosen) {
        $chosen = [pscustomobject]@{ id = [guid]::NewGuid().ToString(); name = $script:CpaConst.ProfileName }
        $entries += $chosen
    }

    $profilePath = Join-Path $library ($chosen.id + '.json')
    if (Test-Path -LiteralPath $profilePath) { Copy-Item -LiteralPath $profilePath -Destination $backupDir }
    $profileData = Read-CpaJson $profilePath
    if (-not $profileData) { $profileData = [pscustomobject]@{} }

    $models = @($script:CpaConst.Models | ForEach-Object {
        [pscustomobject][ordered]@{ name = $_.name; supports1m = $false; labelOverride = $_.label; anthropicFamilyTier = $_.tier }
    })
    # Extra models (-AddModel and the main CPA models). Built-ins stay first, so
    # Sonnet 5.5 remains the default; extras follow in the order they were added.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $models) { $null = $seen.Add([string]$m.name) }
    foreach ($entry in @(Read-CpaModelFile)) {
        $name = [string]$entry['name']
        if (-not $seen.Add($name)) { continue }
        $item = [ordered]@{}
        foreach ($key in $script:CpaConst.ModelKeys) {
            if ($entry.Contains($key)) { $item[$key] = $entry[$key] }
        }
        $item['name'] = $name
        if (-not $item.Contains('supports1m')) { $item['supports1m'] = $false }
        if ($script:CpaConst.ModelTiers -cnotcontains [string]$item['anthropicFamilyTier']) {
            $item['anthropicFamilyTier'] = Get-CpaModelTier $name
        }
        $models += [pscustomobject]$item
    }
    Set-CpaProp $profileData 'coworkEgressAllowedHosts' @('*')
    Set-CpaProp $profileData 'inferenceProvider' 'gateway'
    Set-CpaProp $profileData 'inferenceGatewayBaseUrl' $base
    Set-CpaProp $profileData 'inferenceGatewayApiKey' $script:CpaKey
    Set-CpaProp $profileData 'inferenceGatewayAuthScheme' 'x-api-key'
    Set-CpaProp $profileData 'inferenceModels' $models
    Set-CpaProp $profileData 'chatTabEnabled' ([bool]$script:Opt.WithChat)
    Set-CpaProp $profileData 'disableDeploymentModeChooser' $true
    Set-CpaProp $profileData 'modelDiscoveryEnabled' $false
    Set-CpaProp $profileData 'inferenceStreamIdleTimeoutSec' 1800

    Set-CpaProp $meta 'appliedId' $chosen.id
    Set-CpaProp $meta 'entries' ([object[]]$entries)

    Write-CpaJsonFile $profilePath $profileData
    Write-CpaJsonFile $metaPath $meta

    $desktop = Read-CpaJson $desktopPath
    if (-not $desktop) { $desktop = [pscustomobject]@{} }
    Set-CpaProp $desktop 'deploymentMode' '3p'
    $prefs = $null
    if ($desktop.PSObject.Properties['preferences']) { $prefs = $desktop.preferences }
    if (-not $prefs -or $prefs -isnot [System.Management.Automation.PSCustomObject]) { $prefs = [pscustomobject]@{} }
    # Keep the app's current Code UI choice; only seed a value when it has none.
    $mode = $null
    if ($prefs.PSObject.Properties['sidebarMode']) { $mode = $prefs.sidebarMode }
    if (@('code', 'epitaxy') -notcontains $mode) { Set-CpaProp $prefs 'sidebarMode' 'code' }
    Set-CpaProp $desktop 'preferences' $prefs
    Write-CpaJsonFile $desktopPath $desktop

    # Keep only the newest 5 backups (they can contain old API keys).
    Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object Name -Descending |
        Select-Object -Skip 5 | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Write-CpaLog ('profile: ' + $profilePath)
    Write-CpaLog ('applied_id: ' + $chosen.id)
    Write-CpaLog ('models: ' + (($models | ForEach-Object { $_.name }) -join ', '))
    Write-CpaLog ('chatTabEnabled: ' + ([string]([bool]$script:Opt.WithChat)).ToLowerInvariant())
    Write-CpaLog ('backup: ' + $backupDir)
}

# Returns a hashtable describing the applied 3P configuration.
function Get-CpaConfigState {
    $support = Get-CpaSupportDir
    $state = [ordered]@{ support_dir = $support; applied_id = '(none)'; provider = '(none)'; base_url = '(none)'; base_matches = 'no'; key_kind = 'none'; models = '(none)'; auth_scheme = '(none)'; chat_tab_enabled = ''; deploymentMode = '(none)' }
    $meta = Read-CpaJson (Join-Path $support 'configLibrary\_meta.json')
    if ($meta -and $meta.appliedId) {
        $state.applied_id = [string]$meta.appliedId
        $p = Read-CpaJson (Join-Path $support ('configLibrary\' + $meta.appliedId + '.json'))
        if ($p) {
            if ($p.inferenceProvider) { $state.provider = [string]$p.inferenceProvider }
            if ($p.inferenceGatewayBaseUrl) { $state.base_url = [string]$p.inferenceGatewayBaseUrl }
            if (([string]$p.inferenceGatewayBaseUrl).TrimEnd('/') -eq $script:Opt.BaseUrl.TrimEnd('/')) { $state.base_matches = 'yes' }
            $k = [string]$p.inferenceGatewayApiKey
            if ($k) { if ($k.Length -le 100) { $state.key_kind = 'direct' } else { $state.key_kind = 'encrypted' } }
            $names = @($p.inferenceModels | ForEach-Object { $_.name } | Where-Object { $_ })
            if ($names.Count -gt 0) { $state.models = $names -join ', ' }
            if ($p.inferenceGatewayAuthScheme) { $state.auth_scheme = [string]$p.inferenceGatewayAuthScheme }
            $state.chat_tab_enabled = [string]$p.chatTabEnabled
        }
    }
    $desktop = Read-CpaJson (Join-Path $support 'claude_desktop_config.json')
    if ($desktop -and $desktop.deploymentMode) { $state.deploymentMode = [string]$desktop.deploymentMode }
    return $state
}

# --- modes -----------------------------------------------------------------------------

function Invoke-CpaCheck {
    $ok = $true
    Write-CpaLog '== Claude Desktop =='
    $app = Get-CpaInstalledApp
    if ($app) {
        Write-CpaLog ('kind: ' + $app.Kind)
        Write-CpaLog ('version: ' + $app.Version)
        Write-CpaLog ('path: ' + $app.Path)
        if ($app.Kind -eq 'msix') { Write-CpaLog ('publisher: Anthropic (' + $script:CpaConst.PackageFamily + ')') }
        Write-CpaLog ('running: ' + $(if ((Get-CpaAppProcess).Count -gt 0) { 'yes' } else { 'no' }))
    } else {
        Write-CpaWarn 'Claude Desktop не установлен.'
        $ok = $false
    }
    $latest = Get-CpaLatestArtifact
    Write-CpaLog ('latest: ' + $(if ($latest.Version) { $latest.Version } else { 'unknown' }) + ' (' + $latest.Source + ')')
    Write-CpaLog ('vm_platform: ' + (Get-CpaVmPlatformState))

    Write-CpaLog ''
    Write-CpaLog '== CPA / 3P config =='
    $state = Get-CpaConfigState
    foreach ($name in $state.Keys) { Write-CpaLog ('{0}: {1}' -f $name, $state[$name]) }
    if ($state.provider -ne 'gateway' -or $state.base_matches -ne 'yes' -or $state.deploymentMode -ne '3p' -or $state.models -notmatch 'claude-sonnet-5-5') { $ok = $false }

    Write-CpaLog ''
    Write-CpaLog '== Key validation =='
    if (Resolve-CpaKey) {
        Write-CpaLog ('key_source: ' + $script:CpaKeySource)
        if ($state.key_kind -eq 'encrypted') {
            Write-CpaLog 'Ключ в профиле зашифрован приложением (DPAPI); приложение использует его само.'
        } elseif ($script:CpaKeySource -ne 'Claude-3p profile') {
            Write-CpaWarn 'В профиле записан другой ключ, а рабочий найден в другом месте. Запустите скрипт без -Check, чтобы обновить профиль.'
            $ok = $false
        }
    } elseif ($state.key_kind -eq 'encrypted') {
        $log = Join-Path $state.support_dir 'Logs\main.log'
        if ((Test-Path -LiteralPath $log) -and (Get-Content -LiteralPath $log -Tail 200 | Select-String -Pattern 'ConfigHealth.*healthy' -Quiet)) {
            Write-CpaLog 'Журнал приложения подтверждает подключение к CPA.'
        } else {
            Write-CpaWarn 'Ключ зашифрован приложением; подтверждения подключения в журнале нет.'
            $ok = $false
        }
    } else {
        Write-CpaWarn 'Рабочий CPA-ключ не найден.'
        $ok = $false
    }

    Write-CpaLog ''
    if ($ok) {
        Write-CpaLog 'OK: Claude Desktop настроен на CPA. Для работы используйте вкладку Code.'
        return 0
    }
    Write-CpaWarn 'Настройка неполная или ключ не прошёл проверку.'
    return 1
}

function Invoke-CpaDryRun {
    Write-CpaLog 'DRY-RUN: изменения не применяются.'
    $app = Get-CpaInstalledApp
    if ($app) { Write-CpaLog ("app: $($app.Kind) $($app.Version)") } else { Write-CpaLog 'app: not installed' }
    $latest = Get-CpaLatestArtifact
    Write-CpaLog ('latest: ' + $(if ($latest.Version) { $latest.Version } else { 'unknown' }) + ' ' + $latest.Url + ' (' + $latest.Source + ')')
    Write-CpaLog ('3P config: ' + (Get-CpaSupportDir))
    Write-CpaLog ('models: ' + (($script:CpaConst.Models | ForEach-Object { $_.name }) -join ', '))
    if ($script:Opt.MainModels) {
        Write-CpaLog 'main models:'
        foreach ($m in $script:CpaConst.MainModels) { Write-CpaLog ('  ' + $m.name) }
    }
    $extra = Get-CpaModelSummary
    if ($extra) { Write-CpaLog ('extra models: ' + $extra) }
    $null = Resolve-CpaKey
    Write-CpaLog 'Были бы записаны профиль CPA, _meta.json и deploymentMode=3p.'
    Write-CpaLog ('Claude был бы перезапущен: ' + $(if ($script:Opt.NoRestart) { 'no' } else { 'yes' }) + '.')
}

function Invoke-CpaVerifyDownload {
    $latest = Get-CpaLatestArtifact
    Write-CpaLog ('source: ' + $latest.Source)
    Write-CpaLog ('version: ' + $latest.Version)
    $tmp = New-CpaTempDir
    try {
        $file = Save-CpaArtifact -Url $latest.Url -Directory $tmp
        $identity = Test-CpaArtifact -Path $file -Sha256 $latest.Sha256
        $signature = Get-AuthenticodeSignature -LiteralPath $file
        Write-CpaLog ('package: ' + $identity.Name + ' ' + $identity.Version + ' ' + $identity.Architecture)
        Write-CpaLog ('publisher_id: ' + (Get-CpaPublisherId $identity.Publisher))
        Write-CpaLog ('signature_status: ' + $signature.Status)
        if ($signature.SignerCertificate) { Write-CpaLog ('signature_subject: ' + $signature.SignerCertificate.Subject) }
        Write-CpaLog 'OK: установщик подлинный.'
        return 0
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-CpaMain {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    try {
        if ($script:Opt.Help) { Show-CpaUsage; return 0 }
        Test-CpaPlatform
        Initialize-CpaNetwork
        $script:Opt.BaseUrl = $script:Opt.BaseUrl.TrimEnd('/')
        if ($script:Opt.BaseUrl -notmatch '^https?://') { Stop-Cpa ('Некорректный -BaseUrl: ' + $script:Opt.BaseUrl) }

        if ($script:Opt.VerifyDownload) { return (Invoke-CpaVerifyDownload) }
        if ($script:Opt.ListModels) { Show-CpaModelList; return 0 }
        if (-not $script:Opt.Check -and -not $script:Opt.DryRun) {
            if ($script:Opt.AddModel.Count -gt 0) { Update-CpaModelFile -Mode add -Spec $script:Opt.AddModel }
            if ($script:Opt.RemoveModel.Count -gt 0) { Update-CpaModelFile -Mode remove -Spec $script:Opt.RemoveModel }
        }
        if ($script:Opt.Check) { return (Invoke-CpaCheck) }
        if ($script:Opt.DryRun) { Invoke-CpaDryRun; return 0 }

        if (-not $script:Opt.ConfigureOnly) { Install-CpaApp }
        if (-not (Get-CpaInstalledApp)) {
            Stop-Cpa 'Claude Desktop не установлен. Запустите скрипт без -ConfigureOnly или установите приложение.'
        }

        $null = Resolve-CpaKey
        if ($script:Opt.MainModels) { Add-CpaMainModel }
        Stop-CpaApp
        Write-CpaConfig
        if ($script:Opt.NoRestart) { Write-CpaLog 'Настройка записана. Claude не запускался (-NoRestart).' }
        else { Start-CpaApp }
        Show-CpaVmPlatformHint

        $app = Get-CpaInstalledApp
        Write-CpaLog ''
        Write-CpaLog 'Готово.'
        Write-CpaLog ('Claude Desktop: ' + $app.Version)
        Write-CpaLog ('3P профиль: ' + (Join-Path (Get-CpaSupportDir) 'configLibrary'))
        Write-CpaLog 'Откройте вкладку Code. Chat по-прежнему требует аккаунт claude.ai.'
        Write-CpaLog 'Первый запуск Code может докачивать компоненты — это не вход в аккаунт.'
        return 0
    } catch {
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
        return 1
    }
}

# Tests dot-source this file with CPA_INSTALL_SOURCE_ONLY=1 to reach the
# helpers without running the installer. `irm | iex` never sets it.
if ($env:CPA_INSTALL_SOURCE_ONLY -ne '1') {
    $cpaExitCode = Invoke-CpaMain
    # Always report the result through $LASTEXITCODE, which works for every
    # way of starting the script. Only a script file may also call `exit`:
    # under `irm | iex` an `exit` would close the user's PowerShell window.
    $global:LASTEXITCODE = $cpaExitCode
    if ($PSCommandPath -and $MyInvocation.InvocationName -ne '.') { exit $cpaExitCode }
}
