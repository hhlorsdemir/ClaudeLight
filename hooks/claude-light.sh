#!/bin/bash
# ClaudeLight state writer. Usage: claude-light.sh working|waiting|idle
# Reads the Claude Code hook JSON from stdin and writes a state file per session_id.
DIR="$HOME/.claude/claude-light/state"
mkdir -p "$DIR"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
[ -z "$SID" ] && SID="unknown"
case "$1" in
  idle) rm -f "$DIR/$SID" ;;
  working|waiting) printf '%s' "$1" > "$DIR/$SID" ;;
esac
exit 0
