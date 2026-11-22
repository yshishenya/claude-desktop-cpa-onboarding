#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "$installer" ]] || fail "install.sh is not executable"
bash -n "$installer"

# --- help -----------------------------------------------------------------
help_text="$(bash "$installer" --help)"
for needle in --check --dry-run --configure-only --with-chat --with-main-models --claude-only --yes --ask-key --base-url --dmg-url --list-models --add-model --remove-model CPA_API_KEY "bash -s --"; do
  grep -q -- "$needle" <<<"$help_text" || fail "help does not mention $needle"
done

# --- static invariants ----------------------------------------------------
grep -q 'formulae.brew.sh/api/cask/claude.json' "$installer"
grep -q 'Claude-3p' "$installer"
grep -q 'inferenceProvider' "$installer"
grep -q 'deploymentMode' "$installer"
grep -q 'inferenceGatewayBaseUrl' "$installer"
grep -q 'MAIN_MODEL_SPECS' "$installer"
grep -q 'sonnet-4-argon-cpa' "$installer"
grep -q '^WITH_MAIN_MODELS=1$' "$installer" || fail "main models must be enabled by default"
python3 - "$repo_dir/scripts/sync-cpa-main-models.py" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
for alias in sonnet-4-5-cpa haiku-4-5-cpa opus-6-2-astra-cpa sonnet-6-2-sol-cpa haiku-6-luna-cpa sonnet-4-argon-cpa; do
  grep -q -- "$alias" "$installer" || fail "install.sh does not mention $alias"
  grep -q -- "$alias" "$repo_dir/scripts/sync-cpa-main-models.py" || fail "sync script does not mention $alias"
done
grep -q 'APP_TEAM_ID="Q6L2SF6YDW"' "$installer" || fail "Anthropic Team ID check is missing"
grep -q 'source=Notarized Developer ID' "$installer" || fail "notarization check is missing"

if grep -Eq 'sk-(clb|ant)-[A-Za-z0-9_-]{20,}' "$installer"; then
  fail "install.sh contains what looks like a hardcoded API key"
fi

# --- key discovery: only keys tied to the CPA host are used ---------------
fake_home="$(mktemp -d)"
mkdir -p "$fake_home/.claude" "$fake_home/.codex" \
  "$fake_home/Library/Application Support/Claude-3p/configLibrary"

# Never touch the real user's settings: every helper reads $HOME at call
# time, so HOME stays pointed at the fake directory for the whole test.
export HOME="$fake_home"
export CPA_INSTALL_SOURCE_ONLY=1
# shellcheck source=install.sh
source "$installer"
[[ "$HOME" == "$fake_home" ]] || fail "HOME is not isolated"
# The installer turns on errexit/ERR handling and its own EXIT trap; reset
# them for the test body.
set +eE
trap 'rm -rf "$fake_home"' EXIT

host="$(url_host "https://User@CPA.2brain.pro:443/v1/")"
[[ "$host" == "cpa.2brain.pro" ]] || fail "url_host returned '$host'"

expect() { # expect <description> <actual> <expected>
  # Values are never printed: a mistake here must not leak a real key.
  [[ "$2" == "$3" ]] || fail "$1: unexpected value (length ${#2}, expected length ${#3})"
}

# Claude Code settings pointing at Anthropic directly: must be ignored.
cat > "$fake_home/.claude/settings.json" <<'JSON'
{"env": {"ANTHROPIC_API_KEY": "direct-anthropic-key"}}
JSON
expect "claude settings without CPA base" "$(key_from_claude_settings "$host")" ""

cat > "$fake_home/.claude/settings.json" <<'JSON'
{"env": {"ANTHROPIC_BASE_URL": "https://api.anthropic.com", "ANTHROPIC_AUTH_TOKEN": "other-key"}}
JSON
expect "claude settings with other base" "$(key_from_claude_settings "$host")" ""

cat > "$fake_home/.claude/settings.json" <<'JSON'
{"env": {"ANTHROPIC_BASE_URL": "https://cpa.2brain.pro", "ANTHROPIC_AUTH_TOKEN": "cpa-key-from-claude"}}
JSON
expect "claude settings with CPA base" "$(key_from_claude_settings "$host")" "cpa-key-from-claude"

# Codex: an OpenAI key must not be picked up; the CPA provider's key must.
cat > "$fake_home/.codex/config.toml" <<'TOML'
api_key = "top-level-openai-key"

[model_providers.openai]
base_url = "https://api.openai.com/v1"
api_key = "openai-key"
TOML
expect "codex without CPA provider" "$(key_from_codex "$host")" ""

cat > "$fake_home/.codex/config.toml" <<'TOML'
[model_providers.openai]
base_url = "https://api.openai.com/v1"
api_key = "openai-key"

[model_providers.cpa]
name = "CPA"
base_url = "https://cpa.2brain.pro/v1"

[model_providers.cpa.http_headers]
"X-Api-Key" = "cpa-key-from-codex"
TOML
expect "codex with CPA provider (header table)" "$(key_from_codex "$host")" "cpa-key-from-codex"

cat > "$fake_home/.codex/config.toml" <<'TOML'
[model_providers.cpa]
base_url = "https://cpa.2brain.pro/v1"
experimental_bearer_token = "cpa-bearer"
TOML
expect "codex with CPA provider (bearer)" "$(key_from_codex "$host")" "cpa-bearer"

