#!/usr/bin/env bash
# and-then-stop-hook.sh - Stop hook for the and-then task queue
# Detects task completion via <done/> tag and advances to the next task
# Handles both standard tasks and fork (parallel subagent) tasks

set -euo pipefail

# State file location
QUEUE_FILE=".claude/and-then-queue.local.md"

# Exit early if no queue is active
if [[ ! -f "$QUEUE_FILE" ]]; then
    exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || echo "")

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    echo "⚠️  And-then queue: No transcript found, allowing exit" >&2
    rm -f "$QUEUE_FILE"
    exit 0
fi

# Parse state file using Python (reliable YAML parsing)
STATE_JSON=$(python3 -c "
import yaml
import json
import sys

try:
    with open('$QUEUE_FILE', 'r') as f:
        content = f.read()

    # Extract YAML frontmatter between --- markers
    parts = content.split('---')
    if len(parts) < 2:
        print(json.dumps({'error': 'Invalid state file format'}))
        sys.exit(0)

    data = yaml.safe_load(parts[1])
    if data is None:
        print(json.dumps({'error': 'Empty YAML'}))
        sys.exit(0)

    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo '{"error": "Python parsing failed"}')

# Check for parsing errors
if echo "$STATE_JSON" | jq -e '.error' >/dev/null 2>&1; then
    ERROR=$(echo "$STATE_JSON" | jq -r '.error')
    echo "⚠️  And-then queue: State file error: $ERROR" >&2
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

# Extract last assistant message from transcript
# Transcript is JSONL format (one JSON object per line)
LAST_OUTPUT=$(tac "$TRANSCRIPT_PATH" 2>/dev/null | while read -r line; do
    ROLE=$(echo "$line" | jq -r '.role // empty' 2>/dev/null || echo "")
    if [[ "$ROLE" == "assistant" ]]; then
        # Extract text content from message
        echo "$line" | jq -r '
            .message.content[]? |
            select(.type == "text") |
            .text // empty
        ' 2>/dev/null | head -1
        break
    fi
done)

if [[ -z "$LAST_OUTPUT" ]]; then
    echo "⚠️  And-then queue: No assistant output found" >&2
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
        local subtasks
        subtasks=$(echo "$task_json" | jq -r '.subtasks | join("\n- ")')
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
    else
        echo "Unknown task type: $task_type"
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

    # Update state file with new index
    TEMP_FILE="${QUEUE_FILE}.tmp.$$"
    python3 -c "
import yaml

with open('$QUEUE_FILE', 'r') as f:
    content = f.read()

parts = content.split('---')
data = yaml.safe_load(parts[1])
data['current_index'] = $NEXT_INDEX

# Rebuild file
output = '---\n'
output += yaml.dump(data, default_flow_style=False, sort_keys=False)
output += '---\n'

with open('$TEMP_FILE', 'w') as f:
    f.write(output)
"
    mv "$TEMP_FILE" "$QUEUE_FILE"

    # Build system message for next task
    if [[ "$NEXT_TYPE" == "fork" ]]; then
        SYSTEM_MSG="🔀 Task $((NEXT_INDEX + 1))/$TASK_COUNT [FORK] | Launch parallel subagents, then <done/> when all complete"
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
        SYSTEM_MSG="🔀 Task $((CURRENT_INDEX + 1))/$TASK_COUNT [FORK] | Launch parallel subagents, then <done/> when all complete"
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
