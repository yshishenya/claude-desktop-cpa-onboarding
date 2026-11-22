# Claude Desktop через CPA

[![Проверка установщика](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml/badge.svg)](https://github.com/yshishenya/claude-desktop-cpa-onboarding/actions/workflows/test.yml)
[![macOS](https://img.shields.io/badge/macOS-поддерживается-000000?logo=apple)](#требования)

Скрипт устанавливает или обновляет **Claude Desktop** на macOS и настраивает
его нативный режим **third-party inference (3P)** для работы через CPA.

После установки Claude Code открывается во вкладке **Code** и использует
модели CPA. Вход в аккаунт claude.ai для этого не нужен. Вкладка **Chat**
по-прежнему требует аккаунт claude.ai — это отдельный режим приложения.

## Быстрый старт

Откройте **Терминал** и выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/yshishenya/claude-desktop-cpa-onboarding/main/install.sh | bash
```

Скрипт попросит **CPA API key**. Во время ввода символы не отображаются — это
нормально. Если ключ уже сохранён в Claude Code, Codex или в профиле Claude
Desktop, скрипт может использовать его без вопроса.

Альтернатива — клонировать репозиторий и запустить установщик вручную:

```bash
git clone https://github.com/yshishenya/claude-desktop-cpa-onboarding.git
cd claude-desktop-cpa-onboarding
./install.sh
```

Если ключ нужно передать без интерактивного ввода:

```bash
CPA_API_KEY='sk-...' ./install.sh
```

Ключ не нужно коммитить в репозиторий и не рекомендуется передавать через
`--key`: он останется в истории shell.

## Что делает скрипт

1. **Устанавливает/обновляет Claude Desktop**:
   - берёт официальный артефакт из Homebrew cask API
     `https://formulae.brew.sh/api/cask/claude.json`;
   - проверяет SHA256 ZIP, bundle id `com.anthropic.claudefordesktop`,
     подпись `codesign` и версию;
   - **не откатывает** приложение, если установленная версия новее публичного
     cask;
   - не использует страницу `claude.com/download`, потому что сейчас она
     отдаёт `Claude-Science-*.dmg`, а не Claude Desktop.

2. **Настраивает 3P-профиль**:
   - `~/Library/Application Support/Claude-3p/configLibrary/<uuid>.json`;
   - `~/Library/Application Support/Claude-3p/configLibrary/_meta.json`;
   - `~/Library/Application Support/Claude-3p/claude_desktop_config.json`.

   В профиль записываются:
   - gateway `https://cpa.2brain.pro`;
   - auth `x-api-key`;
   - модели `claude-sonnet-5-5`, `claude-opus-5-5`, `claude-haiku-5-5`;
   - `deploymentMode: "3p"` и Code-вкладка.

3. **Проверяет ключ** через `/v1/models` и реальный запрос
   `/v1/messages` к `claude-haiku-5-5`. Если ключ не имеет доступа к Claude,
   скрипт остановится с понятным сообщением; `--force` позволяет записать
   конфиг всё равно.

4. **Делает бэкапы** конфигов в
   `~/Library/Application Support/Claude-3p/.cpa-backups/` (последние 5).
   Ключ и конфиги имеют права `600`, каталоги — `700`.

## Требования

- macOS.
- CPA API key с доступом к native Claude-моделям.
- Сеть до `cpa.2brain.pro` и `downloads.claude.ai`.
- При установке в `/Applications` может потребоваться пароль администратора
  (скрипт использует `sudo`, если без него нет прав записи).

## Команды

```bash
./install.sh                  # установить/обновить, настроить CPA, перезапустить Claude
./install.sh --check          # только проверить состояние, ничего не менять
./install.sh --dry-run        # показать план действий
./install.sh --configure-only # только перенастроить, без установки/обновления
./install.sh --no-update      # не обновлять приложение
./install.sh --no-restart     # записать конфиг, но не запускать Claude
./install.sh --with-chat      # показать вкладку Chat (нужен аккаунт claude.ai)
./install.sh --help
```

## Проверка

```bash
./install.sh --check
```

Скрипт покажет версию Claude Desktop, состояние 3P-профиля, модели, тип ключа
и результат проверки. Если приложение уже забрало ключ в macOS Keychain,
`--check` покажет `key_kind: keychain` и проверит исходный ключ из настроек
Claude Code/Codex.

## Обновление

- Если публичный cask новее установленного приложения, скрипт скачает ZIP,
  проверит SHA256 и обновит Claude Desktop.
- Если установленная версия новее (обычная ситуация для канала автообновления
  Claude), скрипт ничего не откатывает. Обновление выполняет сам Claude
  Desktop.
- После обновления скрипт повторно применяет 3P-конфиг.

## Ограничения

- **Chat** в Claude Desktop требует аккаунт claude.ai. Через CPA работает
  вкладка **Code**.
- Первый запуск Code скачивает runtime Claude Code и Linux VM. Это не
  авторизация и не ошибка; дождитесь завершения загрузки.
- `coworkEgressAllowedHosts` выставляется в `["*"]`, чтобы Code не упирался в
  egress-ограничения. Если нужен строгий allowlist, его можно сузить в профиле.
- Скрипт не настраивает Claude Code CLI и не меняет обычный профиль
  `~/Library/Application Support/Claude` (1P/claude.ai).

## Разработка

```bash
bash -n install.sh
bash tests/test-script.sh
```

CI проверяет синтаксис, `--help`, статические инварианты и `--dry-run` на
macOS.
