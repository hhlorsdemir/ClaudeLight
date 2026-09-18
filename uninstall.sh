#!/bin/bash
# Removes ClaudeLight: app, hooks, login item, state files.
set -uo pipefail
APP="$HOME/Applications/ClaudeLight.app"
HOOK="$HOME/.claude/hooks/claude-light.sh"

pkill -x ClaudeLight 2>/dev/null || true
osascript -e 'tell application "System Events" to if exists login item "ClaudeLight" then delete login item "ClaudeLight"' >/dev/null 2>&1 || true
rm -rf "$APP" "$HOOK" "$HOME/.claude/claude-light"
defaults delete com.lafagency.claudelight >/dev/null 2>&1 || true

strip_hooks() {
  local file="$1"
  { [ -f "$file" ] && command -v jq >/dev/null; } || return 0
  cp "$file" "$file.bak-claudelight-uninstall"
  jq '
    if .hooks == null then . else
      .hooks |= with_entries(
        .value |= (map(.hooks = ((.hooks // []) | map(select((.command? // "" | test("claude-light\\.sh")) | not)))) | map(select(.hooks | length > 0)))
        | select(.value | length > 0))
      | if .hooks == {} then del(.hooks) else . end
    end
  ' "$file.bak-claudelight-uninstall" > "$file"
  echo "Hooks removed from $file (backup: $file.bak-claudelight-uninstall)"
}
strip_hooks "$HOME/.claude/settings.json"
strip_hooks "${CODEX_HOME:-$HOME/.codex}/hooks.json"
echo "ClaudeLight removed."
