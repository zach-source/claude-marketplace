#!/usr/bin/env bash
# setup-and-then.sh - Creates the and-then task queue state file
# Usage: setup-and-then.sh --task "task1" [--task "task2"] [--fork "subtask1" "subtask2" ...]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# State file location
QUEUE_FILE=".claude/and-then-queue.local.md"
RALPH_FILE=".claude/ralph-loop.local.md"

# Array to hold task objects (JSON strings)
declare -a TASK_OBJECTS=()

# Temporary array for fork subtasks
declare -a FORK_SUBTASKS=()
IN_FORK=false

# Function to flush fork subtasks as a task object
flush_fork() {
    if [[ ${#FORK_SUBTASKS[@]} -gt 0 ]]; then
        # Build JSON array of subtasks
        SUBTASKS_JSON="["
        for i in "${!FORK_SUBTASKS[@]}"; do
            [[ $i -gt 0 ]] && SUBTASKS_JSON+=","
            # Escape quotes and build JSON string
            ESCAPED="${FORK_SUBTASKS[$i]//\\/\\\\}"
            ESCAPED="${ESCAPED//\"/\\\"}"
            SUBTASKS_JSON+="\"$ESCAPED\""
        done
        SUBTASKS_JSON+="]"

        TASK_OBJECTS+=("{\"type\":\"fork\",\"subtasks\":$SUBTASKS_JSON}")
        FORK_SUBTASKS=()
    fi
    IN_FORK=false
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
            # Escape quotes for JSON
            ESCAPED="${2//\\/\\\\}"
            ESCAPED="${ESCAPED//\"/\\\"}"
            TASK_OBJECTS+=("{\"type\":\"standard\",\"prompt\":\"$ESCAPED\"}")
            shift 2
            ;;
        --fork|-f)
            # Flush any pending fork subtasks (start new fork group)
            flush_fork
            IN_FORK=true
            shift

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
            echo "Usage: setup-and-then.sh --task \"task1\" [--task \"task2\"] [--fork \"sub1\" \"sub2\" ...]"
            echo ""
            echo "Options:"
            echo "  --task, -t      Standard task (executed sequentially)"
            echo "  --fork, -f      Fork task (subtasks run in parallel via subagents)"
            echo "  --help, -h      Show this help message"
            echo ""
            echo "Completion: Output <done/> when each task is complete (auto-detected)"
            echo ""
            echo "Examples:"
            echo "  # Sequential tasks"
            echo "  setup-and-then.sh --task \"Build API\" --task \"Write tests\" --task \"Deploy\""
            echo ""
            echo "  # Mix of sequential and parallel tasks"
            echo "  setup-and-then.sh --task \"Build API\" \\"
            echo "                    --fork \"Unit tests\" \"Integration tests\" \"E2E tests\" \\"
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

# Build JSON tasks array
TASKS_JSON="["
for i in "${!TASK_OBJECTS[@]}"; do
    [[ $i -gt 0 ]] && TASKS_JSON+=","
    TASKS_JSON+="${TASK_OBJECTS[$i]}"
done
TASKS_JSON+="]"

# Convert to YAML and write state file using Python
python3 << EOF
import json
import yaml

tasks_json = '''$TASKS_JSON'''
tasks = json.loads(tasks_json)

data = {
    'active': True,
    'current_index': 0,
    'started_at': '$TIMESTAMP',
    'tasks': tasks
}

with open('$QUEUE_FILE', 'w') as f:
    f.write('---\n')
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    f.write('---\n')
EOF

# Display confirmation
echo -e "${GREEN}✓ And-then queue created with ${#TASK_OBJECTS[@]} task(s)${NC}"
echo ""
echo -e "${BLUE}Tasks:${NC}"

TASK_NUM=1
for obj in "${TASK_OBJECTS[@]}"; do
    TYPE=$(echo "$obj" | python3 -c "import sys,json; print(json.load(sys.stdin).get('type',''))")

    if [[ "$TYPE" == "standard" ]]; then
        PROMPT=$(echo "$obj" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))")
        echo -e "  ${TASK_NUM}. ${PROMPT}"
    elif [[ "$TYPE" == "fork" ]]; then
        SUBTASKS=$(echo "$obj" | python3 -c "import sys,json; print('\\n'.join(json.load(sys.stdin).get('subtasks',[])))")
        echo -e "  ${TASK_NUM}. ${CYAN}[FORK]${NC} Parallel subtasks:"
        while IFS= read -r subtask; do
            echo -e "      • ${subtask}"
        done <<< "$SUBTASKS"
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
