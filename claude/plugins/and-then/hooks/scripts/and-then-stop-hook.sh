#!/usr/bin/env bash
# and-then-stop-hook.sh - Stop hook for the and-then task queue
# Detects task completion via <done/> tag and advances to the next task
# Handles both standard tasks and fork (parallel subagent) tasks

set -euo pipefail

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Get working directory from hook input (where Claude session is running)
SESSION_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Fallback to current directory if not provided
if [[ -z "$SESSION_CWD" ]]; then
    SESSION_CWD="$(pwd)"
fi

# State file location (JSON format, in session's working directory)
QUEUE_FILE="${SESSION_CWD}/.claude/and-then-queue.json"

# Exit early if no queue is active
if [[ ! -f "$QUEUE_FILE" ]]; then
    exit 0
fi

# Guard against looping: if we already blocked once and Claude is still trying to
# stop, let it. Without this, an unreadable completion signal re-feeds forever.
if [[ "$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" == "true" ]]; then
    exit 0
fi

# Parse state file (JSON format - no external dependencies)
STATE_JSON=$(cat "$QUEUE_FILE" 2>/dev/null || echo '{}')

# Validate JSON
if ! echo "$STATE_JSON" | jq -e '.' >/dev/null 2>&1; then
    echo "⚠️  And-then queue: Invalid JSON in state file" >&2
    rm -f "$QUEUE_FILE"
    exit 0
fi

# Extract state values
CURRENT_INDEX=$(echo "$STATE_JSON" | jq -r '.current_index // 0')
TASKS_JSON=$(echo "$STATE_JSON" | jq -c '.tasks // []')
TASK_COUNT=$(echo "$TASKS_JSON" | jq 'length')

# Validate we have tasks
if [[ "$TASK_COUNT" -eq 0 ]]; then
    echo "⚠️  And-then queue: No tasks in queue" >&2
    rm -f "$QUEUE_FILE"
    exit 0
fi

# Validate current_index is numeric
if ! [[ "$CURRENT_INDEX" =~ ^[0-9]+$ ]]; then
    echo "⚠️  And-then queue: Invalid current_index, resetting" >&2
    rm -f "$QUEUE_FILE"
    exit 0
fi

# Get current task info
CURRENT_TASK_JSON=$(echo "$TASKS_JSON" | jq -c ".[$CURRENT_INDEX] // {}")
TASK_TYPE=$(echo "$CURRENT_TASK_JSON" | jq -r '.type // "standard"')

# Final assistant text for this turn, straight off the Stop payload.
#
# This used to tac the transcript looking for a top-level `.role == "assistant"`.
# Two things wrong with that: Claude Code puts the role at `.message.role` and the
# entry kind at `.type`, so the match never fired and no task ever completed; and
# the transcript is written asynchronously, so at Stop time it may not contain the
# current turn yet - a race we would lose exactly when it matters. The docs say to
# use last_assistant_message on Stop/SubagentStop for precisely this reason.
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || echo "")

if [[ -z "$LAST_OUTPUT" ]]; then
    echo "⚠️  And-then queue: no last_assistant_message on the Stop payload" >&2
fi

# Check for completion signal: <done/> or <done></done>
TASK_COMPLETE=false
if [[ -n "$LAST_OUTPUT" ]]; then
    if echo "$LAST_OUTPUT" | grep -qE '<done\s*/>' 2>/dev/null || \
       echo "$LAST_OUTPUT" | grep -qE '<done>\s*</done>' 2>/dev/null; then
        TASK_COMPLETE=true
        echo "✅ And-then queue: Task $((CURRENT_INDEX + 1))/$TASK_COUNT complete" >&2
    fi
fi

