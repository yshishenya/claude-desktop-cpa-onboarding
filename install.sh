#!/usr/bin/env bash
# claude-desktop-cpa
#
# macOS: install/update Claude Desktop and configure its native
# "third-party inference" (3P) mode to use CPA.
#
# Design notes:
# - Claude Desktop keeps 3P data in ~/Library/Application Support/Claude-3p.
#   The normal ~/Library/Application Support/Claude (1P / claude.ai) is not touched.
# - 3P gateway config lives in Claude-3p/configLibrary/<uuid>.json and is
#   selected by Claude-3p/configLibrary/_meta.json:appliedId.
# - Claude-3p/claude_desktop_config.json must contain deploymentMode="3p".
# - The public Homebrew cask can lag the app's own update channel. This script
#   never uses `brew upgrade --cask claude`, so it cannot downgrade a newer app.
# - The official Homebrew cask API is used for install/update (the public
#   claude.com/download page currently serves Claude Science, not Desktop).
#   The artifact version is compared with the installed app before replacing.
# - The CPA key is only written to a 0600 profile file and a 0600 temporary file;
#   it is never printed and never placed in argv.
# - Keys found in Claude Code / Codex settings are reused only when those
#   settings already point at the same CPA host. Unrelated keys (for example a
#   direct Anthropic or OpenAI key) are never sent to CPA.
# - The installed app must be signed by Anthropic (Team ID below) and
#   notarized by Apple before the quarantine attribute is removed.

set -Eeuo pipefail
umask 077

readonly APP_PATH="/Applications/Claude.app"
readonly APP_BUNDLE_ID="com.anthropic.claudefordesktop"
readonly APP_TEAM_ID="Q6L2SF6YDW"
readonly APP_NAME="Claude"
readonly DEFAULT_BASE_URL="https://cpa.2brain.pro"
readonly SUPPORT_DIR="${HOME}/Library/Application Support/Claude-3p"
readonly LOG_DIR="${HOME}/Library/Logs/Claude-3p"
readonly PROFILE_NAME="CPA"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/claude-desktop-cpa"
readonly MODELS_FILE="${CONFIG_DIR}/models.json"
readonly MODEL_SONNET="claude-sonnet-5-5"
readonly MODEL_OPUS="claude-opus-5-5"
readonly MODEL_HAIKU="claude-haiku-5-5"

BASE_URL="${DEFAULT_BASE_URL}"
KEY=""
DMG_URL=""
DO_INSTALL=1
DO_UPDATE=1
DO_CONFIGURE=1
DO_RESTART=1
WITH_CHAT=0
FORCE=0
ASSUME_YES=0
ASK_KEY=0
CHECK=0
DRY_RUN=0
LIST_MODELS=0
ADD_MODELS=()
REMOVE_MODELS=()

TMP_DIR=""
MOUNT_DIR=""
TMP_FILES=()

cleanup() {
  set +e
  if [[ -n "${MOUNT_DIR:-}" ]]; then
    hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
  if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
    for f in "${TMP_FILES[@]}"; do
      [[ -n "${f:-}" ]] && rm -f "${f}" 2>/dev/null || true
    done
  fi
  if [[ -n "${TMP_DIR:-}" ]]; then
    rm -rf "${TMP_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"
}

new_tmp_file() {
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/claude-cpa.XXXXXX")"
  TMP_FILES+=("$f")
  printf '%s\n' "$f"
}

# True when a controlling terminal can actually be opened. `curl ... | bash`
# leaves stdin as a pipe, but /dev/tty is still usable for prompts and sudo.
have_tty() {
  [[ -t 0 ]] && return 0
  { : </dev/tty; } 2>/dev/null
}

read_secret() {
  local prompt="$1" var="$2"
  if [[ -t 0 ]]; then
    printf '%s' "$prompt" >&2
    IFS= read -r -s "${var?}"
    printf '\n' >&2
    return 0
  fi
  if have_tty; then
    printf '%s' "$prompt" > /dev/tty
    IFS= read -r -s "${var?}" < /dev/tty
    printf '\n' > /dev/tty
    return 0
  fi
  return 1
}

# Extra models are persisted outside the 3P profile, because the profile is
# rewritten on every run. Only model IDs and labels are stored here; keys
# never reach this file.
update_models_file() {
  local mode="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  mkdir -p "$CONFIG_DIR" || die "Не удалось создать $CONFIG_DIR"
  chmod 700 "$CONFIG_DIR" 2>/dev/null || true
  python3 - "$MODELS_FILE" "$mode" "$@" <<'PY'
import json, os, sys

path, mode, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception:
    data = []
if not isinstance(data, list):
    data = []
data = [x for x in data if isinstance(x, dict) and isinstance(x.get("name"), str)]

TIERS = ("fable", "mythos", "opus", "haiku", "sonnet")
ALLOWED = (
    "name", "labelOverride", "supports1m", "prefer1m",
    "anthropicFamilyTier", "isFamilyDefault", "behavesAs", "maxEffort",
)

def tier_for(name):
    low = name.lower()
    for tier in TIERS:
        if tier in low:
            return tier
    return "sonnet"

def clean(entry):
    return {k: entry[k] for k in ALLOWED if k in entry}

if mode == "add":
    index = {x.get("name"): i for i, x in enumerate(data)}
    for spec in specs:
        name, _, label = spec.partition("=")
        name = name.strip()
        label = label.strip()
        if not name:
            raise SystemExit("пустой ID модели")
        entry = {
            "name": name,
            "supports1m": False,
            "labelOverride": label or name,
            "anthropicFamilyTier": tier_for(name),
        }
        if name in index:
            data[index[name]] = entry
        else:
            index[name] = len(data)
            data.append(entry)
        print("добавлена модель:", name)
else:
    removing = {s.strip() for s in specs if s.strip()}
    before = len(data)
    data = [x for x in data if x.get("name") not in removing]
    print("удалено моделей:", before - len(data))

data = [clean(x) for x in data]
os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
}

# Comma-separated names of models added through --add-model, for logs.
models_summary() {
  python3 - "$MODELS_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(0)
names = [x.get("name") for x in data if isinstance(x, dict) and x.get("name")]
print(", ".join(names))
PY
}

# Prints the lowercase host of a URL (no scheme, port, path or credentials).
url_host() {
  local u="${1#*://}"
  u="${u%%/*}"
  u="${u##*@}"
  u="${u%%:*}"
  printf '%s\n' "$u" | tr '[:upper:]' '[:lower:]'
}

