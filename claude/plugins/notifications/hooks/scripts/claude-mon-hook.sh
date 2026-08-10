#!/bin/bash
# claude-mon PostToolUse hook
# Sends tool edits to both the TUI and daemon for real-time display and persistence

# Read the hook payload. This script used to take TOOL_INPUT and TOOL_NAME from
# the environment - a legacy env-var hook interface that no harness sets. Claude
# Code delivers the payload as JSON on stdin, so both were always empty: the TUI
# got blank lines and FILE_PATH never resolved, which meant the daemon branch
# never ran at all.
payload="$(cat)"

# tool_input is not guaranteed to be an object; keep a non-map from aborting the
# picks below.
TOOL_NAME=$(jq -r '.tool_name // "unknown"' <<<"$payload" 2>/dev/null || echo "unknown")
TOOL_INPUT=$(jq -c 'if (.tool_input | type) == "object" then .tool_input else {} end' <<<"$payload" 2>/dev/null || echo '{}')

# Session cwd from the payload; the hook process's own cwd is not authoritative
# and the TUI socket name is derived from this path.
CWD=$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || echo "")
[[ -z "$CWD" ]] && CWD="$(pwd)"

# Resolve symlinks (macOS compatible)
if command -v realpath &>/dev/null; then
    CWD="$(realpath "$CWD")"
elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS: use perl to resolve symlinks
    CWD="$(perl -MCwd -e 'print Cwd::realpath($ARGV[0])' "$CWD")"
else
    CWD="$(readlink -f "$CWD")"
fi

# Hash the path (matching Go's sha256.Sum256[:12])
HASH="$(echo -n "$CWD" | sha256sum | cut -c1-12)"

# Get username
USER="${USER:-unknown}"

# Socket paths
TUI_SOCKET="/tmp/claude-mon-${USER}-${HASH}.sock"
DAEMON_SOCKET="/tmp/claude-mon-daemon.sock"

# Send to TUI if socket exists (raw TOOL_INPUT)
if [[ -S "$TUI_SOCKET" ]]; then
    # nc's stdout is the hook's stdout, and PostToolUse stdout is parsed for hook
    # decisions - a daemon reply carrying a `decision` or `continue` key could
    # otherwise steer the session. Nothing this socket says is for Claude.
    echo "$TOOL_INPUT" | nc -U "$TUI_SOCKET" >/dev/null 2>&1 &
fi

# Send to daemon if socket exists (formatted payload)
if [[ -S "$DAEMON_SOCKET" ]] && command -v jq &>/dev/null; then
    # Parse tool input
    FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null)
    OLD_STRING=$(echo "$TOOL_INPUT" | jq -r '.old_string // empty' 2>/dev/null | head -c 10000)
    NEW_STRING=$(echo "$TOOL_INPUT" | jq -r '.new_string // .content // empty' 2>/dev/null | head -c 10000)

    if [[ -n "$FILE_PATH" ]]; then
        # Get git info
        # -C "$CWD": the payload names the workspace being reported on, which is
        # not necessarily where this hook process happens to be running.
        BRANCH=""
        COMMIT_SHA=""
        if git -C "$CWD" rev-parse --git-dir &>/dev/null; then
            BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
            COMMIT_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
        fi

        # Calculate line count
        LINE_COUNT=0
        if [[ -n "$NEW_STRING" ]]; then
            LINE_COUNT=$(echo "$NEW_STRING" | wc -l | tr -d ' ')
        fi

        # Create daemon payload
        PAYLOAD=$(jq -n \
            --arg type "edit" \
            --arg workspace "$CWD" \
            --arg workspace_name "$(basename "$CWD")" \
            --arg branch "$BRANCH" \
            --arg commit_sha "$COMMIT_SHA" \
            --arg tool_name "$TOOL_NAME" \
            --arg file_path "$FILE_PATH" \
            --arg old_string "$OLD_STRING" \
            --arg new_string "$NEW_STRING" \
            --argjson line_num 0 \
            --argjson line_count "$LINE_COUNT" \
            '{
                type: $type,
                workspace: $workspace,
                workspace_name: $workspace_name,
                branch: $branch,
                commit_sha: $commit_sha,
                tool_name: $tool_name,
                file_path: $file_path,
                old_string: $old_string,
                new_string: $new_string,
                line_num: $line_num,
                line_count: $line_count
            }')

        echo "$PAYLOAD" | nc -U "$DAEMON_SOCKET" >/dev/null 2>&1 &
    fi
fi
