#!/usr/bin/env bash
# and-then-add.sh - Add tasks to an existing and-then queue
# Usage: and-then-add.sh --task "task1" [--task "task2"] [--fork [--workers N] "sub1" "sub2" ...]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# State file location (JSON format - no external dependencies)
QUEUE_FILE=".claude/and-then-queue.json"

# Check if queue exists
if [[ ! -f "$QUEUE_FILE" ]]; then
    echo -e "${RED}Error: No and-then queue exists.${NC}" >&2
    echo -e "${YELLOW}Use /and-then to create a new queue first.${NC}" >&2
    exit 1
fi

# Array to hold new task objects (JSON strings)
declare -a NEW_TASKS=()

# Temporary array for fork subtasks
declare -a FORK_SUBTASKS=()

# Workers count for current fork (0 = unlimited/all at once)
FORK_WORKERS=0

# Function to flush fork subtasks as a task object
flush_fork() {
    if [[ ${#FORK_SUBTASKS[@]} -gt 0 ]]; then
        # Build JSON array of subtasks using jq
        local subtasks_json
        subtasks_json=$(printf '%s\n' "${FORK_SUBTASKS[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')

        if [[ $FORK_WORKERS -gt 0 ]]; then
            NEW_TASKS+=("{\"type\":\"fork\",\"workers\":$FORK_WORKERS,\"subtasks\":$subtasks_json}")
        else
            NEW_TASKS+=("{\"type\":\"fork\",\"subtasks\":$subtasks_json}")
        fi
        FORK_SUBTASKS=()
        FORK_WORKERS=0
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --task|-t)
            flush_fork

            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --task requires a value${NC}" >&2
                exit 1
            fi
            # Use jq for proper JSON escaping
            ESCAPED=$(echo -n "$2" | jq -R -s '.')
            # Remove surrounding quotes since we'll add them in the JSON object
            ESCAPED="${ESCAPED:1:-1}"
            NEW_TASKS+=("{\"type\":\"standard\",\"prompt\":\"$ESCAPED\"}")
            shift 2
            ;;
        --fork|-f)
            flush_fork
            shift

            # Check for optional --workers flag
            if [[ "${1:-}" == "--workers" ]] || [[ "${1:-}" == "-w" ]]; then
                shift
                if [[ -z "${1:-}" ]] || ! [[ "$1" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Error: --workers requires a numeric value${NC}" >&2
                    exit 1
                fi
                FORK_WORKERS="$1"
                shift
            fi

            while [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; do
                FORK_SUBTASKS+=("$1")
                shift
            done

            if [[ ${#FORK_SUBTASKS[@]} -eq 0 ]]; then
                echo -e "${RED}Error: --fork requires at least one subtask${NC}" >&2
                exit 1
            fi
            ;;
        --help|-h)
            echo "Usage: and-then-add.sh --task \"task1\" [--task \"task2\"] [--fork [--workers N] \"sub1\" \"sub2\" ...]"
            echo ""
            echo "Add tasks to an existing and-then queue."
            echo ""
            echo "Options:"
            echo "  --task, -t           Standard task (executed sequentially)"
            echo "  --fork, -f           Fork task (subtasks run in parallel via subagents)"
            echo "  --workers N, -w N    Limit concurrent workers for fork (default: all at once)"
            echo "  --help, -h           Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $1${NC}" >&2
            exit 1
            ;;
    esac
done

# Flush any remaining fork subtasks
flush_fork

# Validate we have at least one task to add
if [[ ${#NEW_TASKS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: At least one --task or --fork is required${NC}" >&2
    exit 1
fi

# Build JSON array for new tasks
NEW_TASKS_JSON="["
for i in "${!NEW_TASKS[@]}"; do
    [[ $i -gt 0 ]] && NEW_TASKS_JSON+=","
    NEW_TASKS_JSON+="${NEW_TASKS[$i]}"
done
NEW_TASKS_JSON+="]"

# Get current task count before update
CURRENT_COUNT=$(jq '.tasks | length' "$QUEUE_FILE")

# Update the state file using jq (append new tasks to existing tasks array)
jq --argjson new_tasks "$NEW_TASKS_JSON" '.tasks += $new_tasks' "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

# Get new task count
NEW_COUNT=$(jq '.tasks | length' "$QUEUE_FILE")
ADDED_COUNT=$((NEW_COUNT - CURRENT_COUNT))

echo -e "${GREEN}✓ Added ${ADDED_COUNT} task(s) to queue${NC}"
echo -e "  Total tasks: ${NEW_COUNT}"
echo ""
echo -e "${BLUE}New tasks:${NC}"

TASK_NUM=1
for obj in "${NEW_TASKS[@]}"; do
    TYPE=$(echo "$obj" | jq -r '.type // "standard"')

    if [[ "$TYPE" == "standard" ]]; then
        PROMPT=$(echo "$obj" | jq -r '.prompt // ""')
        echo -e "  + ${PROMPT}"
    elif [[ "$TYPE" == "fork" ]]; then
        WORKERS=$(echo "$obj" | jq -r '.workers // 0')
        SUBTASK_COUNT=$(echo "$obj" | jq '.subtasks | length')
        if [[ "$WORKERS" -gt 0 ]]; then
            echo -e "  + ${CYAN}[FORK workers=${WORKERS}]${NC} ${SUBTASK_COUNT} parallel subtasks:"
        else
            echo -e "  + ${CYAN}[FORK]${NC} ${SUBTASK_COUNT} parallel subtasks:"
        fi
        echo "$obj" | jq -r '.subtasks[]' | while read -r subtask; do
            echo -e "      • ${subtask}"
        done
    fi

    TASK_NUM=$((TASK_NUM + 1))
done