usage() {
  cat <<'EOF'
claude-desktop-cpa — установка/обновление Claude Desktop и настройка CPA.

Использование:
  claude-desktop-cpa [опции]

Опции:
  --check              Только проверить состояние, ничего не менять.
  --dry-run            Показать план действий, ничего не менять.
  --configure-only     Не устанавливать/не обновлять приложение.
  --no-update          Не обновлять приложение.
  --no-restart         Записать конфиг, но не запускать Claude.
  --with-chat          Показать вкладку Chat (ей нужен вход в claude.ai).
  --list-models        Показать модели Claude, доступные ключу CPA.
  --add-model SPEC     Добавить модель в список Claude. SPEC: ID или
                       ID=Подпись. Можно повторять. Пример:
                       --add-model 'claude-opus-4-8=Opus 4.8'
  --remove-model ID    Убрать модель, добавленную через --add-model.
  --key KEY            CPA API-ключ. Ключ, набранный в команде, остаётся
                       в истории терминала; безопаснее ввести его по запросу.
  --base-url URL       Адрес CPA (по умолчанию https://cpa.2brain.pro).
  --dmg-url URL        Свой URL DMG или ZIP для установки/обновления.
                       Приложение всё равно должно быть подписано Anthropic
                       и заверено Apple.
  --force              Записать конфиг даже если проверка Claude не прошла.
  --yes                Не задавать вопросов (если ключ уже найден).
  --ask-key            Не искать сохранённый ключ, а спросить новый
                       (например, после замены или отзыва ключа).
  --help               Эта справка.

Запуск с опциями без скачивания репозитория:
  curl -fsSL <адрес install.sh> | bash -s -- --check

Ключ ищется в таком порядке:
  1. --key
  2. CPA_API_KEY
  3. текущий профиль Claude-3p, если он смотрит на тот же адрес CPA
  4. ~/.claude/settings.json (ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY),
     только если ANTHROPIC_BASE_URL указывает на тот же адрес CPA
  5. ~/.codex/config.toml, только из раздела провайдера, у которого
     base_url указывает на тот же адрес CPA
  6. ввод по запросу
Ключи для других сервисов (например, прямые ключи Anthropic или OpenAI)
не используются и никуда не отправляются.

Что настраивается:
  - ~/Library/Application Support/Claude-3p/configLibrary/<uuid>.json
  - ~/Library/Application Support/Claude-3p/configLibrary/_meta.json
  - ~/Library/Application Support/Claude-3p/claude_desktop_config.json

Список моделей:
  - по умолчанию: claude-sonnet-5-5, claude-opus-5-5, claude-haiku-5-5;
  - --add-model добавляет модель в inferenceModels и сохраняет выбор в
    ~/.config/claude-desktop-cpa/models.json, поэтому повторный запуск
    установщика его не потеряет;
  - tier (sonnet/opus/haiku/fable/mythos) определяется по ID модели;
  - после изменения списка Claude нужно перезапустить.

Источник установки:
  - официальный Homebrew cask claude (ZIP), актуальная версия из
    https://formulae.brew.sh/api/cask/claude.json;
  - страница claude.com/download сейчас отдаёт Claude Science и не используется;
  - если установленная версия новее публичного cask, скрипт не откатывает
    приложение: обновление выполняет сам Claude Desktop.

Важно:
  - Chat в Claude Desktop по-прежнему требует аккаунт claude.ai.
  - Для Claude Code используется вкладка Code; она работает через CPA.
  - Первый запуск Code скачивает runtime Claude Code; это не авторизация.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check) CHECK=1; DO_INSTALL=0; DO_UPDATE=0; DO_CONFIGURE=0; DO_RESTART=0 ;;
      --dry-run) DRY_RUN=1; DO_INSTALL=0; DO_UPDATE=0; DO_CONFIGURE=0 ;;
      --configure-only) DO_INSTALL=0; DO_UPDATE=0 ;;
      --no-update) DO_UPDATE=0 ;;
      --no-restart) DO_RESTART=0 ;;
      --with-chat) WITH_CHAT=1 ;;
      --list-models) LIST_MODELS=1; DO_INSTALL=0; DO_UPDATE=0; DO_CONFIGURE=0; DO_RESTART=0 ;;
      --add-model) shift; [[ $# -gt 0 ]] || die "--add-model требует значение"; ADD_MODELS+=("$1") ;;
      --add-model=*) ADD_MODELS+=("${1#*=}") ;;
      --remove-model) shift; [[ $# -gt 0 ]] || die "--remove-model требует значение"; REMOVE_MODELS+=("$1") ;;
      --remove-model=*) REMOVE_MODELS+=("${1#*=}") ;;
      --force) FORCE=1 ;;
      --yes) ASSUME_YES=1 ;;
      --ask-key) ASK_KEY=1 ;;
      --key) shift; [[ $# -gt 0 ]] || die "--key требует значение"; KEY="$1" ;;
      --key=*) KEY="${1#*=}" ;;
      --base-url) shift; [[ $# -gt 0 ]] || die "--base-url требует значение"; BASE_URL="$1" ;;
      --base-url=*) BASE_URL="${1#*=}" ;;
      --dmg-url) shift; [[ $# -gt 0 ]] || die "--dmg-url требует значение"; DMG_URL="$1" ;;
      --dmg-url=*) DMG_URL="${1#*=}" ;;
      -h|--help) usage; exit 0 ;;
      *) die "Неизвестная опция: $1 (см. --help)" ;;
    esac
    shift
  done
  BASE_URL="${BASE_URL%/}"
  [[ "$BASE_URL" == https://* || "$BASE_URL" == http://* ]] || die "Некорректный --base-url: $BASE_URL"
}

require_env() {
  [[ "$(uname -s)" == "Darwin" ]] || die "Скрипт предназначен только для macOS."
  need python3
  need curl
  need osascript
  need defaults
  need pgrep
  need pkill
  need shasum
  need mktemp
  need hdiutil
  need codesign
  [[ -n "${HOME:-}" ]] || die "HOME не задан."
}

app_installed() { [[ -d "$APP_PATH" && -f "$APP_PATH/Contents/Info.plist" ]]; }

app_version() {
  defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true
}

app_bundle_id() {
  defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true
}

app_running() { pgrep -x "$APP_NAME" >/dev/null 2>&1; }

quit_app() {
  app_running || return 0
  log "Закрываю Claude..."
  osascript -e 'tell application "Claude" to quit' >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 30); do
    app_running || return 0
    sleep 0.5
  done
  warn "Claude не закрылся штатно, отправляю TERM."
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  for i in $(seq 1 20); do
    app_running || return 0
    sleep 0.5
  done
  die "Не удалось закрыть Claude. Закрой его вручную и повтори."
}

