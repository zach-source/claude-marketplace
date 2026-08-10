#!/usr/bin/env bash
# setup-and-then.sh - Creates the and-then task queue state file
# Usage: setup-and-then.sh --task "task1" [--task "task2"] [--fork [--workers N] "subtask1" "subtask2" ...]

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
RALPH_FILE=".claude/ralph-loop.local.md"

# Array to hold task objects (JSON strings)
declare -a TASK_OBJECTS=()

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
            TASK_OBJECTS+=("{\"type\":\"fork\",\"workers\":$FORK_WORKERS,\"subtasks\":$subtasks_json}")
        else
            TASK_OBJECTS+=("{\"type\":\"fork\",\"subtasks\":$subtasks_json}")
        fi
        FORK_SUBTASKS=()
        FORK_WORKERS=0
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --task|-t)
            # Flush any pending fork subtasks
            flush_fork

            if [[ -z "${2:-}" ]]; then
                echo -e "${RED}Error: --task requires a value${NC}" >&2
                exit 1
            fi
            # Use jq for proper JSON escaping
            ESCAPED=$(echo -n "$2" | jq -R -s '.')
            # Remove surrounding quotes since we'll add them in the JSON object
            ESCAPED="${ESCAPED:1:-1}"
            TASK_OBJECTS+=("{\"type\":\"standard\",\"prompt\":\"$ESCAPED\"}")
            shift 2
            ;;
        --fork|-f)
            # Flush any pending fork subtasks (start new fork group)
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

            # Collect all following arguments until next flag
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
            echo "Usage: setup-and-then.sh --task \"task1\" [--task \"task2\"] [--fork [--workers N] \"sub1\" \"sub2\" ...]"
            echo ""
            echo "Options:"
            echo "  --task, -t           Standard task (executed sequentially)"
            echo "  --fork, -f           Fork task (subtasks run in parallel via subagents)"
            echo "  --workers N, -w N    Limit concurrent workers for fork (default: all at once)"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Completion: Output <done/> when each task is complete (auto-detected)"
            echo ""
            echo "Examples:"
            echo "  # Sequential tasks"
            echo "  setup-and-then.sh --task \"Build API\" --task \"Write tests\" --task \"Deploy\""
            echo ""
            echo "  # Parallel tasks (all at once)"
            echo "  setup-and-then.sh --fork \"Unit tests\" \"Integration tests\" \"E2E tests\""
            echo ""
            echo "  # Parallel tasks with limited concurrency (2 at a time)"
            echo "  setup-and-then.sh --fork --workers 2 \"Task A\" \"Task B\" \"Task C\" \"Task D\""
            echo ""
            echo "  # Mix of sequential and parallel"
            echo "  setup-and-then.sh --task \"Build API\" \\"
            echo "                    --fork --workers 3 \"Test 1\" \"Test 2\" \"Test 3\" \"Test 4\" \\"
            echo "                    --task \"Deploy to staging\""
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $1${NC}" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Flush any remaining fork subtasks
flush_fork

# Validate we have at least one task
if [[ ${#TASK_OBJECTS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: At least one --task or --fork is required${NC}" >&2
    exit 1
fi

# Check for Ralph loop conflict
if [[ -f "$RALPH_FILE" ]]; then
    echo -e "${YELLOW}Warning: Ralph loop is active at $RALPH_FILE${NC}" >&2
    echo -e "${YELLOW}The and-then queue and Ralph loop may conflict.${NC}" >&2
    echo -e "${YELLOW}Consider canceling Ralph loop first: /cancel-ralph${NC}" >&2
fi

# Check if queue already exists
if [[ -f "$QUEUE_FILE" ]]; then
    echo -e "${YELLOW}Warning: An and-then queue already exists.${NC}" >&2
    echo -e "${YELLOW}Use /and-then-add to add tasks, or /and-then-cancel to start fresh.${NC}" >&2
    exit 1
fi

# Create .claude directory if needed
mkdir -p .claude

# Get current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build tasks array JSON
TASKS_JSON="["
for i in "${!TASK_OBJECTS[@]}"; do
    [[ $i -gt 0 ]] && TASKS_JSON+=","
    TASKS_JSON+="${TASK_OBJECTS[$i]}"
done
TASKS_JSON+="]"

# Create state file using jq for proper JSON formatting
jq -n \
    --argjson tasks "$TASKS_JSON" \
    --arg started_at "$TIMESTAMP" \
    '{
        active: true,
        current_index: 0,
        started_at: $started_at,
        tasks: $tasks
    }' > "$QUEUE_FILE"

# Display confirmation
echo -e "${GREEN}✓ And-then queue created with ${#TASK_OBJECTS[@]} task(s)${NC}"
echo ""
echo -e "${BLUE}Tasks:${NC}"

TASK_NUM=1
for obj in "${TASK_OBJECTS[@]}"; do
    TYPE=$(echo "$obj" | jq -r '.type // "standard"')

    if [[ "$TYPE" == "standard" ]]; then
        PROMPT=$(echo "$obj" | jq -r '.prompt // ""')
        echo -e "  ${TASK_NUM}. ${PROMPT}"
    elif [[ "$TYPE" == "fork" ]]; then
        WORKERS=$(echo "$obj" | jq -r '.workers // 0')
        SUBTASK_COUNT=$(echo "$obj" | jq '.subtasks | length')
        if [[ "$WORKERS" -gt 0 ]]; then
            echo -e "  ${TASK_NUM}. ${CYAN}[FORK workers=${WORKERS}]${NC} ${SUBTASK_COUNT} parallel subtasks:"
        else
            echo -e "  ${TASK_NUM}. ${CYAN}[FORK]${NC} ${SUBTASK_COUNT} parallel subtasks:"
        fi
        echo "$obj" | jq -r '.subtasks[]' | while read -r subtask; do
            echo -e "      • ${subtask}"
        done
    fi

    TASK_NUM=$((TASK_NUM + 1))
done

echo ""
echo -e "${BLUE}State file:${NC} $QUEUE_FILE"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT:${NC}"
echo -e "  • Output ${GREEN}<done/>${NC} when each task is complete"
echo -e "  • Fork tasks: Launch parallel subagents, then ${GREEN}<done/>${NC} when all complete"
echo -e "  • The session will auto-advance to the next task"
echo -e "  • Use ${BLUE}/and-then-add${NC} to add more tasks"
echo -e "  • Use ${BLUE}/and-then-cancel${NC} to stop the queue"
