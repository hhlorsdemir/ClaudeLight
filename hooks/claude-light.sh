#!/bin/bash
# ClaudeLight state writer. Usage: claude-light.sh working|waiting|idle|codex
# Codex mode maps lifecycle events; legacy state arguments preserve Claude behavior.
set -u
DIR="${CLAUDELIGHT_STATE_DIR:-$HOME/.claude/claude-light/state}"
INPUT=$(cat)
# Parse JSON, never nested tool arguments or malformed payloads as session IDs.
SID=$(printf '%s' "$INPUT" | jq -er '.session_id // .thread_id // .["thread-id"] | select(type == "string" and length > 0)' 2>/dev/null) || exit 0
SID=$(printf '%s' "$SID" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')
STATE="${1:-}"
if [ "$STATE" = codex ]; then
  SID="codex-$SID"
  EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""')
  case "$EVENT" in
    SessionStart)
      SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // ""')
      if [ "$SOURCE" = compact ]; then STATE=working; else STATE=idle; fi ;;
    Stop|Interrupt|SessionEnd) STATE=idle ;;
    UserPromptSubmit|PostToolUse|PreCompact|PostCompact) STATE=working ;;
    PermissionRequest) STATE=waiting ;;
    PreToolUse)
      TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')
      case "$TOOL" in
        request_user_input|*/request_user_input|*.request_user_input|AskUserQuestion) STATE=waiting ;;
        *) STATE=working ;;
      esac ;;
    *) exit 0 ;;
  esac
fi
# Prefixing Codex IDs avoids collisions with Claude sessions; reject path-only IDs.
case "$SID" in .|..|.*) exit 0 ;; esac
case "$STATE" in
  idle) rm -f "$DIR/$SID" ;;
  working|waiting)
    mkdir -p "$DIR" || exit 0
    # Hidden temporary files are ignored by the app; rename publishes a complete state.
    TEMP=$(mktemp "$DIR/.state.XXXXXX") || exit 0
    printf '%s' "$STATE" > "$TEMP"
    mv -f "$TEMP" "$DIR/$SID" ;;
esac
exit 0
