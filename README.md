# Claude Desktop через CPA

[![Проверка установщиков](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml/badge.svg)](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml)
[![Релиз](https://img.shields.io/github/v/release/yshishenya/claude-desktop-cpa-onboarding?label=версия)](https://github.com/yshishenya/claude-desktop-cpa-onboarding/releases/latest)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows)](#windows)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](#macos)
[![Лицензия: MIT](https://img.shields.io/badge/лицензия-MIT-blue)](LICENSE)

Установщик ставит **Claude Desktop** и подключает его к серверу **CPA**.
Нужно выполнить одну команду и один раз ввести выданный вам ключ.
**Входить в аккаунт claude.ai не нужно.** Работать можно во вкладке **Code**.
Вкладке **Chat** по-прежнему нужен личный аккаунт claude.ai.

## Выберите вашу систему

| Если у вас | Перейдите к инструкции |
|---|---|
| Компьютер с Windows 10 или 11 | [Настройка Windows](#windows) |
| MacBook, iMac или Mac mini (macOS 13 или новее) | [Настройка macOS](#macos) |

Понадобятся ключ CPA ([где взять](#где-взять-ключ)) и интернет.

---

## Windows

### Шаг 1. Откройте PowerShell

1. Нажмите кнопку **Пуск**.
2. Напечатайте `PowerShell`.
3. Откройте **Windows PowerShell**.

Запускать от имени администратора не нужно.

> [!NOTE]
> Не используйте «Командную строку» (`cmd`). Нужен именно **PowerShell**
> с синим значком.

### Шаг 2. Скопируйте и запустите команду

```powershell
irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 | iex
```

Вставьте строку в PowerShell сочетанием <kbd>Ctrl</kbd> + <kbd>V</kbd> и
нажмите <kbd>Enter</kbd>.

### Шаг 3. Введите ключ

Когда скрипт попросит `CPA API key`, вставьте ключ и нажмите <kbd>Enter</kbd>.
Вместо ключа на экране будут звёздочки или пустота — это нормально.

Если ключ уже есть в настройках Claude Code или Codex, скрипт найдёт его сам и
не спросит.

### Шаг 4. Дождитесь «Готово.»

Установка занимает несколько минут: пакет весит около 300 МБ. В конце
откроется Claude. Перейдите на вкладку **Code**: в списке моделей будут
Claude Sonnet 5.5, Opus 5.5 и Haiku 5.5.

---

## macOS

### Шаг 1. Откройте Терминал

1. Нажмите <kbd>Command</kbd> + <kbd>Пробел</kbd>.
2. Напечатайте `Терминал`.
3. Нажмите <kbd>Enter</kbd>.

### Шаг 2. Скопируйте и запустите команду

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash
```

Вставьте строку в Терминал сочетанием <kbd>Command</kbd> + <kbd>V</kbd> и
нажмите <kbd>Enter</kbd>.

### Шаг 3. Введите ключ

Когда скрипт попросит `CPA API key`, вставьте ключ и нажмите <kbd>Enter</kbd>.
Символы **не отображаются** — это нормально.

Если скрипт попросит пароль, введите пароль от вашего Mac. Он нужен, только
если учётная запись не может сама ставить программы.

Если ключ уже есть в настройках Claude Code или Codex, скрипт найдёт его сам и
не спросит.

### Шаг 4. Дождитесь «Готово.»

В конце откроется Claude. Перейдите на вкладку **Code**: в списке моделей будут
Claude Sonnet 5.5, Opus 5.5 и Haiku 5.5.

---

## Где взять ключ

Ключ выдаёт администратор вашего CPA. Установщик его не создаёт.

> [!WARNING]
> Не отправляйте ключ в чат, письмо или обращение на GitHub и не делайте с ним
> снимков экрана.

## Что делает установщик

1. Скачивает официальное приложение Claude Desktop с сайта Anthropic и
   проверяет его подлинность: контрольную сумму и подпись Anthropic (на Mac ещё
   и проверку Apple). Чужое приложение не ставится.
2. Не ставит старую версию поверх новой.
3. Проверяет ключ на сервере CPA.
4. Сохраняет прежние настройки в резервную копию (последние пять).
5. Записывает настройку подключения к CPA и запускает Claude.
6. Добавляет рядом с Claude основные модели CPA (GPT 6.2 Astra, GPT 6.2 Sol,
   GPT 6.1 Terra, GPT-6 Luna), если ваш ключ их открывает. Только Claude:
   `--claude-only` на Mac, `-ClaudeOnly` на Windows.

## Если что-то пошло не так

| Что вы видите | Что делать |
|---|---|
| `HTTP 401`, `Ключ ... не прошёл проверку` | Ключ скопирован не целиком, с ошибкой или не действует. Скрипт напишет, сколько символов получил, и отпечаток введённого ключа: сверьте их с данными администратора. Скопируйте ключ ещё раз целиком и запустите команду снова. |
| `Claude-модель вернула HTTP ...` | У ключа нет доступа к Claude. Попросите администратора CPA включить его. |
| `не прошло проверку подлинности`, `Контрольная сумма ... не совпала` | Скрипт ничего не установил. Попробуйте позже. Если повторяется — [сообщите](#помощь). |
| `Не удалось закрыть Claude` | Закройте Claude вручную и запустите команду снова. На Windows закройте и значок Claude у часов. |
| **Mac:** `нужен пароль администратора, но терминал недоступен` | Запустите команду в приложении «Терминал». |
| **Windows:** `0x80073CFF` | Windows запрещает ставить приложения не из Microsoft Store. Попросите администратора включить «Allow all trusted apps to install». |
| **Windows:** `старая версия Claude Desktop (установщик .exe)` | Вкладка Code работает. Режиму Cowork нужна новая версия: удалите Claude в «Параметры → Приложения» и запустите команду снова. |
| В Code долго идёт загрузка | Это первая докачка компонентов. Подождите несколько минут. |
| Вкладка Chat просит войти | Так и должно быть. Используйте вкладку Code. |

Не помогло? Запустите [проверку](#проверка-и-смена-ключа) и приложите её
результат к [обращению](#помощь). Ключ в результате не показывается.

### Проверить ключ отдельно от установщика

Если ключ не принимается (`HTTP 401`), так можно увидеть, что именно вы
вводите. Команда спросит ключ скрытым вводом, покажет число символов и
отпечаток (сам ключ не выводится) и спросит у сервера, принимает ли он его.
Сравните цифры с теми, что назвал администратор. Если они не совпадают, при
копировании потерялся или заменился символ: скопируйте ключ ещё раз целиком.

**macOS** (Терминал):

```bash
printf 'Вставьте ключ и нажмите Enter: '; read -rs K; echo; printf 'символов: %s\nотпечаток: %s\n' "$(printf %s "$K" | wc -c | tr -d ' ')" "$(printf %s "$K" | shasum -a 256 | cut -c1-8)"; printf 'x-api-key: %s\n' "$K" | curl -sS -o /dev/null -w 'ответ сервера: HTTP %{http_code}\n' -H @- https://cpa.2brain.pro/v1/models
```

**Windows** (PowerShell):

```powershell
$s = Read-Host 'Вставьте ключ и нажмите Enter' -AsSecureString
$k = [Net.NetworkCredential]::new('', $s).Password
$h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($k))
'символов: ' + [Text.Encoding]::UTF8.GetByteCount($k)
'отпечаток: ' + (-join ($h[0..3] | ForEach-Object { $_.ToString('x2') }))
try { $r = (Invoke-WebRequest https://cpa.2brain.pro/v1/models -Headers @{ 'x-api-key' = $k } -UseBasicParsing).StatusCode } catch { if ($_.Exception.Response) { $r = [int]$_.Exception.Response.StatusCode } else { $r = 'нет ответа' } }
'ответ сервера: HTTP ' + $r
```

Нормальный результат: `HTTP 200`. Ответ `401` означает, что сервер не принял
ключ, `нет ответа` — что нет связи с сервером.

## Проверка и смена ключа

**Windows** (PowerShell):

```powershell
# проверить, всё ли настроено (ничего не меняет)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -Check

# ввести новый ключ
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -ConfigureOnly -AskKey
```

**macOS** (Терминал):

```bash
# проверить, всё ли настроено (ничего не меняет)
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --check

# ввести новый ключ
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --configure-only --ask-key
```

Обновить приложение вручную обычно не нужно: Claude обновляется сам. Чтобы
заново применить настройку, запустите команду установки ещё раз.

## Как вернуть всё обратно

Закройте Claude и удалите папку `configLibrary`. Так советует Anthropic: в ней
только настройка подключения. Историю разговоров это не затронет.

| | Windows | macOS |
|---|---|---|
| Папка `configLibrary` | `%LOCALAPPDATA%\Claude-3p\configLibrary` | `~/Library/Application Support/Claude-3p/configLibrary` |
| Резервные копии | `%LOCALAPPDATA%\Claude-3p\.cpa-backups` | `~/Library/Application Support/Claude-3p/.cpa-backups` |
| Удалить приложение | «Параметры → Приложения → Claude» | перетащить Claude из «Программ» в Корзину |

> [!WARNING]
> В резервных копиях могут быть старые ключи. Никому их не пересылайте.

## Безопасность

- Ключ идёт только на адрес CPA и только для проверки. Скрипт не печатает его и
  не передаёт в аргументах команд.
- Скрипт берёт ключ из настроек Claude Code и Codex, только если там указан
  адрес этого же CPA. Ключи Anthropic, OpenAI и других сервисов не
  используются.
- Код вкладки Code может ходить по любым адресам в интернете
  (`coworkEgressAllowedHosts: ["*"]`), иначе не работает, например, установка
  пакетов. Строгий список можно задать в профиле вручную.
- Хотите сначала прочитать скрипт? Скачайте `install.ps1` или `install.sh` из
  этого репозитория, откройте его и запустите сами.
- О найденных уязвимостях сообщайте по правилам из [SECURITY.md](SECURITY.md),
  а не в открытых обращениях.

## Для администраторов

<details>
<summary>Модели, параметры, устройство</summary>

**Основные модели CPA.** Alias создаются один раз на сервере скриптом
`scripts/sync-cpa-main-models.py` (нужен management key); пользователю он не
нужен. Установщик добавляет только те alias, которые доступны ключу. Скрипт
выдаёт ключу и три базовые модели Claude 5.5 (Opus, Sonnet, Haiku): их alias на
сервере уже есть, новые не создаются.

Имя alias говорит, на какую модель он указывает и для чего он: `семейство-модель-версия-claude-code`.
Первое слово (`opus`, `sonnet`, `haiku`) нужно приложению, чтобы понять класс
модели, а `claude-code` означает, что alias сделан для Claude Code. Слова `gpt`,
`codex`, `deepseek`, `gemini` в имени нельзя: Claude Desktop такие имена
отбрасывает.

| Подпись в Claude | Alias | Модель в CPA |
|---|---|---|
| GPT 6.2 Astra | `opus-astra-6-2-claude-code` | `gpt-6.2-astra` |
| GPT 6.2 Sol | `sonnet-sol-6-2-claude-code` | `gpt-6.2-sol` |
| GPT 6.1 Terra | `sonnet-terra-6-1-claude-code` | `gpt-6.1-terra` |
| GPT-6 Luna | `haiku-luna-6-claude-code` | `gpt-6-luna` |

Когда в каталоге появится `gpt-6.2-terra`, достаточно сменить модель для Terra
(поле `source` в скрипте и имя alias).

Выдать доступ **одному ключу** (рекомендуется), сначала посмотрев план:

```bash
export CPA_MANAGEMENT_KEY=...   # либо --management-key-file
python3 scripts/sync-cpa-main-models.py --key-name 'ИМЯ_КЛЮЧА'           # показать план
python3 scripts/sync-cpa-main-models.py --key-name 'ИМЯ_КЛЮЧА' --apply   # применить
```

Для всех существующих ключей: `--all-keys` вместо `--key-name`. Перед
изменением скрипт сохраняет снимок политики (права `600`), а после читает её
заново и проверяет результат. Старые alias (`...-cpa`) на сервере не
удаляются: у кого они уже записаны, продолжают работать. Чтобы убрать их с
компьютера, используйте `--remove-model`.

**Свои модели.** Claude Desktop отбрасывает имена с `deepseek`, `gpt`,
`gemini` и другими чужими названиями, поэтому такую модель публикуют в CPA под
alias с `claude-` или `sonnet`/`haiku` в имени. Формат: `ID`, `ID=Подпись` или
`ID=Подпись=Claude-модель` (третий элемент задаёт лимиты и уровни effort).
Модели хранятся в `models.json` (Windows: `%LOCALAPPDATA%\claude-desktop-cpa`,
Mac: `~/.config/claude-desktop-cpa`), ключей в файле нет. Три базовые модели
всегда первые.

```powershell
# Windows: посмотреть, добавить, убрать
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -ListModels
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -AddModel 'claude-opus-4-8=Opus 4.8' -ConfigureOnly
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -RemoveModel claude-opus-4-8 -ConfigureOnly
```

```bash
# macOS: посмотреть, добавить, убрать
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --list-models
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --add-model 'claude-opus-4-8=Opus 4.8' --configure-only
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --remove-model claude-opus-4-8 --configure-only
```

`--claude-only` / `-ClaudeOnly` не удаляет ранее добавленные модели, а только
не добавляет новые.

**Если ключ не принят (`401`).** Скрипт убирает из ключа лишние пробелы,
переводы строк и коды вставки, а при отказе пишет длину и отпечаток (первые 8
символов SHA-256) того, что получил, но не сам ключ. Ожидаемые значения
администратор считает так: `printf '%s' "$KEY" | wc -c` и
`printf '%s' "$KEY" | shasum -a 256 | cut -c1-8`. Если они не совпадают, при
копировании потерялся или заменился символ (например, русская «с» вместо
латинской `c`).

**Параметры.**

| Mac | Windows | Что делает |
|---|---|---|
| `--check` | `-Check` | Проверить состояние, ничего не меняя |
| `--dry-run` | `-DryRun` | Показать план, ничего не меняя |
| `--configure-only` | `-ConfigureOnly` | Только настройка, без установки приложения |
| `--no-update` | `-NoUpdate` | Не обновлять приложение |
| `--no-restart` | `-NoRestart` | Не запускать Claude |
| `--with-chat` | `-WithChat` | Показать вкладку Chat |
| `--ask-key` | `-AskKey` | Не искать сохранённый ключ, спросить новый |
| `--yes` | `-Yes` | Не задавать вопросов |
| `--force` | `-Force` | Записать настройку, даже если ключ не прошёл проверку |
| `--base-url URL` | `-BaseUrl URL` | Другой адрес CPA |
| `--dmg-url URL` | — | Свой файл DMG или ZIP (проверка подлинности остаётся) |
| — | `-VerifyDownload` | Только скачать и проверить установщик |
| `--key KEY` | `-Key KEY` | Ключ в команде (не рекомендуется: останется в истории) |
| `--with-main-models`, `--claude-only` | `-WithMainModels`, `-ClaudeOnly` | Основные модели вкл./выкл. |
| `--list-models`, `--add-model`, `--remove-model` | `-ListModels`, `-AddModel`, `-RemoveModel` | Управление списком моделей |

**Устройство.** Настройка пишется в профиль режима third-party inference
(3P): `configLibrary\<uuid>.json`, `configLibrary\_meta.json` и
`claude_desktop_config.json` (`deploymentMode: "3p"`) в папке `Claude-3p`. Ключ
проверяется запросами `GET /v1/models` и `POST /v1/messages` к
`claude-haiku-5-5`.

- **Mac:** источник — Homebrew cask API `formulae.brew.sh/api/cask/claude.json`.
  Проверки: SHA256, bundle id, `codesign`, Team ID `Q6L2SF6YDW`, `spctl`
  (`Notarized Developer ID`). Права файлов `600`, каталогов `700`.
- **Windows:** источник — пакет MSIX с `downloads.claude.ai`; адрес и SHA256 из
  манифеста winget. Проверки: SHA256, имя пакета и идентификатор издателя
  `pzs8sxrjxfjjc`, подпись Authenticode (`Valid`, Anthropic), затем сама
  Windows при установке. Ставится на пользователя, права администратора не
  нужны. Старая установка `.exe` не трогается. Папка настроек —
  `%LOCALAPPDATA%\Claude-3p`; на Windows 10 с MSIX может быть в
  `%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\Claude-3p`.
- **Кодировка:** `install.ps1` сохранён в UTF-8 без BOM, чтобы работал
  `irm | iex`. Скачанную копию запускайте так:
  `& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1)))`.

</details>

## Для разработчиков

```bash
bash tests/test-script.sh   # Mac и Linux (включая тесты моделей)
shellcheck -x install.sh tests/*.sh
```

```powershell
./tests/test-windows.ps1   # Windows PowerShell 5.1 или PowerShell 7
```

CI запускает ShellCheck, PSScriptAnalyzer, тесты и пробный запуск на macOS и
Windows. Проверка `windows-e2e` проходит весь путь пользователя на настоящем
сервере Windows без настоящего ключа: скачивает пакет Claude, проверяет и
устанавливает его, подключает к поддельному CPA на `127.0.0.1`, запускает
приложение, запускает установщик второй раз и сохраняет снимок экрана (в
артефактах запуска). Тесты работают во временной домашней папке и не читают
ваши настройки.

## Помощь

[Создайте обращение](https://github.com/yshishenya/claude-desktop-cpa-onboarding/issues/new/choose)
и приложите результат проверки. **Никогда не вставляйте ключ CPA** в обращения
и комментарии.

## Лицензия

[MIT](LICENSE)
