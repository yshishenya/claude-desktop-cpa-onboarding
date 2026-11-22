#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "$installer" ]] || fail "install.sh is not executable"
bash -n "$installer"

# --- help -----------------------------------------------------------------
help_text="$(bash "$installer" --help)"
for needle in --check --dry-run --configure-only --with-chat --yes --base-url --dmg-url CPA_API_KEY "bash -s --"; do
  grep -q -- "$needle" <<<"$help_text" || fail "help does not mention $needle"
done

# --- static invariants ----------------------------------------------------
grep -q 'formulae.brew.sh/api/cask/claude.json' "$installer"
grep -q 'Claude-3p' "$installer"
grep -q 'inferenceProvider' "$installer"
grep -q 'deploymentMode' "$installer"
grep -q 'inferenceGatewayBaseUrl' "$installer"
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

echo "static checks OK"
