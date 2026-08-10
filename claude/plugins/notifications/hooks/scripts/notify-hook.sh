#!/usr/bin/env bash
set -euo pipefail

# Source common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-helpers.sh"

# Get event type from argument or payload
event_type="${1:-notification}"

# Check if notifications are enabled
[[ "${CLAUDE_HOOKS_NOTIFY_ENABLED:-true}" != "true" ]] && exit 0

# Get context information
CWD=$(pwd)
CWD_BASENAME=$(basename "$CWD")
GROUP="${CWD}:claude"

# Determine notification message
# Note: Stop events don't have a message field, so we skip stdin read to avoid blocking
case "$event_type" in
  "stop")
    TITLE="Claude Code: $CWD_BASENAME"
    BODY="Task completed"
    ;;
  "notification"|*)
    # Only read stdin for events that actually use the message
    # Use timeout to prevent blocking if stdin doesn't close properly
    MESSAGE=$(timeout 1 cat 2>/dev/null | jq -r '.message // "Claude notification"' 2>/dev/null || echo "Claude notification")
    TITLE="Claude Code: $CWD_BASENAME"
    BODY="${MESSAGE}"
    ;;
esac

# For macOS, use terminal-notifier with Zellij integration
if [[ "$(uname)" == "Darwin" ]] && command -v terminal-notifier >/dev/null 2>&1; then
  # Build notification command
  NOTIFIER_CMD=(terminal-notifier -message "$BODY" -title "$TITLE" -group "$GROUP")

  # If running in Zellij, add command to focus the pane when clicked
  if [[ -n "${ZELLIJ:-}" ]] && [[ -n "${ZELLIJ_PANE_ID:-}" ]]; then
    # Focus the Zellij pane when notification is clicked
    NOTIFIER_CMD+=(-execute "zellij action focus-pane --pane-id $ZELLIJ_PANE_ID")

    # Also flash the tab to draw attention
    zellij action write 27 91 53 109 2>/dev/null || true  # Flash escape sequence
  fi

  # Send the notification
  "${NOTIFIER_CMD[@]}" 2>/dev/null || true

# Fallback to osascript for macOS without terminal-notifier
elif [[ "$(uname)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$BODY\" with title \"$TITLE\"" 2>/dev/null || true

# For Linux, use notify-send if available
elif command_exists notify-send; then
  notify-send "$TITLE" "$BODY" || true
fi

# Return JSON response with suppressOutput to avoid cluttering Claude's output
echo '{"decision": "approve", "reason": "Notification sent", "suppressOutput": true}'
exit 0