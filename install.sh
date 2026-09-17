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
need swiftc "Install Xcode Command Line Tools: xcode-select --install"
need jq     "Install jq: brew install jq"

echo "==> Building"
./build.sh >/dev/null

echo "==> Installing app to $APP"
pkill -x ClaudeLight 2>/dev/null || true
mkdir -p "$APP_DIR"
rm -rf "$APP"
cp -R ClaudeLight.app "$APP"

echo "==> Installing hook script to $HOOK"
mkdir -p "$HOOK_DIR" "$STATE_DIR"
cp hooks/claude-light.sh "$HOOK"
chmod +x "$HOOK"

echo "==> Registering hooks in $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-claudelight"
CMD='"$HOME/.claude/hooks/claude-light.sh"'
jq --arg cmd "$CMD" '
  def ours($s): {"hooks":[{"type":"command","command":($cmd+" "+$s),"timeout":5}]};
  def strip: if . == null then [] else map(select((.hooks // []) | any(.command? // "" | test("claude-light\\.sh")) | not)) end;
  def add($ev; $s): .hooks[$ev] = ((.hooks[$ev] | strip) + [ours($s)]);
  .hooks = (.hooks // {})
  | add("SessionStart"; "waiting")
  | add("UserPromptSubmit"; "working")
  | add("PreToolUse"; "working")
  | add("PostToolUse"; "working")
  | add("PermissionRequest"; "waiting")
  | add("Notification"; "waiting")
  | add("Stop"; "waiting")
  | add("SessionEnd"; "idle")
' "$SETTINGS.bak-claudelight" > "$SETTINGS"

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
echo "New Claude Code sessions are tracked automatically; sessions opened before install are not."
echo "Right-click the light for options. To remove: ./uninstall.sh"
