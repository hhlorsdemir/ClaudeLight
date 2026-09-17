#!/bin/bash
# ClaudeLight durum yazıcı. Kullanım: claude-light.sh working|waiting|idle
# stdin'den Claude Code hook JSON'unu okur, session_id'ye göre durum dosyası yazar.
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
