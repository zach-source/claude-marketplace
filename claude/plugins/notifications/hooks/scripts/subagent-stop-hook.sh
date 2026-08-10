#!/usr/bin/env bash
set -euo pipefail

# SubagentStop Hook - Notify when agents complete
# Supports: tmux window/status notification + desktop notification

# Source common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-helpers.sh"

# Check if notifications are enabled
[[ "${CLAUDE_HOOKS_NOTIFY_ENABLED:-true}" != "true" ]] && exit 0

# Read hook input
HOOK_INPUT=$(cat)

# Extract agent information
AGENT_NAME=$(echo "$HOOK_INPUT" | jq -r '.agent_name // "unknown"' 2>/dev/null || echo "unknown")
AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.subagent_type // "agent"' 2>/dev/null || echo "agent")
EXIT_STATUS=$(echo "$HOOK_INPUT" | jq -r '.exit_status // "completed"' 2>/dev/null || echo "completed")

# Get context
CWD=$(pwd)
CWD_BASENAME=$(basename "$CWD")

# Format notification
TITLE="🤖 Agent Completed: $CWD_BASENAME"
BODY="$AGENT_TYPE finished ($EXIT_STATUS)"

# ═══════════════════════════════════════════════════════════════════════
# TMUX Notification
# ═══════════════════════════════════════════════════════════════════════

MARKER="●"  # Character to add to window name when agent completes

if [[ -n "${TMUX:-}" ]]; then
  # Get current window info
  CURRENT_WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "")
  WINDOW_NAME=$(tmux display-message -p '#W' 2>/dev/null || echo "")

  # Display message in tmux status line
  tmux display-message "✅ $AGENT_TYPE completed" 2>/dev/null || true

  # Add marker to window name if not already present
  if [[ ! "$WINDOW_NAME" =~ "$MARKER"$ ]]; then
    # Store original name in window option for later restoration
    tmux set-option -w @claude_original_name "$WINDOW_NAME" 2>/dev/null || true

    # Add marker to window name
    tmux rename-window "${WINDOW_NAME}${MARKER}" 2>/dev/null || true

    # Set up hook to remove marker when window gains focus
    # The hook checks for the stored name and clears it
    # Note: Using escaped dollars to prevent shell expansion before tmux receives the command
    tmux set-hook -w pane-focus-in "run-shell 'NAME=\$(tmux show-option -wqv @claude_original_name); if [ -n \"\$NAME\" ]; then tmux rename-window \"\$NAME\"; tmux set-option -wu @claude_original_name; tmux set-hook -wu pane-focus-in; fi'" 2>/dev/null || true
  fi

  # Set window alert flag to draw attention
  tmux set-window-option -t "$CURRENT_WINDOW" window-status-style "fg=green,bold" 2>/dev/null || true

  # Reset style after 5 seconds (background)
  (sleep 5 && tmux set-window-option -t "$CURRENT_WINDOW" window-status-style "" 2>/dev/null) &

  # Also set the @claude_waiting option to 0 (agent done)
  tmux set-option -w @claude_waiting 0 2>/dev/null || true

  # Ring the bell to get attention
  tmux send-keys -t "$CURRENT_WINDOW" "" 2>/dev/null || true
  printf '\a'  # Terminal bell
fi

# ═══════════════════════════════════════════════════════════════════════
# Desktop Notification  
# ═══════════════════════════════════════════════════════════════════════

GROUP="${CWD}:claude-agent"

# macOS with terminal-notifier
if [[ "$(uname)" == "Darwin" ]] && command_exists terminal-notifier; then
  NOTIFIER_CMD=(terminal-notifier -message "$BODY" -title "$TITLE" -group "$GROUP" -sound "Glass")
  
  # If in tmux, add command to focus the window when clicked
  if [[ -n "${TMUX:-}" ]]; then
    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
    TMUX_WINDOW=$(tmux display-message -p '#I' 2>/dev/null || echo "")
    if [[ -n "$TMUX_SESSION" && -n "$TMUX_WINDOW" ]]; then
      NOTIFIER_CMD+=(-execute "tmux select-window -t ${TMUX_SESSION}:${TMUX_WINDOW}")
    fi
  fi
  
  # stdout too: terminal-notifier writes to it, and the harness parses hook
  # stdout as JSON.
  "${NOTIFIER_CMD[@]}" >/dev/null 2>&1 || true

# macOS fallback with osascript
elif [[ "$(uname)" == "Darwin" ]] && command_exists osascript; then
  osascript -e "display notification \"$BODY\" with title \"$TITLE\" sound name \"Glass\"" >/dev/null 2>&1 || true

# Linux with notify-send
elif command_exists notify-send; then
  notify-send -u low "$TITLE" "$BODY" >/dev/null 2>&1 || true
fi

# No output. "block" is the only valid decision on SubagentStop; "approve" is
# not in the schema and failed validation on every subagent completion.
# Omitting decision is how you allow the stop.
exit 0
