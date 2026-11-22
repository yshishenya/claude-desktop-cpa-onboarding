# Claude Desktop через CPA

[![Проверка установщика](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml/badge.svg)](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple)](#что-понадобится)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4)](#что-понадобится)
[![Лицензия: MIT](https://img.shields.io/badge/лицензия-MIT-blue)](LICENSE)

Одна команда, которая ставит на Mac или компьютер с Windows приложение
**Claude Desktop** и настраивает его на работу через **CPA**. CPA — это
сервис-посредник: через него ваша команда получает доступ к моделям Claude
по своему ключу, без отдельного аккаунта на claude.ai.

После настройки вы работаете во вкладке **Code** приложения Claude. Вкладка
**Chat** в этом режиме не используется: ей по-прежнему нужен личный аккаунт
claude.ai.

## Содержание

- [Что понадобится](#что-понадобится)
- [Установка на Mac](#установка-на-mac)
- [Установка на Windows](#установка-на-windows)
- [Как понять, что всё получилось](#как-понять-что-всё-получилось)
- [Если что-то пошло не так](#если-что-то-пошло-не-так)
- [Проверка, обновление и повторная настройка](#проверка-обновление-и-повторная-настройка)
- [Другие модели](#другие-модели)
- [Основные модели CPA](#основные-модели-cpa)
- [Как вернуть всё обратно](#как-вернуть-всё-обратно)
- [Безопасность и ваши данные](#безопасность-и-ваши-данные)
- [Подробности для специалистов](#подробности-для-специалистов)
- [Помощь и обратная связь](#помощь-и-обратная-связь)

## Что понадобится

- **Ключ CPA** — строка, похожая на `sk-...`. Его выдаёт тот, кто управляет
  вашим доступом к CPA. У ключа должен быть доступ к моделям Claude.
- **Интернет.** Скрипт обращается к `cpa.2brain.pro` (проверка ключа),
  `downloads.claude.ai` (само приложение) и к сайтам со сведениями о
  последней версии: `formulae.brew.sh`, а на Windows ещё
  `raw.githubusercontent.com` и `api.github.com`.

**На Mac**

- macOS 13 Ventura или новее. Подходят и процессоры Apple (M1, M2 и новее),
  и Intel.
- Иногда пароль администратора Mac. Он нужен, только если ваша учётная
  запись не может сама устанавливать программы в папку «Программы».

**На Windows**

- Windows 10 версии 2004 или новее, либо Windows 11. Подходят обычные
  процессоры (x64) и процессоры ARM.
- Права администратора не нужны: приложение ставится только для вашей
  учётной записи.
- Для режима Cowork (агент, который работает в отдельной защищённой среде)
  нужна включённая виртуализация и компонент Windows «Платформа виртуальной
  машины». Скрипт проверит это и подскажет, что сделать. Вкладке Code
  этот компонент не нужен.

## Установка на Mac

**1. Откройте «Терминал».** Нажмите <kbd>⌘ Command</kbd> + <kbd>Пробел</kbd>,
наберите `Терминал` и нажмите <kbd>Enter</kbd>.

**2. Скопируйте команду, вставьте её в Терминал и нажмите <kbd>Enter</kbd>:**

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash
```

**3. Введите ключ CPA, когда скрипт попросит**, и нажмите <kbd>Enter</kbd>.
Символы при вводе не отображаются — так и задумано, ключ всё равно вводится.
Если скрипт попросит пароль, введите пароль от вашего Mac (он тоже не
отображается).

Скрипт сам скачает Claude Desktop, проверит, что это подлинное приложение
Anthropic, настроит его и запустит. Обычно это занимает несколько минут.

## Установка на Windows

**1. Откройте PowerShell.** Нажмите клавишу <kbd>⊞ Win</kbd>, наберите
`PowerShell` и нажмите <kbd>Enter</kbd>. Запускать от имени администратора
не нужно.

**2. Скопируйте команду, вставьте её в окно PowerShell** (правой кнопкой мыши
или <kbd>Ctrl</kbd> + <kbd>V</kbd>) **и нажмите <kbd>Enter</kbd>:**

```powershell
irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 | iex
```

**3. Введите ключ CPA, когда скрипт попросит**, и нажмите <kbd>Enter</kbd>.
Вместо символов ключа появятся звёздочки — так и задумано.

Скрипт сам скачает официальный пакет Claude Desktop с сайта Anthropic,
проверит его подлинность, установит, настроит и запустит. Пакет весит около
300 МБ, поэтому установка может занять несколько минут.

> [!TIP]
> Если ключ CPA уже настроен у вас в Claude Code или Codex, скрипт найдёт
> его сам и не будет спрашивать. Подробнее — в разделе
> [«Безопасность и ваши данные»](#безопасность-и-ваши-данные).

## Как понять, что всё получилось

1. В конце Терминал или PowerShell напишет **«Готово.»**.
2. Откроется приложение **Claude**.
3. Перейдите на вкладку **Code**. В списке моделей должны быть
   Claude Sonnet 5.5, Claude Opus 5.5 и Claude Haiku 5.5. Если на сервере
   настроены основные модели CPA, рядом появятся DeepSeek, GPT и Gemini.

При **первом** открытии вкладки Code приложение докачивает свои рабочие
компоненты. Это может занять несколько минут. Это не вход в аккаунт и не
ошибка: просто дождитесь окончания загрузки.

## Если что-то пошло не так

| Что вы видите | Что это значит и что делать |
|---|---|
| `Ключ ... не прошёл проверку` или `HTTP 401` | Ключ введён с ошибкой или не действует. Скопируйте ключ ещё раз целиком, без пробелов, и запустите команду снова. |
| `Ключ принят ..., но Claude-модель вернула HTTP ...` | Ключ рабочий, но к моделям Claude у него нет доступа. Попросите администратора CPA включить доступ к Claude для вашего ключа. |
| `HTTP 429` или `HTTP 5xx` | Сервер временно перегружен. Настройка всё равно записана; повторите проверку позже. |
| `не прошло проверку подлинности`, `выпущен не Anthropic`, `Контрольная сумма ... не совпала` | Скачанный файл не похож на подлинное приложение Anthropic, и скрипт ничего не установил. Проверьте подключение к интернету и попробуйте позже. Если ошибка повторяется, [сообщите о ней](#помощь-и-обратная-связь). |
| `Не удалось закрыть Claude` | Закройте Claude вручную и запустите команду снова. На Mac — <kbd>⌘ Command</kbd> + <kbd>Q</kbd>. На Windows закройте окно и значок Claude рядом с часами (правой кнопкой → выход). |
| Во вкладке Code долго идёт загрузка | Это первая докачка компонентов. Подождите несколько минут, не закрывая приложение. |
| Вкладка Chat просит войти в аккаунт | Так и должно быть: Chat работает только с аккаунтом claude.ai. Для работы через CPA используйте вкладку Code. |
| **Mac:** `нужен пароль администратора, но терминал недоступен` | Скрипт запущен не из приложения «Терминал». Откройте «Терминал» и запустите команду там. |
| **Mac:** `Пароль администратора не принят` | Введён неверный пароль или у учётной записи нет прав администратора. Попросите администратора Mac запустить команду. |
| **Windows:** `ошибка 0x80073CFF` | Политика компьютера запрещает ставить приложения не из Microsoft Store. Попросите администратора разрешить установку доверенных приложений («Allow all trusted apps to install») и запустите команду снова. |
| **Windows:** `Установлена старая версия Claude Desktop (установщик .exe)` | Вкладка Code работает и так. Для режима Cowork нужна новая версия: удалите Claude в «Параметры → Приложения» и запустите команду снова. |
| **Windows:** `«Платформа виртуальной машины» выключен` | Нужно только для режима Cowork. Откройте «Пуск» → «Включение или отключение компонентов Windows», отметьте «Платформа виртуальной машины» и перезагрузите компьютер. Для этого нужны права администратора. |
| **Windows:** `Нужна Windows 10 версии 2004 ... или новее` | Обновите Windows через «Параметры → Центр обновления Windows». |

Не нашли свою ситуацию? Запустите [проверку](#проверка-обновление-и-повторная-настройка)
и приложите её результат к [обращению](#помощь-и-обратная-связь). Проверка не
показывает сам ключ, только его короткий отпечаток.

## Проверка, обновление и повторная настройка

Обычно запускать обновление вручную не нужно: Claude Desktop обновляется
сам. Скрипт никогда не ставит более старую версию поверх новой. Если
сохранённый ключ перестал работать, обычная команда установки сама попросит
ввести новый.

### На Mac

Команды запускаются в Терминале так же, как установка. Слова после
`bash -s --` — это то, что нужно сделать.

Проверить, всё ли настроено (ничего не меняет):

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --check
```

Обновить приложение и заново применить настройку — та же команда, что при
установке:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash
```

Сменить ключ CPA (например, если выдали новый), не трогая само приложение.
Скрипт не будет искать старый ключ и сразу попросит ввести новый:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --configure-only --ask-key
```

### На Windows

Команды запускаются в PowerShell. Слова в конце команды, начинающиеся с
дефиса, — это то, что нужно сделать.

Проверить, всё ли настроено (ничего не меняет):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -Check
```

Обновить приложение и заново применить настройку — та же команда, что при
установке:

```powershell
irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 | iex
```

Сменить ключ CPA, не трогая само приложение:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -ConfigureOnly -AskKey
```

<details>
<summary>Все параметры команды</summary>

| Mac | Windows | Что делает |
|---|---|---|
| `--check` | `-Check` | Только проверить состояние, ничего не менять |
| `--dry-run` | `-DryRun` | Показать, что было бы сделано, ничего не меняя |
| `--configure-only` | `-ConfigureOnly` | Только перенастроить, не устанавливать и не обновлять приложение |
| `--no-update` | `-NoUpdate` | Не обновлять приложение, если оно уже стоит |
| `--no-restart` | `-NoRestart` | Записать настройку, но не запускать Claude |
| `--with-chat` | `-WithChat` | Показывать вкладку Chat (ей нужен аккаунт claude.ai) |
| `--with-main-models` | `-WithMainModels` | Добавить основные модели CPA (включено по умолчанию) |
| `--claude-only` | `-ClaudeOnly` | Только три базовые модели Claude, без DeepSeek, GPT и Gemini |
| `--list-models` | `-ListModels` | Показать модели Claude, доступные вашему ключу CPA |
| `--add-model SPEC` | `-AddModel SPEC` | Добавить модель в список Claude: `ID`, `ID=Подпись` или `ID=Подпись=Claude-модель` |
| `--remove-model ID` | `-RemoveModel ID` | Убрать модель, добавленную через `--add-model` |
| `--yes` | `-Yes` | Не задавать вопросов, если ключ уже найден |
| `--ask-key` | `-AskKey` | Не искать сохранённый ключ, а сразу спросить новый |
| `--force` | `-Force` | Записать настройку, даже если проверка ключа не прошла |
| `--base-url URL` | `-BaseUrl URL` | Другой адрес CPA (по умолчанию `https://cpa.2brain.pro`) |
| `--dmg-url URL` | — | Установить приложение из своего файла DMG или ZIP. Файл всё равно должен пройти проверку подлинности |
| — | `-VerifyDownload` | Только скачать и проверить установщик, ничего не устанавливая |
| `--key KEY` | `-Key KEY` | Передать ключ в команде. Не рекомендуется: ключ останется в истории команд |
| `--help` | `-Help` | Показать справку |

> В PowerShell несколько моделей в `-AddModel` перечисляют через запятую:
> `-AddModel 'a=A','b=B'`. Параметры вида `ID=Подпись` берите в кавычки.

</details>

## Другие модели

Три базовые модели — **Claude Sonnet 5.5**, **Claude Opus 5.5** и
**Claude Haiku 5.5** — остаются в списке всегда. Если ваш ключ CPA открывает
другие модели Claude, их можно добавить вручную. Основные модели CPA
(DeepSeek, GPT, Gemini) установщик добавляет по умолчанию, если для них
настроены alias и доступ ключа.

Посмотреть, что доступно вашему ключу:

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --list-models
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -ListModels
```

Добавить модель (подпись после `=` необязательна):

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --add-model 'claude-opus-4-8=Opus 4.8' --configure-only
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -AddModel 'claude-opus-4-8=Opus 4.8' -ConfigureOnly
```

Можно добавить несколько моделей сразу:

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- \
  --add-model 'claude-sonnet-5=Sonnet 5' \
  --add-model 'claude-fable-5-2=Fable 5.2' \
  --configure-only
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) `
  -AddModel 'claude-sonnet-5=Sonnet 5','claude-fable-5-2=Fable 5.2' `
  -ConfigureOnly
```

Если модель не от Anthropic, под исходным именем её добавить нельзя: Claude
Desktop принимает только ID, похожие на Anthropic, и отбрасывает `deepseek-*`,
`gpt-*`, `gemini-*` и подобные. Администратор CPA публикует такую модель под
alias с `claude-` или названием семейства (`sonnet`, `haiku`) в имени —
например, `sonnet-4-5-cpa`. После этого добавьте alias. Третий элемент
задаёт `behavesAs` — лимиты и уровни effort:

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- \
  --add-model 'sonnet-4-5-cpa=DeepSeek V4 Pro=claude-sonnet-5' \
  --add-model 'haiku-4-5-cpa=DeepSeek V4.1 Flash=claude-haiku-5-5' \
  --configure-only
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) `
  -AddModel 'sonnet-4-5-cpa=DeepSeek V4 Pro=claude-sonnet-5','haiku-4-5-cpa=DeepSeek V4.1 Flash=claude-haiku-5-5' `
  -ConfigureOnly
```

Пример маршрута в CPA (`cpa-key-policy`):

```yaml
aliases:
  - alias: sonnet-4-5-cpa
    targets:
      - provider: opencode-go
        target_model: opencode-go/deepseek-v4-pro
```

Alias нужно добавить и в список моделей вашего ключа CPA, иначе запрос
получит `401 Invalid API key`.

Третий элемент попадает в поле `behavesAs`: приложение будет знать, что это
за модель, какие у неё лимиты и какие уровни effort показывать.

Убрать добавленную модель:

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash -s -- --remove-model claude-opus-4-8 --configure-only
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -RemoveModel claude-opus-4-8 -ConfigureOnly
```

Что важно знать:

- Три базовые модели остаются в списке всегда. Первая модель списка
  считается моделью по умолчанию — это Sonnet 5.5.
- Добавленные модели сохраняются в файле `models.json`: на Mac —
  `~/.config/claude-desktop-cpa/models.json`, на Windows —
  `%LOCALAPPDATA%\claude-desktop-cpa\models.json`. Обычный запуск
  установщика их не удаляет. В этом файле нет ключей.
- После изменения списка Claude нужно перезапустить. Установщик делает это
  сам, если не указан `--no-restart` (на Windows — `-NoRestart`).
- Модели не-Claude (`gpt-*`, `gemini-*`, `deepseek-*` и другие) добавляются
  только через alias, опубликованный в CPA. Установщик откажется записывать
  такой ID напрямую: Claude Desktop всё равно выбросит его из списка.
- Даже с alias поведение не-Claude модели зависит от CPA и может отличаться
  от Claude: приложение ожидает Claude-специфичные возможности. Для
  повседневной работы надёжнее модели Claude.

## Основные модели CPA

Это короткий набор моделей, который установщик добавляет **по умолчанию**.
Если серверные alias не настроены или у ключа нет к ним доступа, установщик
пропустит их и оставит только Claude-модели.

| Подпись в Claude | Alias | Модель в CPA |
|---|---|---|
| DeepSeek V4 Pro | `sonnet-4-5-cpa` | `opencode-go/deepseek-v4-pro` |
| DeepSeek V4.1 Flash | `haiku-4-5-cpa` | `opencode-go/deepseek-v4.1-flash` |
| GPT 6.2 Astra | `opus-6-2-astra-cpa` | `gpt-6.2-astra` |
| GPT 6.2 Sol | `sonnet-6-2-sol-cpa` | `gpt-6.2-sol` |
| GPT-6 Luna | `haiku-6-luna-cpa` | `gpt-6-luna` |
| Gemini 4 Argon | `sonnet-4-argon-cpa` | `opencode-go/gemini-4-argon` |

### Один раз на сервере

Alias создаются **не у каждого пользователя**, а один раз в CPA. Есть два
уровня:

1. **Глобальный alias** — имя, которое видит клиент, и маршрут к модели CPA.
2. **Доступ ключа** — alias нужно добавить в список моделей конкретного
   ключа CPA.

Скрипт `scripts/sync-cpa-main-models.py` делает оба шага через management
API CPA. По умолчанию он только показывает план:

```bash
python3 scripts/sync-cpa-main-models.py --all-keys
```

Применить изменения для всех существующих ключей:

```bash
python3 scripts/sync-cpa-main-models.py --all-keys --apply
```

Скрипт попросит management key скрытым вводом. Его также можно передать
через `CPA_MANAGEMENT_KEY` или `--management-key-file`. Management key — это
административный секрет: не вставляйте его в историю shell и не передавайте
пользователям.

Перед изменениями скрипт сохраняет снимок политики в
`cpa-policy-backup-<дата>.json` (права `600`). После применения он читает
политику заново и проверяет, что alias и доступы появились.

Если позже вы создадите новый ключ CPA, повторите команду с `--all-keys` —
она добавит ему те же модели.

### На каждом компьютере

Пользователю management key не нужен. Установщик по умолчанию проверяет,
какие из основных alias доступны его ключу, и добавляет только их:

На Mac:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash
```

На Windows:

```powershell
irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 | iex
```

Если нужны только три базовые модели Claude.

На Mac (из клонированного репозитория):

```bash
./install.sh --claude-only
```

На Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1))) -ClaudeOnly
```

Модели, к которым у ключа нет доступа, пропускаются с предупреждением.
Повторный запуск уже добавленные модели не удаляет; `--claude-only` тоже не
удаляет их, а только не добавляет новые. Для удаления используйте
`--remove-model` (на Windows — `-RemoveModel`).

## Как вернуть всё обратно

Перед каждой настройкой скрипт сохраняет прежние файлы в папку
`.cpa-backups`. Там хранятся пять последних копий, каждая в папке с датой и
временем.

| | Mac | Windows |
|---|---|---|
| Папка настроек | `~/Library/Application Support/Claude-3p` | `%LOCALAPPDATA%\Claude-3p` |
| Резервные копии | `…/Claude-3p/.cpa-backups/` | `%LOCALAPPDATA%\Claude-3p\.cpa-backups\` |
| Удаление приложения | Перетащите **Claude** из «Программ» в Корзину | «Параметры → Приложения → Claude → Удалить» |

**Вернуть прежнюю настройку.** Закройте Claude и скопируйте файлы из нужной
резервной копии обратно: `_meta.json` и файлы профиля — в папку
`Claude-3p/configLibrary`, `claude_desktop_config.json` — в папку
`Claude-3p`.

**Убрать настройку CPA совсем.** Закройте Claude и удалите папку
`configLibrary` внутри папки настроек. Так советует Anthropic: эта папка
хранит только настройку подключения. Если удалить всю папку `Claude-3p`,
пропадёт и история разговоров, которые вы вели через CPA.

Обычный профиль Claude для аккаунта claude.ai скрипт не трогает.

> [!WARNING]
> В резервных копиях могут быть старые ключи CPA. Не пересылайте эти
> файлы и не выкладывайте их в общий доступ.

## Безопасность и ваши данные

**Что скрипт читает, чтобы найти ключ** (по порядку):

1. ключ, переданный в команде (`--key` / `-Key` или переменная `CPA_API_KEY`);
2. текущую настройку CPA в Claude Desktop — только если она указывает на
   тот же адрес CPA;
3. настройки Claude Code (`~/.claude/settings.json`, на Windows —
   `%USERPROFILE%\.claude\settings.json`) — только если там указан адрес CPA
   (`ANTHROPIC_BASE_URL`);
4. настройки Codex (`~/.codex/config.toml`, на Windows —
   `%USERPROFILE%\.codex\config.toml`) — только из раздела, где указан адрес
   CPA;
5. если ничего не нашлось, просит ввести ключ.

Ключи для других сервисов, например прямые ключи Anthropic или OpenAI,
скрипт **не берёт и никуда не отправляет**.

**Куда уходит ключ.** Только на адрес CPA, и только чтобы проверить, что он
работает. Скрипт не печатает ключ на экран и не передаёт его в аргументах
команд. При первом запуске Claude сам шифрует ключ средствами системы
(связка ключей на Mac, защита данных Windows) и дальше хранит его в
зашифрованном виде.

**Что меняется на компьютере.**

- **Mac:** в папке «Программы» появляется или обновляется **Claude.app**.
  Перед установкой скрипт проверяет контрольную сумму файла, подпись
  Anthropic и проверку (нотаризацию) Apple. Только после этого он снимает
  предупреждение macOS о первом запуске программы из интернета. Пароль
  администратора нужен только для записи в папку «Программы».
- **Windows:** устанавливается официальный пакет Claude (MSIX) только для
  вашей учётной записи. Перед установкой скрипт проверяет контрольную сумму
  файла, что пакет выпущен Anthropic, и цифровую подпись; при установке
  Windows ещё раз проверяет подпись сама. Права администратора не нужны.
- В папке настроек `Claude-3p` записывается профиль CPA. Доступ к ней есть
  только у вашей учётной записи (и у администраторов компьютера).

**Доступ в интернет из вкладки Code.** Скрипт разрешает коду, который
запускает Claude во вкладке Code, обращаться к любым адресам в интернете
(`coworkEgressAllowedHosts: ["*"]`). Без этого многие задачи, например
установка пакетов, не работают. Если в вашей организации нужен строгий
список разрешённых адресов, его можно задать в профиле CPA вручную.

**Хотите сначала посмотреть скрипт?** Это хорошая привычка для любых команд,
которые скачивают и сразу запускают программу. Скачайте файл, откройте его и
запустите, когда убедитесь, что всё в порядке.

На Mac:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh
```

```bash
open -e install.sh
```

```bash
bash install.sh
```

На Windows (последняя команда читает файл как UTF-8, иначе PowerShell может
неправильно прочитать русский текст):

```powershell
irm https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.ps1 -OutFile install.ps1
```

```powershell
notepad install.ps1
```

```powershell
& ([scriptblock]::Create((Get-Content -Raw -Encoding UTF8 .\install.ps1)))
```

О найденных уязвимостях сообщайте по правилам из [SECURITY.md](SECURITY.md),
а не в открытых обращениях.

## Подробности для специалистов

<details>
<summary>Mac: как устроена установка и настройка</summary>

**Установка и обновление приложения**

- Источник — официальный Homebrew cask API
  `https://formulae.brew.sh/api/cask/claude.json` (универсальная сборка ZIP).
  `brew` при этом не нужен и не используется.
- Проверки: SHA256 архива из cask, bundle id `com.anthropic.claudefordesktop`,
  `codesign --verify --deep --strict`, Team ID `Q6L2SF6YDW` (Anthropic PBC),
  `spctl --assess` с результатом `Notarized Developer ID`. Скачанная копия
  проверяется до замены установленной, а установленная копия — ещё раз
  после копирования; при ошибке возвращается прежняя версия.
- Если установленная версия новее, чем в cask (обычно так и бывает, потому
  что приложение обновляется само), скрипт ничего не откатывает.
- Страница загрузки claude.com не используется: на момент написания она
  отдавала другой продукт.

**Профиль third-party inference (3P)**

- `~/Library/Application Support/Claude-3p/configLibrary/<uuid>.json` — профиль;
- `~/Library/Application Support/Claude-3p/configLibrary/_meta.json` — выбор
  активного профиля (`appliedId`);
- `~/Library/Application Support/Claude-3p/claude_desktop_config.json` —
  `deploymentMode: "3p"`.

Права на файлы — `600`, на каталоги — `700`.

Список моделей можно расширить. `--add-model` сохраняет выбранные модели в
`~/.config/claude-desktop-cpa/models.json` и добавляет их в
`inferenceModels` после трёх базовых. Поддерживаются поля Claude Desktop:
`labelOverride`, `supports1m`, `prefer1m`, `anthropicFamilyTier`,
`isFamilyDefault`, `behavesAs`, `maxEffort`. Первая модель списка — модель
по умолчанию.

Claude Desktop принимает в `inferenceModels` только ID, похожие на Anthropic,
и отбрасывает имена с `deepseek`, `gpt`, `gemini` и другими чужими
названиями. Поэтому не-Claude модель сначала публикуют в CPA под alias с
`claude-` или названием семейства в имени, например `sonnet-4-5-cpa`, а в
профиль добавляют уже этот alias.

После первого запуска приложение переносит ключ в связку ключей macOS
(Keychain); в этом случае
`--check` покажет `key_kind: keychain`.

</details>

<details>
<summary>Windows: как устроена установка и настройка</summary>

**Установка и обновление приложения**

- Источник — официальный пакет MSIX с `downloads.claude.ai`. Адрес и SHA256
  берутся из манифеста winget (`microsoft/winget-pkgs`,
  `manifests/a/Anthropic/Claude`); последняя версия — из того же Homebrew
  cask API, а при его недоступности — из списка версий winget. Если
  манифест недоступен, используется официальная ссылка
  `claude.ai/api/desktop/win32/<arch>/msix/latest/redirect` без SHA256, а
  проверки пакета ниже остаются в силе.
- Проверки до установки: SHA256; в `AppxManifest.xml` имя пакета `Claude`
  и издатель, у которого идентификатор издателя (хеш от имени) равен
  `pzs8sxrjxfjjc`, то есть семейство пакета `Claude_pzs8sxrjxfjjc`;
  `Get-AuthenticodeSignature` со статусом `Valid` и подписантом Anthropic.
  Затем `Add-AppxPackage` — Windows сама проверяет, что подпись совпадает с
  издателем.
- Обновление только на более новую версию. Старая установка через `.exe`
  (`%LOCALAPPDATA%\AnthropicClaude`) не трогается: она обновляется сама.
- Закрываются только процессы Claude Desktop (по пути к пакету), а не
  `claude.exe` от Claude Code CLI.

**Профиль third-party inference (3P)**

По [документации Anthropic](https://claude.com/docs/third-party/claude-desktop/data-storage)
данные режима 3P на Windows лежат в `%LOCALAPPDATA%\Claude-3p\`. При
установке MSIX на Windows до сборки 22000 (Windows 10) папка может быть в
`%LOCALAPPDATA%\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Local\Claude-3p\`;
скрипт сначала ищет уже существующую папку. Файлы те же, что на Mac:
`configLibrary\<uuid>.json`, `configLibrary\_meta.json`,
`claude_desktop_config.json`. При следующем запуске приложение шифрует ключ
через DPAPI; `-Check` тогда покажет `key_kind: encrypted`.

**Список моделей**

Логика та же, что на Mac: основные модели CPA проверяются запросом
`POST /v1/messages` с вашим ключом, и добавляются только доступные (ответы
`429` и `5xx` считаются временными, модель остаётся). Модели хранятся в
`%LOCALAPPDATA%\claude-desktop-cpa\models.json` и дописываются в
`inferenceModels` после трёх базовых. Список основных моделей и фильтр имён
других производителей совпадают с `install.sh`: это проверяет тест.

**Кодировка и запуск**

`install.ps1` сохранён в UTF-8 **без** BOM: так его правильно читает
`irm | iex`. Windows PowerShell 5.1 читает файл без BOM в кодировке ANSI,
поэтому скачанную копию запускают через
`[scriptblock]::Create((Get-Content -Raw -Encoding UTF8 …))`. При запуске
через `iex` скрипт не вызывает `exit`, чтобы не закрыть окно PowerShell;
результат доступен в `$LASTEXITCODE`.

</details>

**Общее для обеих систем.** В профиль записываются шлюз
`https://cpa.2brain.pro`, схема авторизации `x-api-key`, модели
`claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-5-5`, а также
`chatTabEnabled` и `coworkEgressAllowedHosts`. Ключ проверяется запросами
`GET /v1/models` и пробным `POST /v1/messages` к `claude-haiku-5-5`
(`max_tokens: 8`); ошибки `429` и `5xx` считаются временными. Скрипты не
настраивают Claude Code CLI и не меняют обычный профиль Claude для аккаунта
claude.ai.

### Разработка

Mac и Linux:

```bash
bash -n install.sh
```

```bash
shellcheck -x install.sh tests/test-script.sh tests/test-models.sh
```

```bash
bash tests/test-script.sh
```

Windows (Windows PowerShell 5.1 или PowerShell 7):

```powershell
./tests/test-windows.ps1
```

Проверка синтаксиса Python-скрипта для администратора CPA:

```bash
python3 -m py_compile scripts/sync-cpa-main-models.py
```

CI проверяет синтаксис, ShellCheck и PSScriptAnalyzer, справку, правила
поиска ключей, запись настроек, синтаксис Python-скрипта и пробный запуск на
macOS и Windows (в PowerShell 5.1 и 7). Отдельная проверка `windows-e2e`
скачивает настоящий пакет Claude, проверяет его подлинность, устанавливает
его и записывает настройку с ненастоящим ключом. Тесты используют
временную домашнюю папку и не читают настоящие настройки разработчика.

## Помощь и обратная связь

- Нашли ошибку или что-то непонятно — [создайте обращение (issue)](https://github.com/yshishenya/claude-desktop-cpa-onboarding/issues/new/choose).
- Уязвимость или утечка ключа — по правилам из [SECURITY.md](SECURITY.md).
- Никогда не вставляйте ключ CPA в обращения и комментарии.

## Лицензия

[MIT](LICENSE).
