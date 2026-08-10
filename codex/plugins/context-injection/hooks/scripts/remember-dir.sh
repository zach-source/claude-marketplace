#!/usr/bin/env bash
set -euo pipefail

# Source common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-helpers.sh"

payload="$(cat)"
[[ "$(jq -r '.tool_name' <<<"$payload")" != Bash ]] && exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$payload")

# First, try to extract session ID if user runs 'status' command
if [[ "$cmd" == "status" ]] || [[ "$cmd" =~ ^[[:space:]]*status[[:space:]]*$ ]]; then
  # This is a status command, we'll try to capture the session ID from the output
  # The hook runs before the command, so we set a marker
  echo "CLAUDE_CAPTURE_SESSION=1" > "${HOME}/.claude/.session-capture"
fi

if [[ "$cmd" =~ ^[[:space:]]*cd[[:space:]]+([^;&|]+) ]]; then
  dest="${BASH_REMATCH[1]}"
  abs=$(realpath -m "$(eval echo "$dest")")
  
  # Get session ID from local UUID file
  # Find the git root directory, or use current directory if not in a git repo
  GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  
  # Get session ID from local UUID file in project root
  SESSION_FILE="$GIT_ROOT/.claude-uuid-session"
  
  # Check if session file exists, create with UUID if not
  if [[ ! -f "$SESSION_FILE" ]]; then
    # Generate a new UUID for this session
    if command -v uuidgen >/dev/null 2>&1; then
      SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
      # Fallback: use random hex string if uuidgen not available
      SESSION_ID=$(openssl rand -hex 16)
    fi
    echo "$SESSION_ID" > "$SESSION_FILE"
  else
    # Read existing session ID
    SESSION_ID=$(cat "$SESSION_FILE")
  fi
  
  # Validate session ID
  if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID="session-$(date '+%Y%m%d-%H%M%S')"
    echo "$SESSION_ID" > "$SESSION_FILE"
  fi
  
  # Get timestamp
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  
  # Create session-specific directory if it doesn't exist
  SESSION_DIR="${HOME}/.claude/sessions/$SESSION_ID"
  mkdir -p "$SESSION_DIR"
  
  # Write to session-specific file
  {
    printf '## Directory Change\n'
    printf '* **Time**: %s\n' "$TIMESTAMP"
    printf '* **Directory**: `%s`\n' "$abs"
    printf '* **Command**: `%s`\n' "$cmd"
    printf '\n'
  } >> "$SESSION_DIR/directory-history.md"
  
  # Also write current directory to standard locations for compatibility
  printf '* Current directory: %s\n' "$abs" \
    > "${XDG_CONFIG_HOME:-$HOME/.config}/claude/last-dir.md"
  printf '* Current directory: %s\n' "$abs" \
    > "${HOME}/.claude/last-dir.md"
  
  # Write session-aware current directory
  {
    printf '# Current Directory\n'
    printf '* **Session**: %s\n' "$SESSION_ID"
    printf '* **Time**: %s\n' "$TIMESTAMP"
    printf '* **Directory**: `%s`\n' "$abs"
  } > "${HOME}/.claude/current-dir.md"
fi