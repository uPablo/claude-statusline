#!/usr/bin/env bash
# Installer for claude-statusline — copies the script and prints the settings snippet.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/status-line.sh"
dest="$HOME/.claude/scripts/status-line.sh"

mkdir -p "$HOME/.claude/scripts"
cp "$src" "$dest"
chmod +x "$dest"

echo "✓ Installed to $dest"
echo ""
echo "Add this to ~/.claude/settings.json, then restart Claude Code:"
echo ""
cat <<'JSON'
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/scripts/status-line.sh",
    "refreshInterval": 10
  }
JSON
echo ""
command -v jq >/dev/null 2>&1 || echo "⚠ jq not found — required. Install with: brew install jq"
command -v ccusage >/dev/null 2>&1 || echo "ℹ ccusage not found — optional (burn rate + daily cost). Install with: npm i -g ccusage"