# Claude-3p profile pointing at a different gateway: must be ignored.
lib="$fake_home/Library/Application Support/Claude-3p/configLibrary"
echo '{"appliedId": "p1", "entries": [{"id": "p1", "name": "Other"}]}' > "$lib/_meta.json"
echo '{"inferenceGatewayBaseUrl": "https://gw.example.com", "inferenceGatewayApiKey": "gw-key"}' > "$lib/p1.json"
expect "profile with other gateway" "$(key_from_profile "$host")" ""
echo '{"inferenceGatewayBaseUrl": "https://cpa.2brain.pro", "inferenceGatewayApiKey": "cpa-key-from-profile"}' > "$lib/p1.json"
expect "profile with CPA gateway" "$(key_from_profile "$host")" "cpa-key-from-profile"

# --- key resolution without network ---------------------------------------
# validate_key and have_tty are stubbed so nothing is sent anywhere.
out="$( ( validate_key() { return 1; }; have_tty() { return 1; }
          ASK_KEY=1; ASSUME_YES=1; resolve_key ) 2>&1 )"
grep -q -- "--ask-key требует ввода ключа" <<<"$out" || fail "--ask-key with --yes must refuse to run"

out="$( ( validate_key() { return 1; }; have_tty() { return 1; }
          ASK_KEY=0; ASSUME_YES=0; FORCE=0; resolve_key ) 2>&1 )"
grep -q -- "--ask-key" <<<"$out" || fail "a rejected stored key must point the user to --ask-key"

out="$( ( validate_key() { [[ "$1" == "new-key" ]]; }; have_tty() { return 0; }
          read_secret() { printf -v "$2" '%s' "new-key"; }
          ASK_KEY=0; ASSUME_YES=0; FORCE=0; resolve_key >/dev/null 2>&1
          printf '%s|%s' "$KEY" "$KEY_SOURCE" ) 2>&1 )"
expect "rejected stored key falls back to a prompt" "$out" "new-key|interactive"

bash "$repo_dir/tests/test-models.sh"

# --- key input: paste artifacts are cleaned, rejections are explained ---------
[[ "$(clean_key $'\033[200~  sk-abc-123 \t\033[201~\r')" == "sk-abc-123" ]] \
  || fail "clean_key must strip paste markers, control characters and surrounding whitespace"
[[ "$(clean_key $'\n  sk-abc-123\n')" == "sk-abc-123" ]] \
  || fail "clean_key must trim a leading blank line, not only trailing whitespace"
[[ "$(clean_key $'\n\t \n')" == "" ]] || fail "clean_key of only whitespace must be empty"
[[ "$(clean_key 'sk-ab c')" == "sk-ab c" ]] || fail "clean_key must not touch the inside of a key"
[[ -z "$(clean_key '')" ]] || fail "clean_key of an empty value must stay empty"

out="$(describe_key 'sk-clb-abc' 2>&1)"
grep -q 'Введено символов: 10, отпечаток: [0-9a-f]\{8\}' <<<"$out" || fail "describe_key must report length and fingerprint"
if grep -q 'sk-clb-abc' <<<"$out"; then fail "describe_key must never print the key"; fi
out="$(describe_key $'sk-\xd1\x81lb-abc' 2>&1)"
grep -q 'не из латиницы' <<<"$out" || fail "describe_key must flag lookalike and invisible characters"
out="$(describe_key 'sk-clb abc' 2>&1)"
grep -q 'пробел' <<<"$out" || fail "describe_key must flag a space inside the key"

# --- README: the key check command works and keeps the key out of curl's arguments
check_cmd="$(python3 - "$repo_dir/README.md" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"```bash\n(printf 'Вставьте ключ.*?)\n```", text, re.S)
print(m.group(1) if m else "")
PY
)"
[[ -n "$check_cmd" ]] || fail "README must contain the key check command for macOS"
shim="$(mktemp -d)"
cat > "$shim/curl" <<'SH'
#!/bin/bash
# Stand-in for curl: the key must arrive on stdin (-H @-), never in the arguments.
cat > "$SHIM_HEADER"
case "$*" in *abc-test-key*) echo "key leaked into curl arguments" >&2; exit 9 ;; esac
echo "ответ сервера: HTTP 200"
SH
chmod +x "$shim/curl"
export SHIM_HEADER="$shim/header"
want_fp="$(printf %s abc-test-key | shasum -a 256 | cut -c1-8)"
# The command is pasted into the user's own shell: zsh is the default on current
# Macs, older accounts still use bash 3.2. Run it in every shell that is installed.
for sh_bin in /bin/bash bash zsh; do
  command -v "$sh_bin" >/dev/null 2>&1 || continue
  : > "$SHIM_HEADER"
  out="$(printf 'abc-test-key\n' | PATH="$shim:$PATH" "$sh_bin" -c "$check_cmd" 2>&1)" || fail "the key check command failed in $sh_bin: $out"
  grep -q "символов: 12" <<<"$out" || fail "key check must print the number of characters ($sh_bin)"
  grep -q "отпечаток: $want_fp" <<<"$out" || fail "key check must print the fingerprint ($sh_bin)"
  grep -q "ответ сервера: HTTP 200" <<<"$out" || fail "key check must print the server answer ($sh_bin)"
  if grep -q 'abc-test-key' <<<"$out"; then fail "key check must never print the key ($sh_bin)"; fi
  [[ "$(cat "$SHIM_HEADER")" == "x-api-key: abc-test-key" ]] || fail "key check must send the key as the x-api-key header on stdin ($sh_bin)"
done
rm -rf "$shim"

echo "static checks OK"
