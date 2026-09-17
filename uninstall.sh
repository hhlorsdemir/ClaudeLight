#!/bin/bash
# Removes ClaudeLight: app, hooks, login item, state files.
set -uo pipefail
APP="$HOME/Applications/ClaudeLight.app"
HOOK="$HOME/.claude/hooks/claude-light.sh"
SETTINGS="$HOME/.claude/settings.json"

pkill -x ClaudeLight 2>/dev/null || true
osascript -e 'tell application "System Events" to if exists login item "ClaudeLight" then delete login item "ClaudeLight"' >/dev/null 2>&1 || true
rm -rf "$APP" "$HOOK" "$HOME/.claude/claude-light"
defaults delete com.lafagency.claudelight >/dev/null 2>&1 || true

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  cp "$SETTINGS" "$SETTINGS.bak-claudelight-uninstall"
  jq '
    if .hooks == null then . else
      .hooks |= with_entries(
        .value |= map(select((.hooks // []) | any(.command? // "" | test("claude-light\\.sh")) | not))
        | select(.value | length > 0))
      | if .hooks == {} then del(.hooks) else . end
    end
  ' "$SETTINGS.bak-claudelight-uninstall" > "$SETTINGS"
  echo "Hooks removed from $SETTINGS (backup: $SETTINGS.bak-claudelight-uninstall)"
fi
echo "ClaudeLight removed."
