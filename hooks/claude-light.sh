#!/bin/bash
# ClaudeLight state writer. Usage: claude-light.sh working|waiting|idle
# Reads the hook JSON from stdin (Claude Code or Codex CLI) and writes a state file per session.
DIR="$HOME/.claude/claude-light/state"
mkdir -p "$DIR"
INPUT=$(cat)
# Claude Code sends "session_id"; Codex may send "session_id", "thread_id" or "thread-id".
SID=$(printf '%s' "$INPUT" | sed -n -E 's/.*"(session_id|thread_id|thread-id)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/p' | head -n1)
[ -z "$SID" ] && SID="unknown"
SID=$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_')
case "$1" in
  idle) rm -f "$DIR/$SID" ;;
  working|waiting) printf '%s' "$1" > "$DIR/$SID" ;;
esac
exit 0
