#!/usr/bin/env bash
# and-then-skip.sh - Skip the current task and move to the next one

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# State file location (JSON format - no external dependencies)
QUEUE_FILE=".claude/and-then-queue.json"

if [[ ! -f "$QUEUE_FILE" ]]; then
    echo -e "${RED}Error: No and-then queue active${NC}" >&2
    exit 1
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

# Check if we're on the last task
if [[ $CURRENT_INDEX -ge $((TASK_COUNT - 1)) ]]; then
    echo -e "${YELLOW}⚠️  Already on the last task ($((CURRENT_INDEX + 1))/${TASK_COUNT})${NC}"
    echo -e "${YELLOW}Cannot skip - use /and-then-cancel to stop the queue${NC}"
    exit 0
fi

# Calculate next index
NEXT_INDEX=$((CURRENT_INDEX + 1))

# Update state file with new index
echo "$STATE_JSON" | jq ".current_index = $NEXT_INDEX" > "$QUEUE_FILE"

# Get the new current task info
NEXT_TASK_JSON=$(echo "$STATE_JSON" | jq -c ".tasks[$NEXT_INDEX] // {}")
TASK_TYPE=$(echo "$NEXT_TASK_JSON" | jq -r '.type // "standard"')

echo -e "${GREEN}✓ Skipped task $((CURRENT_INDEX + 1)), now on task $((NEXT_INDEX + 1))/${TASK_COUNT}${NC}"

if [[ "$TASK_TYPE" == "standard" ]]; then
    PROMPT=$(echo "$NEXT_TASK_JSON" | jq -r '.prompt // "No prompt"')
    echo -e "  ${BLUE}Next task:${NC} $PROMPT"
    echo -e "  ${CYAN}Output <done/> when complete${NC}"
elif [[ "$TASK_TYPE" == "fork" ]]; then
    echo -e "  ${BLUE}Next task:${NC} ${CYAN}[FORK]${NC} Parallel subtasks:"
    echo "$NEXT_TASK_JSON" | jq -r '.subtasks[]' | while read -r subtask; do
        echo -e "      • ${subtask}"
    done
    echo -e "  ${CYAN}Launch all via Task tool, then <done/>${NC}"
fi
