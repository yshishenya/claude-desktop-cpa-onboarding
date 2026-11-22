#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="$repo_dir/install.sh"

[[ -x "$installer" ]] || { echo "install.sh is not executable" >&2; exit 1; }
bash -n "$installer"

help_text="$(bash "$installer" --help)"
for needle in --check --dry-run --configure-only --with-chat CPA_API_KEY; do
  grep -q -- "$needle" <<<"$help_text" || {
    echo "help does not mention $needle" >&2
    exit 1
  }
done

grep -q 'formulae.brew.sh/api/cask/claude.json' "$installer"
grep -q 'Claude-3p' "$installer"
grep -q 'inferenceProvider' "$installer"
grep -q 'deploymentMode' "$installer"
grep -q 'inferenceGatewayBaseUrl' "$installer"

if grep -Eq 'sk-(clb|ant)-[A-Za-z0-9_-]{20,}' "$installer"; then
  echo "install.sh contains what looks like a hardcoded API key" >&2
  exit 1
fi

echo "static checks OK"
