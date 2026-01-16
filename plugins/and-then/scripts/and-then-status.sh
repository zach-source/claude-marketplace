#!/usr/bin/env bash
# and-then-status.sh - Show current queue status

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# State file location (JSON format - no external dependencies)
QUEUE_FILE=".claude/and-then-queue.json"

if [[ ! -f "$QUEUE_FILE" ]]; then
    echo -e "${YELLOW}ℹ️  No active and-then queue${NC}"
    exit 0
fi

# Parse state file (JSON format)
STATE_JSON=$(cat "$QUEUE_FILE")

# Validate JSON
if ! echo "$STATE_JSON" | jq -e '.' >/dev/null 2>&1; then
    echo -e "${RED}Error: Invalid JSON in state file${NC}" >&2
    exit 1
fi

# Extract state values
CURRENT_INDEX=$(echo "$STATE_JSON" | jq -r '.current_index // 0')
TASK_COUNT=$(echo "$STATE_JSON" | jq '.tasks | length')
STARTED_AT=$(echo "$STATE_JSON" | jq -r '.started_at // "unknown"')

echo -e "${BLUE}📋 And-Then Queue Status${NC}"
echo -e "   Started: ${STARTED_AT}"
echo -e "   Progress: $((CURRENT_INDEX + 1))/${TASK_COUNT} tasks"
echo ""

# Display each task
for ((i=0; i<TASK_COUNT; i++)); do
    TASK_JSON=$(echo "$STATE_JSON" | jq -c ".tasks[$i] // {}")
    TASK_TYPE=$(echo "$TASK_JSON" | jq -r '.type // "standard"')

    if [[ "$TASK_TYPE" == "standard" ]]; then
        PROMPT=$(echo "$TASK_JSON" | jq -r '.prompt // "No prompt"')

        if [[ $i -lt $CURRENT_INDEX ]]; then
            # Completed
            echo -e "   ${GREEN}✓ $((i + 1)). ${PROMPT}${NC}"
        elif [[ $i -eq $CURRENT_INDEX ]]; then
            # Current
            echo -e "   ${YELLOW}→ $((i + 1)). ${PROMPT}${NC}"
            echo -e "      ${CYAN}Output <done/> when complete${NC}"
        else
            # Pending
            echo -e "   ${GRAY}○ $((i + 1)). ${PROMPT}${NC}"
        fi

    elif [[ "$TASK_TYPE" == "fork" ]]; then
        SUBTASK_COUNT=$(echo "$TASK_JSON" | jq '.subtasks | length')

        if [[ $i -lt $CURRENT_INDEX ]]; then
            # Completed
            echo -e "   ${GREEN}✓ $((i + 1)). [FORK] ${SUBTASK_COUNT} parallel subtasks${NC}"
        elif [[ $i -eq $CURRENT_INDEX ]]; then
            # Current
            echo -e "   ${YELLOW}→ $((i + 1)). ${CYAN}[FORK]${YELLOW} Parallel subtasks:${NC}"
            echo "$TASK_JSON" | jq -r '.subtasks[]' | while read -r subtask; do
                echo -e "      ${YELLOW}• ${subtask}${NC}"
            done
            echo -e "      ${CYAN}Launch all via Task tool, then <done/>${NC}"
        else
            # Pending
            echo -e "   ${GRAY}○ $((i + 1)). [FORK] ${SUBTASK_COUNT} parallel subtasks${NC}"
        fi
    fi
done

echo ""
echo -e "${BLUE}Commands:${NC}"
echo -e "   /and-then-add    - Add more tasks"
echo -e "   /and-then-skip   - Skip current task"
echo -e "   /and-then-cancel - Cancel the queue"