# Function to build prompt for a task
build_task_prompt() {
    local task_json="$1"
    local task_type
    task_type=$(echo "$task_json" | jq -r '.type // "standard"')

    if [[ "$task_type" == "standard" ]]; then
        echo "$task_json" | jq -r '.prompt // "No task description"'
    elif [[ "$task_type" == "fork" ]]; then
        # Build a prompt that instructs Claude to launch parallel subagents
        local subtasks workers subtask_count
        subtasks=$(echo "$task_json" | jq -r '.subtasks | join("\n- ")')
        workers=$(echo "$task_json" | jq -r '.workers // 0')
        subtask_count=$(echo "$task_json" | jq '.subtasks | length')

        if [[ "$workers" -gt 0 ]] && [[ "$workers" -lt "$subtask_count" ]]; then
            cat << FORK_PROMPT
Launch the following tasks using the Task tool with LIMITED CONCURRENCY of $workers workers at a time.

Subtasks to run ($subtask_count total, $workers concurrent):
- $subtasks

IMPORTANT:
1. Launch up to $workers Task tool calls at a time (not all at once)
2. Wait for a batch to complete before starting the next batch
3. Choose appropriate subagent_type for each task (e.g., "general-purpose", "test-automator", etc.)
4. Summarize the results from each subagent as they complete
5. Output <done/> when ALL $subtask_count subtasks have completed successfully
FORK_PROMPT
        else
            cat << FORK_PROMPT
Launch the following tasks in PARALLEL using the Task tool. Each subtask should run as a separate subagent concurrently.

Subtasks to run in parallel:
- $subtasks

IMPORTANT:
1. Use MULTIPLE Task tool calls in a SINGLE message to run them concurrently
2. Choose appropriate subagent_type for each task (e.g., "general-purpose", "test-automator", etc.)
3. Wait for ALL subagents to complete
4. Summarize the results from each subagent
5. Output <done/> when ALL subtasks have completed successfully
FORK_PROMPT
        fi
    else
        echo "Unknown task type: $task_type"
    fi
}

# Function to build system message label for fork tasks
build_fork_label() {
    local task_json="$1"
    local workers
    workers=$(echo "$task_json" | jq -r '.workers // 0')
    if [[ "$workers" -gt 0 ]]; then
        echo "[FORK workers=$workers]"
    else
        echo "[FORK]"
    fi
}

# Determine next action
if [[ "$TASK_COMPLETE" == true ]]; then
    NEXT_INDEX=$((CURRENT_INDEX + 1))

    # Check if queue is exhausted
    if [[ $NEXT_INDEX -ge $TASK_COUNT ]]; then
        echo "🎉 And-then queue: All $TASK_COUNT tasks complete!" >&2
        rm -f "$QUEUE_FILE"
        exit 0  # Allow session exit
    fi

    # Get next task info
    NEXT_TASK_JSON=$(echo "$TASKS_JSON" | jq -c ".[$NEXT_INDEX] // {}")
    NEXT_TYPE=$(echo "$NEXT_TASK_JSON" | jq -r '.type // "standard"')
    NEXT_PROMPT=$(build_task_prompt "$NEXT_TASK_JSON")

    # Update state file with new index (using jq - no external deps)
    echo "$STATE_JSON" | jq ".current_index = $NEXT_INDEX" > "$QUEUE_FILE"

    # Build system message for next task
    if [[ "$NEXT_TYPE" == "fork" ]]; then
        FORK_LABEL=$(build_fork_label "$NEXT_TASK_JSON")
        SYSTEM_MSG="🔀 Task $((NEXT_INDEX + 1))/$TASK_COUNT $FORK_LABEL | Launch parallel subagents, then <done/> when all complete"
    else
        SYSTEM_MSG="📋 Task $((NEXT_INDEX + 1))/$TASK_COUNT | Output <done/> when complete"
    fi

    # Block exit and feed next task
    jq -n \
        --arg prompt "$NEXT_PROMPT" \
        --arg msg "$SYSTEM_MSG" \
        '{
            "decision": "block",
            "reason": $prompt,
            "systemMessage": $msg
        }'
else
    # Task not complete, re-feed current task
    CURRENT_PROMPT=$(build_task_prompt "$CURRENT_TASK_JSON")

    if [[ "$TASK_TYPE" == "fork" ]]; then
        FORK_LABEL=$(build_fork_label "$CURRENT_TASK_JSON")
        SYSTEM_MSG="🔀 Task $((CURRENT_INDEX + 1))/$TASK_COUNT $FORK_LABEL | Launch parallel subagents, then <done/> when all complete"
    else
        SYSTEM_MSG="📋 Task $((CURRENT_INDEX + 1))/$TASK_COUNT | Output <done/> when complete"
    fi

    jq -n \
        --arg prompt "$CURRENT_PROMPT" \
        --arg msg "$SYSTEM_MSG" \
        '{
            "decision": "block",
            "reason": $prompt,
            "systemMessage": $msg
        }'
fi