version_gt() {
  python3 - "$1" "$2" <<'PY'
import re, sys
def parts(v):
    return [int(x) for x in re.findall(r"\d+", v or "")]
a, b = parts(sys.argv[1]), parts(sys.argv[2])
n = max(len(a), len(b))
a += [0] * (n - len(a))
b += [0] * (n - len(b))
sys.exit(0 if a > b else 1)
PY
}

ARTIFACT_URL=""
ARTIFACT_VERSION=""
ARTIFACT_SHA256=""

# The public claude.com/download page currently serves Claude Science
# (Claude-Science-*.dmg), not Claude Desktop. The official Homebrew cask API
# points at the Claude Desktop zip and is the source used here.
load_artifact_info() {
  ARTIFACT_URL=""
  ARTIFACT_VERSION=""
  ARTIFACT_SHA256=""

  if [[ -n "$DMG_URL" ]]; then
    ARTIFACT_URL="$DMG_URL"
    return 0
  fi

  local json info
  json="$(curl -fsSL --max-time 20 https://formulae.brew.sh/api/cask/claude.json 2>/dev/null || true)"
  if [[ -z "$json" ]]; then
    warn "Не удалось получить метаданные официального cask claude."
    return 1
  fi

  info="$(printf '%s' "$json" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print((d.get("version") or "").split(",")[0])
print(d.get("url") or "")
print(d.get("sha256") or "")
' 2>/dev/null || true)"

  ARTIFACT_VERSION="$(printf '%s\n' "$info" | sed -n '1p')"
  ARTIFACT_URL="$(printf '%s\n' "$info" | sed -n '2p')"
  ARTIFACT_SHA256="$(printf '%s\n' "$info" | sed -n '3p')"

  if [[ -z "$ARTIFACT_URL" ]]; then
    warn "В метаданных cask claude нет URL."
    return 1
  fi
  return 0
}

run_root() {
  if [[ "${USE_SUDO:-0}" -eq 1 ]]; then
    have_tty || die "Для изменения /Applications нужен пароль администратора, но терминал недоступен. Запусти скрипт в приложении «Терминал»."
    # stdin comes from /dev/tty so nothing can eat the script when it is
    # piped through `curl ... | bash`; sudo asks for the password on the tty.
    # shellcheck disable=SC2024 # the redirect is sudo's stdin on purpose
    sudo "$@" </dev/tty
  else
    "$@"
  fi
}

# Succeeds only for a Claude.app signed by Anthropic and notarized by Apple.
verify_app_trust() {
  local app="$1" team assess
  if ! codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
    warn "Подпись приложения повреждена или отсутствует."
    return 1
  fi
  team="$(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
  if [[ "$team" != "$APP_TEAM_ID" ]]; then
    warn "Приложение подписано не Anthropic (Team ID: ${team:-нет}, ожидается $APP_TEAM_ID)."
    return 1
  fi
  assess="$(spctl --assess --type execute -vv "$app" 2>&1 || true)"
  if ! grep -q 'source=Notarized Developer ID' <<<"$assess"; then
    warn "Apple не подтвердила проверку (нотаризацию) приложения."
    return 1
  fi
  return 0
}

install_app_from_src() {
  local src="$1" installed="$2"
  local newver newid cur
  newver="$(defaults read "$src/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)"
  newid="$(defaults read "$src/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"

  [[ "$newid" == "$APP_BUNDLE_ID" ]] || {
    warn "В артефакте не Claude Desktop (bundle id: ${newid:-unknown})."
    return 1
  }

  if [[ "$installed" -eq 1 ]]; then
    cur="$(app_version)"
    if [[ -z "$newver" ]]; then
      warn "Не удалось определить версию в артефакте; обновление пропущено, чтобы не откатиться."
      return 0
    fi
    if ! version_gt "$newver" "$cur"; then
      log "Установлено $cur, в артефакте $newver — обновление не требуется."
      return 0
    fi
    log "Обновляю Claude Desktop: $cur -> $newver"
  else
    log "Устанавливаю Claude Desktop ${newver:-unknown}."
  fi

  # Check the downloaded app before touching the installed one.
  verify_app_trust "$src" || { warn "Скачанное приложение не прошло проверку подлинности; установка отменена."; return 1; }

  USE_SUDO=0
  [[ -w /Applications ]] || USE_SUDO=1
  if [[ "$USE_SUDO" -eq 1 ]]; then
    have_tty || die "Для установки в /Applications нужен пароль администратора, но терминал недоступен."
    log "Для установки в /Applications нужен пароль администратора Mac."
    log "При вводе пароля символы не отображаются — это нормально."
    # shellcheck disable=SC2024 # the redirect is sudo's stdin on purpose
    sudo -v </dev/tty || { warn "Пароль администратора не принят."; return 1; }
  fi

  quit_app

  local ts old
  ts="$(date +%Y%m%d-%H%M%S)"
  old="${APP_PATH}.old.${ts}"

  if [[ -d "$APP_PATH" ]]; then
    run_root mv "$APP_PATH" "$old" || { warn "Не удалось отодвинуть старую копию."; return 1; }
  fi

  if ! run_root ditto "$src" "$APP_PATH"; then
    warn "ditto не смог установить приложение; восстанавливаю старую копию."
    if [[ -d "$old" ]]; then run_root rm -rf "$APP_PATH" 2>/dev/null || true; run_root mv "$old" "$APP_PATH" 2>/dev/null || true; fi
    return 1
  fi

  if ! verify_app_trust "$APP_PATH"; then
    warn "Установленная копия не прошла проверку подлинности; откатываю."
    run_root rm -rf "$APP_PATH" 2>/dev/null || true
    if [[ -d "$old" ]]; then run_root mv "$old" "$APP_PATH" 2>/dev/null || true; fi
    return 1
  fi

  # Signed by Anthropic and notarized (checked above): skip the first-launch
  # quarantine prompt.
  run_root xattr -dr com.apple.quarantine "$APP_PATH" >/dev/null 2>&1 || true

  if [[ -d "$old" ]]; then
    run_root rm -rf "$old" >/dev/null 2>&1 || true
  fi
  log "Claude Desktop установлен: $(app_version)."
  return 0
}

