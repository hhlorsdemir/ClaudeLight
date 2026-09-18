#!/bin/bash
# ClaudeLight installer
#   ./install.sh              build, install app, hooks, login item, launch
#   ./install.sh --no-login   skip the login item
set -euo pipefail
cd "$(dirname "$0")"

APP_DIR="$HOME/Applications"
APP="$APP_DIR/ClaudeLight.app"
HOOK_DIR="$HOME/.claude/hooks"
HOOK="$HOOK_DIR/claude-light.sh"
SETTINGS="$HOME/.claude/settings.json"
STATE_DIR="$HOME/.claude/claude-light/state"
LOGIN=1
[ "${1:-}" = "--no-login" ] && LOGIN=0

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1. $2"; exit 1; }; }
need jq "Install jq: brew install jq"

if command -v swiftc >/dev/null 2>&1; then
  echo "==> Building"
  ./build.sh >/dev/null
elif [ -d ClaudeLight.app ]; then
  echo "==> swiftc not found, using the prebuilt ClaudeLight.app"
  xattr -dr com.apple.quarantine ClaudeLight.app 2>/dev/null || true
else
  echo "Missing: swiftc. Install Xcode Command Line Tools: xcode-select --install"; exit 1
fi

echo "==> Installing app to $APP"
pkill -x ClaudeLight 2>/dev/null || true
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R ClaudeLight.app "$APP"

echo "==> Installing hook script to $HOOK"
mkdir -p "$HOOK_DIR" "$STATE_DIR"
cp hooks/claude-light.sh "$HOOK"
chmod +x "$HOOK"

# Merges our hook entries into a Claude-style hooks file ($1). Idempotent; other hooks untouched.
register_hooks() {
  local file="$1"; shift
  mkdir -p "$(dirname "$file")"
  [ -f "$file" ] || echo '{}' > "$file"
  cp "$file" "$file.bak-claudelight"
  local cmd='"$HOME/.claude/hooks/claude-light.sh"'
  local temp
  temp=$(mktemp "$file.tmp.XXXXXX")
  jq --arg cmd "$cmd" '
    def ours($s): {"hooks":[{"type":"command","command":($cmd+" "+$s),"timeout":3}]};
    def strip: (. // []) | map(.hooks = ((.hooks // []) | map(select((.command? // "" | test("claude-light\\.sh")) | not)))) | map(select(.hooks | length > 0));
    reduce ($ARGS.positional | _nwise(2)) as [$ev, $st] (.hooks = (.hooks // {});
      .hooks[$ev] = ((.hooks[$ev] | strip) + [ours($st)]))
  ' "$file.bak-claudelight" --args "$@" > "$temp" || { rm -f "$temp"; return 1; }
  mv "$temp" "$file"
}

echo "==> Registering Claude Code hooks in $SETTINGS"
register_hooks "$SETTINGS" \
  SessionStart waiting UserPromptSubmit working PreToolUse working PostToolUse working \
  PermissionRequest waiting Notification waiting Stop waiting SessionEnd idle

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
if command -v codex >/dev/null 2>&1 || [ -d "$CODEX_DIR" ]; then
  echo "==> Codex detected, registering hooks in $CODEX_HOOKS"
  register_hooks "$CODEX_HOOKS" \
    SessionStart codex UserPromptSubmit codex PreToolUse codex PostToolUse codex \
    PermissionRequest codex Stop codex Interrupt codex SessionEnd codex \
    PreCompact codex PostCompact codex
fi

if [ "$LOGIN" = 1 ]; then
  echo "==> Adding login item"
  osascript >/dev/null <<OSA
tell application "System Events"
  if exists login item "ClaudeLight" then delete login item "ClaudeLight"
  make login item at end with properties {path:"$APP", hidden:true}
end tell
OSA
fi

echo "==> Launching"
open "$APP"
echo
echo "Done. The light appears on the right edge of your screen."
echo "Start new Claude Code or Codex sessions to track them."
if [ -f "$CODEX_HOOKS" ]; then
  echo "Codex: review and trust the ClaudeLight hooks using /hooks before tracking sessions."
fi
echo "Right-click the light for options. To remove: ./uninstall.sh"
