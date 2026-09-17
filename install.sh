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
  jq --arg cmd "$cmd" '
    def ours($s): {"hooks":[{"type":"command","command":($cmd+" "+$s),"timeout":5}]};
    def strip: if . == null then [] else map(select((.hooks // []) | any(.command? // "" | test("claude-light\\.sh")) | not)) end;
    reduce ($ARGS.positional | _nwise(2)) as [$ev, $st] (.hooks = (.hooks // {});
      .hooks[$ev] = ((.hooks[$ev] | strip) + [ours($st)]))
  ' "$file.bak-claudelight" --args "$@" > "$file"
}

echo "==> Registering Claude Code hooks in $SETTINGS"
register_hooks "$SETTINGS" \
  SessionStart waiting UserPromptSubmit working PreToolUse working PostToolUse working \
  PermissionRequest waiting Notification waiting Stop waiting SessionEnd idle

CODEX_HOOKS="$HOME/.codex/hooks.json"
if command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ]; then
  echo "==> Codex CLI detected, registering hooks in $CODEX_HOOKS"
  register_hooks "$CODEX_HOOKS" \
    SessionStart waiting UserPromptSubmit working PreToolUse working PostToolUse working \
    PermissionRequest waiting Stop waiting SessionEnd idle
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
echo "New Claude Code (and Codex CLI) sessions are tracked automatically; sessions opened before install are not."
echo "Right-click the light for options. To remove: ./uninstall.sh"