install_from_artifact() {
  local artifact="$1" installed="$2"
  local clean="${ARTIFACT_URL%%\?*}"
  local src=""

  case "$clean" in
    *.zip)
      local dir="$TMP_DIR/extract"
      mkdir -p "$dir"
      if ! ditto -x -k "$artifact" "$dir" >/dev/null 2>&1; then
        warn "Не удалось распаковать ZIP."
        return 1
      fi
      src="$(find "$dir" -type d -name "Claude.app" 2>/dev/null | head -1 || true)"
      ;;
    *.dmg)
      local mnt="$TMP_DIR/mnt"
      mkdir -p "$mnt"
      MOUNT_DIR="$mnt"
      hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$artifact" >/dev/null 2>&1 \
        || { warn "Не удалось смонтировать DMG."; return 1; }
      src="$(find "$mnt" -maxdepth 1 -type d -name '*.app' 2>/dev/null | head -1 || true)"
      if [[ -z "$src" ]]; then
        src="$(find "$mnt" -type d -name "Claude.app" 2>/dev/null | head -1 || true)"
      fi
      ;;
    *)
      warn "Неподдерживаемый формат артефакта: $ARTIFACT_URL"
      return 1
      ;;
  esac

  [[ -n "$src" ]] || { warn "В артефакте не найден Claude.app."; return 1; }
  install_app_from_src "$src" "$installed"
}

install_or_update_app() {
  if [[ "$DO_INSTALL" -eq 0 && "$DO_UPDATE" -eq 0 ]]; then
    return 0
  fi

  local installed=0
  app_installed && installed=1

  if [[ "$installed" -eq 1 && "$DO_UPDATE" -eq 0 ]]; then
    log "Claude Desktop $(app_version) установлен; обновление отключено."
    return 0
  fi

  if ! load_artifact_info; then
    if [[ "$installed" -eq 1 ]]; then
      warn "Не удалось проверить обновление; продолжаю с установленной версией."
      return 0
    fi
    die "Не удалось получить информацию об установщике. Укажи --dmg-url (DMG или ZIP)."
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$installed" -eq 1 ]]; then
      if [[ -n "$ARTIFACT_VERSION" ]] && version_gt "$ARTIFACT_VERSION" "$(app_version)"; then
        log "DRY-RUN: обновил бы $(app_version) -> $ARTIFACT_VERSION из $ARTIFACT_URL."
      else
        log "DRY-RUN: установлено $(app_version); официальный cask ${ARTIFACT_VERSION:-unknown} не новее — обновление не требуется."
      fi
    else
      log "DRY-RUN: установил бы Claude Desktop ${ARTIFACT_VERSION:-unknown} из $ARTIFACT_URL."
    fi
    return 0
  fi

  if [[ "$installed" -eq 1 ]]; then
    local cur
    cur="$(app_version)"
    if [[ -n "$ARTIFACT_VERSION" ]] && ! version_gt "$ARTIFACT_VERSION" "$cur"; then
      log "Установлено $cur, официальный cask $ARTIFACT_VERSION — обновление не требуется."
      return 0
    fi
    log "Обновляю Claude Desktop: $cur -> ${ARTIFACT_VERSION:-из артефакта}"
  else
    log "Устанавливаю Claude Desktop ${ARTIFACT_VERSION:-из артефакта}."
  fi

  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-cpa-artifact.XXXXXX")"
  local clean="${ARTIFACT_URL%%\?*}"
  local ext="bin"
  case "$clean" in *.zip) ext="zip" ;; *.dmg) ext="dmg" ;; esac
  local artifact="$TMP_DIR/Claude.${ext}"

  log "Скачиваю Claude Desktop: $ARTIFACT_URL"
  if ! curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -o "$artifact" "$ARTIFACT_URL"; then
    warn "Не удалось скачать артефакт: $ARTIFACT_URL"
    rm -rf "$TMP_DIR"; TMP_DIR=""
    [[ "$installed" -eq 1 ]] || die "Приложение не установлено, а установщик скачать не удалось."
    return 0
  fi

  if [[ -n "$ARTIFACT_SHA256" ]]; then
    local actual
    actual="$(shasum -a 256 "$artifact" | awk '{print $1}')"
    if [[ "$actual" != "$ARTIFACT_SHA256" ]]; then
      warn "SHA256 артефакта не совпал; установка отменена."
      rm -rf "$TMP_DIR"; TMP_DIR=""
      [[ "$installed" -eq 1 ]] || die "Проверка SHA256 не прошла."
      return 0
    fi
  fi

  if install_from_artifact "$artifact" "$installed"; then
    :
  else
    [[ "$installed" -eq 1 ]] || die "Не удалось установить Claude Desktop."
    warn "Обновление не применилось; продолжаю с установленной версией."
  fi

  if [[ -n "${MOUNT_DIR:-}" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    MOUNT_DIR=""
  fi
  rm -rf "$TMP_DIR"; TMP_DIR=""
}

# All key_from_* helpers print a key only when its settings already point at
# the CPA host ($1). Keys for other services are never returned, so they are
# never sent to CPA for validation.

# Prints the current CPA key from the applied Claude-3p profile, if present.
key_from_profile() {
  python3 - "$SUPPORT_DIR" "$1" <<'PY' 2>/dev/null || true
import json, os, sys
from urllib.parse import urlsplit
base, want = sys.argv[1], sys.argv[2].lower()
meta_path = os.path.join(base, "configLibrary", "_meta.json")
try:
    meta = json.load(open(meta_path))
except Exception:
    sys.exit(0)
applied = meta.get("appliedId")
if not applied:
    sys.exit(0)
path = os.path.join(base, "configLibrary", applied + ".json")
try:
    p = json.load(open(path))
except Exception:
    sys.exit(0)
if (urlsplit(p.get("inferenceGatewayBaseUrl") or "").hostname or "").lower() != want:
    sys.exit(0)
key = p.get("inferenceGatewayApiKey")
# After the first launch Claude Desktop imports the gateway key into the
# macOS Keychain and replaces the profile value with an opaque keychain
# reference (long token). Only short/direct keys can be validated against CPA.
if isinstance(key, str) and key.strip() and len(key.strip()) <= 100:
    print(key.strip())
PY
}

key_from_claude_settings() {
  python3 - "$HOME/.claude/settings.json" "$1" <<'PY' 2>/dev/null || true
import json, sys
from urllib.parse import urlsplit
want = sys.argv[2].lower()
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
env = d.get("env") or {}
if not isinstance(env, dict):
    sys.exit(0)
if (urlsplit(env.get("ANTHROPIC_BASE_URL") or "").hostname or "").lower() != want:
    sys.exit(0)
for k in ("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"):
    v = env.get(k)
    if isinstance(v, str) and v.strip():
        print(v.strip())
        sys.exit(0)
PY
}

key_from_codex() {
  python3 - "$HOME/.codex/config.toml" "$1" <<'PY' 2>/dev/null || true
# Minimal line-based reader (system python3 may be older than 3.11, so
# tomllib is not guaranteed). A key is taken only from a provider whose
# base_url points at the CPA host; [model_providers.X.http_headers]
# sub-tables belong to provider X.
import re, sys
from urllib.parse import urlsplit
want = sys.argv[2].lower()
try:
    lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
except Exception:
    sys.exit(0)
groups = {}
group = ""
key_res = [
    re.compile(r'^\s*experimental_bearer_token\s*=\s*"([^"]+)"'),
    re.compile(r'"?X-Api-Key"?\s*=\s*"([^"]+)"', re.I),
    re.compile(r'^\s*api_key\s*=\s*"([^"]+)"'),
]
for line in lines:
    m = re.match(r'^\s*\[+\s*([^\]]+?)\s*\]+\s*$', line)
    if m:
        parts = [x.strip().strip('"') for x in m.group(1).split(".")]
        group = ".".join(parts[:2]) if parts[0] == "model_providers" else ".".join(parts)
        continue
    g = groups.setdefault(group, {"base": None, "keys": []})
    b = re.match(r'^\s*base_url\s*=\s*"([^"]+)"', line)
    if b:
        g["base"] = b.group(1)
        continue
    for r in key_res:
        k = r.search(line)
        if k:
            g["keys"].append(k.group(1).strip())
            break
for g in groups.values():
    if g["base"] and (urlsplit(g["base"]).hostname or "").lower() == want and g["keys"]:
        print(g["keys"][0])
        sys.exit(0)
PY
}

key_fingerprint() {
  printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,8)}'
}

