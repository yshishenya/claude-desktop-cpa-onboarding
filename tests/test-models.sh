#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT

export HOME="$fake_home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME"

export CPA_INSTALL_SOURCE_ONLY=1
# shellcheck source=install.sh
source "$repo_dir/install.sh"
set +E

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$MODELS_FILE" == "$XDG_CONFIG_HOME/claude-desktop-cpa/models.json" ]] \
  || fail "unexpected models path: $MODELS_FILE"

# Claude Desktop silently drops names containing another vendor's keyword,
# so the installer must reject them instead of writing a dead entry.
if update_models_file add 'opencode-go/deepseek-v4-pro=DeepSeek V4 Pro' >/dev/null 2>&1; then
  fail "a non-Anthropic model ID must be rejected"
fi

update_models_file add \
  'claude-opus-4-8=Opus 4.8' \
  'acme-sonnet-cpa=Acme Sonnet' \
  'opencode-go/claude-sonnet-4-5-cpa=DeepSeek V4 Pro=claude-sonnet-5' >/dev/null

python3 - "$MODELS_FILE" <<'PY'
import json, sys
models = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(models) == 3, models
by_name = {m["name"]: m for m in models}
assert by_name["claude-opus-4-8"]["anthropicFamilyTier"] == "opus", by_name
assert by_name["claude-opus-4-8"]["labelOverride"] == "Opus 4.8", by_name
assert by_name["acme-sonnet-cpa"]["anthropicFamilyTier"] == "sonnet", by_name
assert by_name["acme-sonnet-cpa"]["labelOverride"] == "Acme Sonnet", by_name
deepseek = by_name["opencode-go/claude-sonnet-4-5-cpa"]
assert deepseek["labelOverride"] == "DeepSeek V4 Pro", deepseek
assert deepseek["behavesAs"] == "claude-sonnet-5", deepseek
assert deepseek["anthropicFamilyTier"] == "sonnet", deepseek
PY

# Adding the same ID updates it in place instead of creating a duplicate.
update_models_file add 'claude-opus-4-8=Opus 4.8 (CPA)' >/dev/null
python3 - "$MODELS_FILE" <<'PY'
import json, sys
models = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(models) == 3, models
entry = next(m for m in models if m["name"] == "claude-opus-4-8")
assert entry["labelOverride"] == "Opus 4.8 (CPA)", entry
PY

# The config writer keeps the built-in models first and appends extras.
KEY='test-key-not-valid'
BASE_URL='https://cpa.example.test'
WITH_CHAT=0
write_config >/dev/null

python3 - "$SUPPORT_DIR" <<'PY'
import json, os, sys
support = sys.argv[1]
meta = json.load(open(os.path.join(support, "configLibrary", "_meta.json"), encoding="utf-8"))
profile = json.load(open(os.path.join(support, "configLibrary", meta["appliedId"] + ".json"), encoding="utf-8"))
names = [m["name"] for m in profile["inferenceModels"]]
assert names[:3] == ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5"], names
assert names[3:] == [
    "claude-opus-4-8",
    "acme-sonnet-cpa",
    "opencode-go/claude-sonnet-4-5-cpa",
], names
assert profile["inferenceGatewayBaseUrl"] == "https://cpa.example.test", profile
assert profile["inferenceGatewayApiKey"] == "test-key-not-valid", profile
assert profile["inferenceGatewayAuthScheme"] == "x-api-key", profile
PY

update_models_file remove 'acme-sonnet-cpa' >/dev/null
python3 - "$MODELS_FILE" <<'PY'
import json, sys
models = json.load(open(sys.argv[1], encoding="utf-8"))
assert [m["name"] for m in models] == [
    "claude-opus-4-8",
    "opencode-go/claude-sonnet-4-5-cpa",
], models
PY

echo "model tests OK"
