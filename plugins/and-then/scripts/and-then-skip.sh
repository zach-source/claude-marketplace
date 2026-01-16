#!/usr/bin/env bash
# and-then-skip.sh - Skip the current task and move to the next one

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

QUEUE_FILE=".claude/and-then-queue.local.md"

if [[ ! -f "$QUEUE_FILE" ]]; then
    echo -e "${RED}Error: No and-then queue active${NC}" >&2
    exit 1
fi

# Get current state and advance index
python3 << 'EOF'
import yaml
import json
import sys

with open(".claude/and-then-queue.local.md", 'r') as f:
    content = f.read()

parts = content.split('---')
data = yaml.safe_load(parts[1])

current = data.get('current_index', 0)
tasks = data.get('tasks', [])
total = len(tasks)

if current >= total - 1:
    print(json.dumps({'status': 'exhausted', 'current': current, 'total': total}))
else:
    # Skip to next
    data['current_index'] = current + 1
    output = '---\n'
    output += yaml.dump(data, default_flow_style=False, sort_keys=False)
    output += '---\n'
    with open(".claude/and-then-queue.local.md", 'w') as f:
        f.write(output)

    next_task = tasks[current + 1]
    print(json.dumps({
        'status': 'skipped',
        'current': current,
        'total': total,
        'next_task': next_task
    }))
EOF
RESULT=$?

# Parse the JSON output
RESULT_JSON=$(python3 << 'EOF'
import yaml
import json

with open(".claude/and-then-queue.local.md", 'r') as f:
    content = f.read()

parts = content.split('---')
data = yaml.safe_load(parts[1])

current = data.get('current_index', 0)
tasks = data.get('tasks', [])
total = len(tasks)

# Already advanced by Python above, so current is now the "next" task
if current >= total:
    print(json.dumps({'status': 'exhausted', 'current': current - 1, 'total': total}))
else:
    task = tasks[current]
    print(json.dumps({
        'status': 'skipped',
        'skipped_index': current - 1,
        'current_index': current,
        'total': total,
        'task': task
    }))
EOF
)

STATUS=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")

if [[ "$STATUS" == "exhausted" ]]; then
    CURRENT=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('current',0))")
    TOTAL=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))")
    echo -e "${YELLOW}⚠️  Already on the last task ($((CURRENT + 1))/${TOTAL})${NC}"
    echo -e "${YELLOW}Cannot skip - use /and-then-cancel to stop the queue${NC}"
else
    SKIPPED=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('skipped_index',0))")
    CURRENT=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('current_index',0))")
    TOTAL=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total',0))")
    TASK_TYPE=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task',{}).get('type','standard'))")

    echo -e "${GREEN}✓ Skipped task $((SKIPPED + 1)), now on task $((CURRENT + 1))/${TOTAL}${NC}"

    if [[ "$TASK_TYPE" == "standard" ]]; then
        PROMPT=$(echo "$RESULT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task',{}).get('prompt',''))")
        echo -e "  ${BLUE}Next task:${NC} $PROMPT"
        echo -e "  ${CYAN}Output <done/> when complete${NC}"
    elif [[ "$TASK_TYPE" == "fork" ]]; then
        echo -e "  ${BLUE}Next task:${NC} ${CYAN}[FORK]${NC} Parallel subtasks:"
        echo "$RESULT_JSON" | python3 -c "
import sys, json
task = json.load(sys.stdin).get('task', {})
for subtask in task.get('subtasks', []):
    print(f'      • {subtask}')
"
        echo -e "  ${CYAN}Launch all via Task tool, then <done/>${NC}"
    fi
fi