validate_key() {
  local key="$1" hdr body code
  hdr="$(new_tmp_file)"
  body="$(new_tmp_file)"
  printf 'x-api-key: %s\n' "$key" > "$hdr"

  code="$(curl -sS --max-time 25 -o "$body" -w '%{http_code}' -H @"$hdr" "$BASE_URL/v1/models" 2>/dev/null || echo 000)"
  if [[ "$code" != "200" ]]; then
    warn "CPA /v1/models вернул HTTP $code — ключ не принят."
    return 1
  fi

  local model_info
  model_info="$(python3 - "$body" "$MODEL_SONNET" "$MODEL_OPUS" "$MODEL_HAIKU" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
ids = {m.get("id") for m in (d.get("data") or []) if isinstance(m, dict)}
targets = sys.argv[2:5]
print("models=%d; %s" % (len(ids), "; ".join("%s=%s" % (t, "yes" if t in ids else "no") for t in targets)))
PY
)"
  [[ -n "$model_info" ]] && log "  $model_info"

  local req
  req="$(new_tmp_file)"
  cat > "$req" <<JSON
{"model":"$MODEL_HAIKU","max_tokens":8,"messages":[{"role":"user","content":"ping"}]}
JSON
  code="$(curl -sS --max-time 40 -o "$body" -w '%{http_code}' \
    -X POST "$BASE_URL/v1/messages" \
    -H @"$hdr" \
    -H 'anthropic-version: 2023-06-01' \
    -H 'content-type: application/json' \
    --data-binary @"$req" 2>/dev/null || echo 000)"

  if [[ "$code" == "200" ]]; then
    if python3 - "$body" <<'PY' >/dev/null 2>&1
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("type") == "message" else 1)
PY
    then
      log "  Claude-модель $MODEL_HAIKU: OK"
      return 0
    fi
    warn "Ответ /v1/messages не похож на Anthropic message."
    return 1
  fi

  if [[ "$code" == "429" || "$code" =~ ^5 ]]; then
    warn "Claude-модель вернула HTTP $code (временная ошибка/лимит); конфиг можно записать, но проверь позже."
    return 0
  fi

  warn "Ключ принят для /v1/models, но Claude-модель вернула HTTP $code."
  warn "Проверь, что native Claude добавлен этому ключу в CPA."
  return 1
}

# Asks for a key on the terminal (up to 3 attempts); dies when none works.
prompt_key() {
  have_tty || die "Нет терминала для ввода ключа. Передай --key или CPA_API_KEY."
  local _
  for _ in 1 2 3; do
    read_secret 'CPA API key: ' KEY || die "Нет терминала для ввода ключа. Передай --key или CPA_API_KEY."
    [[ -n "$KEY" ]] || continue
    if validate_key "$KEY"; then
      KEY_SOURCE="interactive"
      log "Использую CPA-ключ (fingerprint $(key_fingerprint "$KEY"))."
      return 0
    fi
    warn "Ключ не прошёл проверку. Попробуй ещё раз."
  done
  die "Не удалось получить рабочий CPA-ключ."
}

