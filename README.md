# claude-and-then

A Claude Code plugin that provides a sequential task queue system with support for parallel fork tasks. Tasks are executed automatically, advancing when each task completes.

## Installation

Clone or download this repo, then add to your `.claude/plugins.json`:

```json
{
  "plugins": [
    "/path/to/claude-and-then"
  ]
}
```

Or symlink to your `.claude/plugins/` directory:

```bash
ln -s /path/to/claude-and-then ~/.claude/plugins/and-then
```

## Usage

### Create a Task Queue

```bash
# Sequential tasks
/and-then --task "Build the API" --task "Write tests" --task "Update docs"

# Mix sequential and parallel tasks
/and-then --task "Build the API" \
          --fork "Unit tests" "Integration tests" "E2E tests" \
          --task "Deploy to staging"
```

### Task Types

| Type | Flag | Description |
|------|------|-------------|
| **Standard** | `--task` | Sequential task, executed one at a time |
| **Fork** | `--fork` | Parallel task, spawns multiple subagents concurrently |

### How It Works

1. The queue is stored in `.claude/and-then-queue.local.md`
2. Claude works on the current task
3. When done, Claude outputs `<done/>`
4. The Stop hook detects completion and advances to the next task
5. For fork tasks: Claude launches parallel subagents, waits for all to complete
6. Repeats until all tasks are complete

### Commands

| Command | Description |
|---------|-------------|
| `/and-then` | Create a new task queue |
| `/and-then-add` | Add tasks to the existing queue |
| `/and-then-skip` | Skip current task, move to next |
| `/and-then-status` | Show queue progress |
| `/and-then-cancel` | Cancel the queue |

### Signaling Task Completion

Simply output `<done/>` when each task is complete:

```
<done/>
```

No custom completion signals required - the system auto-detects completion.

## State File Format

The queue state is stored in `.claude/and-then-queue.local.md`:

```yaml
---
active: true
current_index: 0
started_at: "2025-01-15T10:30:45Z"
tasks:
  - type: standard
    prompt: "Build the API"
  - type: fork
    subtasks:
      - "Unit tests"
      - "Integration tests"
      - "E2E tests"
  - type: standard
    prompt: "Deploy to staging"
---
```

## Examples

### Sequential Development Workflow

```bash
/and-then --task "Create database schema" \
          --task "Build REST API endpoints" \
          --task "Write API documentation"
```

### Parallel Testing Pipeline

```bash
/and-then --task "Build the application" \
          --fork "Run unit tests" "Run integration tests" "Run linting" \
          --task "Deploy to staging"
```

### Research-Then-Implement Pattern

```bash
/and-then --fork "Research auth libraries" "Review security requirements" \
          --task "Implement authentication" \
          --task "Write tests"
```

## License

MIT
