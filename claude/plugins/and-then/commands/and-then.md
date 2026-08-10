---
name: and-then
description: Create a sequential task queue with optional parallel fork tasks
arguments:
  - name: args
    description: Tasks using --task and optional --fork flags
    required: true
allowed_tools:
  - Bash
---

# And-Then Task Queue

Execute a series of tasks sequentially, with optional parallel fork tasks. Automatically advances to the next task when you output `<done/>`.

## Usage

```bash
# Sequential tasks
/and-then --task "Task 1" --task "Task 2" --task "Task 3"

# Mix sequential and parallel tasks
/and-then --task "Build API" \
          --fork "Unit tests" "Integration tests" "E2E tests" \
          --task "Deploy to staging"

# Parallel with limited concurrency (2 workers at a time)
/and-then --fork --workers 2 "Task A" "Task B" "Task C" "Task D"
```

## Task Types

### Standard Tasks (`--task`)
Sequential tasks executed one at a time. Output `<done/>` when complete.

### Fork Tasks (`--fork`)
Parallel tasks that spawn multiple subagents concurrently. All subtasks run simultaneously, then rejoin before continuing.

```bash
--fork "Subtask 1" "Subtask 2" "Subtask 3"
```

### Fork with Workers (`--fork --workers N`)
Limit concurrency to N workers at a time. Useful for resource-intensive tasks.

```bash
--fork --workers 2 "Heavy Task A" "Heavy Task B" "Heavy Task C" "Heavy Task D"
```

## Signaling Completion

Simply output `<done/>` when each task is complete:

```
<done/>
```

No need to specify custom completion signals - the system auto-detects completion.

## Managing the Queue

- `/and-then-add` - Add more tasks to the queue
- `/and-then-skip` - Skip current task, move to next
- `/and-then-status` - Show current queue status
- `/and-then-cancel` - Clear the queue and exit

## Examples

### Sequential workflow
```bash
/and-then --task "Create database schema" \
          --task "Build REST API" \
          --task "Write API documentation"
```

### Parallel testing then deploy
```bash
/and-then --task "Build the application" \
          --fork "Run unit tests" "Run integration tests" "Run linting" \
          --task "Deploy to staging"
```

### Research then implement
```bash
/and-then --fork "Research auth libraries" "Review security requirements" \
          --task "Implement authentication" \
          --task "Write tests"
```

---

**Setting up the task queue...**

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/setup-and-then.sh $ARGUMENTS
```

Once the queue is created, I'll begin working on the first task. When I complete it, I'll output `<done/>` and automatically move to the next task.

For fork tasks, I'll launch parallel subagents for each subtask, wait for all to complete, then output `<done/>` to advance.