resolve_key() {
  local -a keys=()
  local -a sources=()
  local k src

  add_candidate() {
    local v="$1" s="$2" i
    [[ -n "$v" ]] || return 0
    for i in "${!keys[@]}"; do
      [[ "${keys[$i]}" == "$v" ]] && return 0
    done
    keys+=("$v")
    sources+=("$s")
  }

  # An explicitly supplied key is authoritative: never silently fall back to
  # another key when the user passed one and it was rejected.
  if [[ -n "$KEY" ]]; then
    log "Проверяю ключ из --key..."
    if validate_key "$KEY"; then
      KEY_SOURCE="--key"
      log "Использую CPA-ключ из --key (fingerprint $(key_fingerprint "$KEY"))."
      return 0
    fi
    if [[ "$CHECK" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
      warn "Ключ из --key не прошёл проверку."
      return 1
    fi
    [[ "$FORCE" -eq 1 ]] || die "Ключ из --key не прошёл проверку."
    KEY_SOURCE="--key"
    warn "Записываю конфиг с ключом из --key несмотря на ошибку проверки (--force)."
    return 0
  fi
  if [[ -n "${CPA_API_KEY:-}" ]]; then
    log "Проверяю ключ из CPA_API_KEY..."
    if validate_key "$CPA_API_KEY"; then
      KEY="$CPA_API_KEY"
      KEY_SOURCE="CPA_API_KEY"
      log "Использую CPA-ключ из CPA_API_KEY (fingerprint $(key_fingerprint "$KEY"))."
      return 0
    fi
    if [[ "$CHECK" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
      warn "Ключ из CPA_API_KEY не прошёл проверку."
      return 1
    fi
    [[ "$FORCE" -eq 1 ]] || die "Ключ из CPA_API_KEY не прошёл проверку."
    KEY="$CPA_API_KEY"
    KEY_SOURCE="CPA_API_KEY"
    warn "Записываю конфиг с ключом из CPA_API_KEY несмотря на ошибку проверки (--force)."
    return 0
  fi

  # --ask-key: the user wants to enter a new key (the stored one may be
  # revoked or replaced), so saved keys are not even looked at.
  if [[ "$ASK_KEY" -eq 1 && "$CHECK" -eq 0 && "$DRY_RUN" -eq 0 ]]; then
    [[ "$ASSUME_YES" -eq 1 ]] && die "--ask-key требует ввода ключа, а --yes запрещает вопросы."
    log "Введите новый CPA-ключ."
    prompt_key
    return 0
  fi

  local host
  host="$(url_host "$BASE_URL")"
  k="$(key_from_profile "$host")";         [[ -n "$k" ]] && add_candidate "$k" "Claude-3p profile"
  k="$(key_from_claude_settings "$host")"; [[ -n "$k" ]] && add_candidate "$k" "Claude CLI settings"
  k="$(key_from_codex "$host")";           [[ -n "$k" ]] && add_candidate "$k" "Codex config"

  if [[ ${#keys[@]} -eq 0 ]]; then
    if [[ "$CHECK" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
      warn "CPA-ключ не найден."
      return 1
    fi
    [[ "$ASSUME_YES" -eq 1 ]] && die "CPA-ключ не найден, а --yes запрещает вопросы. Передай --key или CPA_API_KEY."
    have_tty || die "CPA-ключ не найден. Передай --key или CPA_API_KEY."
    prompt_key
    return 0
  fi

  local i
  for i in "${!keys[@]}"; do
    k="${keys[$i]}"
    src="${sources[$i]}"
    if [[ "$CHECK" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
      log "Проверяю ключ из $src (fingerprint $(key_fingerprint "$k"))..."
    else
      log "Проверяю ключ из $src..."
    fi
    if validate_key "$k"; then
      KEY="$k"
      KEY_SOURCE="$src"
      log "Использую CPA-ключ из $src (fingerprint $(key_fingerprint "$KEY"))."
      return 0
    fi
  done

  if [[ "$CHECK" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
    warn "Ни один найденный ключ не прошёл проверку."
    return 1
  fi

  # A stored key that no longer works was most likely revoked or replaced:
  # ask for the new one instead of failing.
  if [[ "$ASSUME_YES" -eq 0 ]] && have_tty; then
    warn "Сохранённый CPA-ключ не подошёл (возможно, его заменили или отозвали)."
    prompt_key
    return 0
  fi
  [[ "$FORCE" -eq 1 ]] || die "Ни один CPA-ключ не прошёл проверку. Передай новый ключ через CPA_API_KEY или запусти в Терминале с --ask-key."
  KEY="${keys[0]}"
  KEY_SOURCE="${sources[0]}"
  warn "Записываю конфиг с ключом из $KEY_SOURCE несмотря на ошибку проверки (--force)."
}

list_models() {
  resolve_key || die "Не удалось получить рабочий CPA-ключ."
  local hdr body code
  hdr="$(new_tmp_file)"
  body="$(new_tmp_file)"
  printf 'x-api-key: %s\n' "$KEY" > "$hdr"
  code="$(curl -sS --max-time 30 -o "$body" -w '%{http_code}' -H @"$hdr" "$BASE_URL/v1/models" 2>/dev/null || echo 000)"
  [[ "$code" == "200" ]] || die "CPA /v1/models вернул HTTP $code"
  python3 - "$body" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit("не удалось разобрать ответ /v1/models")
ids = sorted({m.get("id") for m in (data.get("data") or []) if isinstance(m, dict) and m.get("id")})
claude = [i for i in ids if i.lower().startswith("claude")]
other = [i for i in ids if i not in claude]
print("Модели Claude, доступные ключу CPA:")
for i in claude:
    print("  " + i)
print()
print("Прочие модели: %d. Через CPA они возможны, но в Claude Desktop" % len(other))
print("не тестировались: приложение отправляет Anthropic-формат запросов.")
print()
print("Пример: claude-desktop-cpa --add-model 'claude-opus-4-8=Opus 4.8' --configure-only")
PY
}

inspect_config() {
  python3 - "$SUPPORT_DIR" "$BASE_URL" <<'PY'
import hashlib, json, os, sys
base, want_base = sys.argv[1], sys.argv[2].rstrip("/")
meta_path = os.path.join(base, "configLibrary", "_meta.json")
desktop_path = os.path.join(base, "claude_desktop_config.json")
print("support_dir:", base)
try:
    meta = json.load(open(meta_path))
except Exception:
    meta = {}
print("applied_id:", meta.get("appliedId") or "(none)")
profile_path = None
applied = meta.get("appliedId")
if applied:
    profile_path = os.path.join(base, "configLibrary", applied + ".json")
profile = {}
if profile_path:
    try:
        profile = json.load(open(profile_path))
    except Exception:
        profile = {}
print("profile_path:", profile_path or "(none)")
print("provider:", profile.get("inferenceProvider") or "(none)")
print("base_url:", profile.get("inferenceGatewayBaseUrl") or "(none)")
print("base_matches:", "yes" if (profile.get("inferenceGatewayBaseUrl") or "").rstrip("/") == want_base else "no")
key = profile.get("inferenceGatewayApiKey")
key_kind = "none"
if isinstance(key, str) and key:
    key_kind = "direct" if len(key) <= 100 else "keychain"
print("key_present:", "yes" if isinstance(key, str) and key else "no")
print("key_kind:", key_kind)
print("key_len:", len(key) if isinstance(key, str) else 0)
if isinstance(key, str) and key and key_kind == "direct":
    print("key_fingerprint:", hashlib.sha256(key.encode()).hexdigest()[:8])
models = profile.get("inferenceModels") or []
names = [m.get("name") for m in models if isinstance(m, dict) and m.get("name")]
print("models:", ", ".join(names) if names else "(none)")
print("auth_scheme:", profile.get("inferenceGatewayAuthScheme") or "(none)")
print("chat_tab_enabled:", profile.get("chatTabEnabled"))
try:
    desktop = json.load(open(desktop_path))
except Exception:
    desktop = {}
print("deploymentMode:", desktop.get("deploymentMode") or "(none)")
prefs = desktop.get("preferences") or {}
print("sidebarMode:", prefs.get("sidebarMode") or "(none)")
PY
}

write_config() {
  local keyfile
  keyfile="$(new_tmp_file)"
  printf '%s' "$KEY" > "$keyfile"

  python3 - "$SUPPORT_DIR" "$BASE_URL" "$WITH_CHAT" "$PROFILE_NAME" "$keyfile" "$MODELS_FILE" <<'PY'
import datetime, json, os, shutil, sys, uuid

support, base, with_chat_s, profile_name, keyfile, models_file = sys.argv[1:7]
base = base.rstrip("/")
with_chat = with_chat_s == "1"
key = open(keyfile, encoding="utf-8").read().strip()
if not key:
    raise SystemExit("empty key")

config_lib = os.path.join(support, "configLibrary")
os.makedirs(config_lib, mode=0o700, exist_ok=True)
os.chmod(support, 0o700)
os.chmod(config_lib, 0o700)

ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup_root = os.path.join(support, ".cpa-backups")
backup_dir = os.path.join(backup_root, ts)
os.makedirs(backup_root, mode=0o700, exist_ok=True)
os.chmod(backup_root, 0o700)
os.makedirs(backup_dir, mode=0o700)
os.chmod(backup_dir, 0o700)
for name in ("_meta.json",):
    p = os.path.join(config_lib, name)
    if os.path.exists(p):
        shutil.copy2(p, os.path.join(backup_dir, name))
dpath = os.path.join(support, "claude_desktop_config.json")
if os.path.exists(dpath):
    shutil.copy2(dpath, os.path.join(backup_dir, "claude_desktop_config.json"))

meta_path = os.path.join(config_lib, "_meta.json")
try:
    meta = json.load(open(meta_path, encoding="utf-8"))
except Exception:
    meta = {}
entries = meta.get("entries")
if not isinstance(entries, list):
    entries = []

def profile_path(uid):
    return os.path.join(config_lib, uid + ".json")

# Reuse an existing profile named CPA, else one already pointing at this base.
chosen = None
for e in entries:
    if isinstance(e, dict) and e.get("name") == profile_name and e.get("id"):
        chosen = e
        break
if chosen is None:
    for e in entries:
        if not isinstance(e, dict) or not e.get("id"):
            continue
        try:
            p = json.load(open(profile_path(e["id"]), encoding="utf-8"))
        except Exception:
            continue
        if (p.get("inferenceGatewayBaseUrl") or "").rstrip("/") == base:
            chosen = e
            if not e.get("name"):
                e["name"] = profile_name
            break
if chosen is None:
    chosen = {"id": str(uuid.uuid4()), "name": profile_name}
    entries.append(chosen)

uid = chosen["id"]
ppath = profile_path(uid)
if os.path.exists(ppath):
    shutil.copy2(ppath, os.path.join(backup_dir, uid + ".json"))
try:
    profile = json.load(open(ppath, encoding="utf-8"))
except Exception:
    profile = {}

models = [
    {"name": "claude-sonnet-5-5", "supports1m": False, "labelOverride": "Claude Sonnet 5.5", "anthropicFamilyTier": "sonnet"},
    {"name": "claude-opus-5-5", "supports1m": False, "labelOverride": "Claude Opus 5.5", "anthropicFamilyTier": "opus"},
    {"name": "claude-haiku-5-5", "supports1m": False, "labelOverride": "Claude Haiku 5.5", "anthropicFamilyTier": "haiku"},
]

# Extra models added through --add-model. Built-ins stay first, so Sonnet 5.5
# remains the default model; extras are appended in the order they were added.
try:
    extra_models = json.load(open(models_file, encoding="utf-8"))
except Exception:
    extra_models = []
if isinstance(extra_models, list):
    allowed = (
        "name", "labelOverride", "supports1m", "prefer1m",
        "anthropicFamilyTier", "isFamilyDefault", "behavesAs", "maxEffort",
    )
    seen = {m["name"] for m in models}
    for entry in extra_models:
        if not isinstance(entry, dict):
            continue
        name = entry.get("name")
        if not isinstance(name, str) or not name.strip() or name in seen:
            continue
        item = {k: entry[k] for k in allowed if k in entry}
        item["name"] = name
        item.setdefault("supports1m", False)
        if item.get("anthropicFamilyTier") not in ("sonnet", "opus", "haiku", "fable", "mythos"):
            low = name.lower()
            item["anthropicFamilyTier"] = next(
                (t for t in ("fable", "mythos", "opus", "haiku", "sonnet") if t in low),
                "sonnet",
            )
        models.append(item)
        seen.add(name)

profile.update({
    "coworkEgressAllowedHosts": ["*"],
    "inferenceProvider": "gateway",
    "inferenceGatewayBaseUrl": base,
    "inferenceGatewayApiKey": key,
    "inferenceGatewayAuthScheme": "x-api-key",
    "inferenceModels": models,
    "chatTabEnabled": bool(with_chat),
    "disableDeploymentModeChooser": True,
    "modelDiscoveryEnabled": False,
    "inferenceStreamIdleTimeoutSec": 1800,
})

meta["appliedId"] = uid
meta["entries"] = entries

def atomic_json(path, obj, mode=0o600):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)

atomic_json(ppath, profile)
atomic_json(meta_path, meta)

try:
    desktop = json.load(open(dpath, encoding="utf-8"))
except Exception:
    desktop = {}
desktop["deploymentMode"] = "3p"
prefs = desktop.get("preferences")
if not isinstance(prefs, dict):
    prefs = {}
# Keep the app's current Code UI choice ("code" or the newer "epitaxy");
# only seed a value when the app has none.
if prefs.get("sidebarMode") not in ("code", "epitaxy"):
    prefs["sidebarMode"] = "code"
desktop["preferences"] = prefs
atomic_json(dpath, desktop)

# Keep only the newest 5 config backups (they can contain old API keys).
backups = sorted(
    (os.path.join(backup_root, n) for n in os.listdir(backup_root) if os.path.isdir(os.path.join(backup_root, n))),
    reverse=True,
)
for old in backups[5:]:
    shutil.rmtree(old, ignore_errors=True)

print("profile:", ppath)
print("applied_id:", uid)
print("models:", ", ".join(m["name"] for m in models))
print("sidebarMode:", prefs.get("sidebarMode"))
print("chatTabEnabled:", "true" if with_chat else "false")
print("backup:", backup_dir)
PY
}

start_app() {
  log "Запускаю Claude..."
  open -a "$APP_NAME"
  local i
  for i in $(seq 1 40); do
    app_running && break
    sleep 0.5
  done
  app_running || die "Claude не запустился."
  log "Claude запущен. Жду инициализацию 3P..."
  local logf="$LOG_DIR/main.log"
  for i in $(seq 1 45); do
    if [[ -f "$logf" ]] && tail -200 "$logf" 2>/dev/null | grep -q "provider: 'gateway'"; then
      log "3P gateway активен."
      return 0
    fi
    sleep 1
  done
  warn "Claude запущен, но строка 'provider: gateway' пока не появилась. Первый запуск может скачивать runtime; проверь вкладку Code."
}

check_mode() {
  local check_ok=1
  log "== Claude Desktop =="
  if app_installed; then
    log "path: $APP_PATH"
    log "version: $(app_version)"
    log "bundle: $(app_bundle_id)"
    log "running: $(app_running && echo yes || echo no)"
    if verify_app_trust "$APP_PATH" 2>/dev/null; then
      log "signature: Anthropic ($APP_TEAM_ID), notarized"
    else
      warn "Приложение не прошло проверку подлинности (подпись Anthropic / нотаризация Apple)."
      check_ok=0
    fi
  else
    warn "Claude Desktop не установлен."
  fi
  if load_artifact_info; then
    log "official cask: ${ARTIFACT_VERSION:-unknown} ($ARTIFACT_URL)"
    if app_installed; then
      if [[ -n "$ARTIFACT_VERSION" ]] && version_gt "$ARTIFACT_VERSION" "$(app_version)"; then
        log "update available via cask: $(app_version) -> $ARTIFACT_VERSION"
      else
        log "installed is current or newer; Claude's own updater handles updates"
      fi
    fi
  else
    warn "Could not load official cask metadata."
  fi
  app_installed || check_ok=0

  log
  log "== CPA / 3P config =="
  local cfg
  cfg="$(inspect_config)"
  log "$cfg"
  if ! printf '%s\n' "$cfg" | grep -q "provider: gateway"; then check_ok=0; fi
  if ! printf '%s\n' "$cfg" | grep -q "base_matches: yes"; then check_ok=0; fi
  if ! printf '%s\n' "$cfg" | grep -q "models: .*$MODEL_SONNET"; then check_ok=0; fi
  log

  local key_kind
  key_kind="$(printf '%s\n' "$cfg" | awk -F': ' '/^key_kind:/{print $2}')"

  log "== Key validation =="
  if resolve_key; then
    log "key_source: $KEY_SOURCE"
    if [[ "$key_kind" == "keychain" ]]; then
      log "3P profile key is keychain-managed; the app uses the macOS Keychain. Direct validation skipped."
    elif [[ "$KEY_SOURCE" != "Claude-3p profile" ]]; then
      warn "Applied 3P profile has a direct key but a different valid key was found."
      warn "Run the script without --check to rewrite the profile with the valid key."
      check_ok=0
    fi
  else
    if [[ "$key_kind" == "keychain" ]]; then
      warn "3P profile key is keychain-managed; direct validation skipped."
      if tail -200 "$LOG_DIR/main.log" 2>/dev/null | grep -q "ConfigHealth.*healthy"; then
        log "App logs confirm gateway healthy."
      else
        warn "No gateway health line in recent app logs."
        check_ok=0
      fi
    else
      warn "Рабочий CPA-ключ не найден."
      check_ok=0
    fi
  fi

  log
  log "== Runtime logs =="
  local logf="$LOG_DIR/main.log"
  if [[ -f "$logf" ]]; then
    tail -200 "$logf" 2>/dev/null | grep -E "provider: 'gateway'|ConfigHealth|sidebar_mode|Binary preflight|Bundle verified" | tail -8 || true
  else
    log "no log file at $logf"
  fi

  if [[ "$check_ok" -eq 1 ]]; then
    log
    log "OK: Claude Desktop настроен на CPA. Для работы используй вкладку Code."
    exit 0
  fi
  log
  warn "Конфигурация неполная или ключ не прошёл проверку."
  exit 1
}

main() {
  parse_args "$@"
  require_env

  if [[ "$LIST_MODELS" -eq 1 ]]; then
    list_models
    exit 0
  fi

  if [[ "$DRY_RUN" -eq 0 && "$CHECK" -eq 0 ]]; then
    if [[ ${#ADD_MODELS[@]} -gt 0 ]]; then
      update_models_file add "${ADD_MODELS[@]}"
    fi
    if [[ ${#REMOVE_MODELS[@]} -gt 0 ]]; then
      update_models_file remove "${REMOVE_MODELS[@]}"
    fi
  fi

  if [[ "$CHECK" -eq 1 ]]; then
    check_mode
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: изменения не применяются."
    if app_installed; then
      log "app: $(app_version) at $APP_PATH"
    else
      log "app: not installed"
    fi
    if load_artifact_info; then
      log "official cask: ${ARTIFACT_VERSION:-unknown} ($ARTIFACT_URL)"
    else
      warn "Could not load official cask metadata."
    fi
    log "3P config: $SUPPORT_DIR"
    log "models: $MODEL_SONNET, $MODEL_OPUS, $MODEL_HAIKU"
    local extra
    extra="$(models_summary)"
    [[ -n "$extra" ]] && log "extra models: $extra"
    resolve_key || true
    log "Были бы записаны профиль CPA, _meta.json и deploymentMode=3p."
    log "Claude был бы перезапущен: $([[ "$DO_RESTART" -eq 1 ]] && echo yes || echo no)."
    exit 0
  fi

  install_or_update_app

  if [[ "$DO_CONFIGURE" -eq 1 ]] && ! app_installed; then
    die "Claude Desktop не установлен. Убери --configure-only или установи приложение."
  fi

  if [[ "$DO_CONFIGURE" -eq 1 ]]; then
    resolve_key
    KEY_SOURCE="${KEY_SOURCE:-unknown}"
    quit_app
    write_config
    if [[ "$DO_RESTART" -eq 1 ]]; then
      start_app
    else
      log "Конфиг записан. Claude не запускался (--no-restart)."
    fi
  fi

  log
  log "Готово."
  log "Claude Desktop: $(app_version 2>/dev/null || echo unknown)"
  log "3P профиль: $SUPPORT_DIR/configLibrary"
  log "Модели: $MODEL_SONNET, $MODEL_OPUS, $MODEL_HAIKU"
  local extra
  extra="$(models_summary)"
  [[ -n "$extra" ]] && log "Доп. модели: $extra"
  log "Открой вкладку Code. Chat по-прежнему требует claude.ai-аккаунт."
  log "Первый запуск Code может скачивать runtime — это не авторизация."
}

# Tests source the script with CPA_INSTALL_SOURCE_ONLY=1 to reach the helpers
# without running the installer. `curl | bash` never sets it.
if [[ "${CPA_INSTALL_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
