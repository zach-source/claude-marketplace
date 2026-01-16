#!/usr/bin/env bash
# and-then-add.sh - Add tasks to an existing and-then queue
# Usage: and-then-add.sh --task "task1" [--task "task2"] [--fork "sub1" "sub2" ...]

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

# Function to flush fork subtasks as a task object
flush_fork() {
    if [[ ${#FORK_SUBTASKS[@]} -gt 0 ]]; then
        # Build JSON array of subtasks
        SUBTASKS_JSON="["
        for i in "${!FORK_SUBTASKS[@]}"; do
            [[ $i -gt 0 ]] && SUBTASKS_JSON+=","
            ESCAPED="${FORK_SUBTASKS[$i]//\\/\\\\}"
            ESCAPED="${ESCAPED//\"/\\\"}"
            SUBTASKS_JSON+="\"$ESCAPED\""
        done
        SUBTASKS_JSON+="]"

        NEW_TASKS+=("{\"type\":\"fork\",\"subtasks\":$SUBTASKS_JSON}")
        FORK_SUBTASKS=()
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
            ESCAPED="${2//\\/\\\\}"
            ESCAPED="${ESCAPED//\"/\\\"}"
            NEW_TASKS+=("{\"type\":\"standard\",\"prompt\":\"$ESCAPED\"}")
            shift 2
            ;;
        --fork|-f)
            flush_fork
            shift

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
            echo "Usage: and-then-add.sh --task \"task1\" [--task \"task2\"] [--fork \"sub1\" \"sub2\" ...]"
            echo ""
            echo "Add tasks to an existing and-then queue."
            echo ""
            echo "Options:"
            echo "  --task, -t      Standard task (executed sequentially)"
            echo "  --fork, -f      Fork task (subtasks run in parallel via subagents)"
            echo "  --help, -h      Show this help message"
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

# Update the state file using Python
python3 << EOF
import yaml
import json

new_tasks_json = '''$NEW_TASKS_JSON'''
new_tasks = json.loads(new_tasks_json)

with open('$QUEUE_FILE', 'r') as f:
    content = f.read()

# Extract YAML frontmatter
parts = content.split('---')
data = yaml.safe_load(parts[1])

# Add new tasks
if 'tasks' not in data:
    data['tasks'] = []
data['tasks'].extend(new_tasks)

# Write updated state
with open('$QUEUE_FILE', 'w') as f:
    f.write('---\n')
    yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    f.write('---\n')

# Print summary
print(f"Added {len(new_tasks)} task(s) to queue")
print(f"Total tasks: {len(data['tasks'])}")
EOF

echo ""
echo -e "${GREEN}✓ Tasks added to queue${NC}"
echo ""
echo -e "${BLUE}New tasks:${NC}"

TASK_NUM=1
for obj in "${NEW_TASKS[@]}"; do
    TYPE=$(echo "$obj" | python3 -c "import sys,json; print(json.load(sys.stdin).get('type',''))")

    if [[ "$TYPE" == "standard" ]]; then
        PROMPT=$(echo "$obj" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))")
        echo -e "  + ${PROMPT}"
    elif [[ "$TYPE" == "fork" ]]; then
        SUBTASKS=$(echo "$obj" | python3 -c "import sys,json; print('\\n'.join(json.load(sys.stdin).get('subtasks',[])))")
        echo -e "  + ${CYAN}[FORK]${NC} Parallel subtasks:"
        while IFS= read -r subtask; do
            echo -e "      • ${subtask}"
        done <<< "$SUBTASKS"
    fi

    TASK_NUM=$((TASK_NUM + 1))
done
