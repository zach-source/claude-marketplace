# claude-marketplace

Claude Code plugins for enhanced productivity and automation.

## Installation

Clone or download this repo, then add to your `.claude/plugins.json`:

```json
{
  "plugins": [
    "/path/to/claude-marketplace"
  ]
}
```

---

# And-Then Task Queue

A sequential task queue with parallel fork support. Tasks auto-advance when completed.

## Usage

```bash
# Sequential tasks
/and-then --task "Build the API" --task "Write tests" --task "Update docs"

# Mix sequential and parallel tasks
/and-then --task "Build the API" \
          --fork "Unit tests" "Integration tests" "E2E tests" \
          --task "Deploy to staging"
```

## Task Types

| Type | Flag | Description |
|------|------|-------------|
| **Standard** | `--task` | Sequential task, executed one at a time |
| **Fork** | `--fork` | Parallel task, spawns multiple subagents concurrently |

## How It Works

1. The queue is stored in `.claude/and-then-queue.local.md`
2. Claude works on the current task
3. When done, Claude outputs `<done/>`
4. The Stop hook detects completion and advances to the next task
5. For fork tasks: Claude launches parallel subagents, waits for all to complete
6. Repeats until all tasks are complete

## Commands

| Command | Description |
|---------|-------------|
| `/and-then` | Create a new task queue |
| `/and-then-add` | Add tasks to the existing queue |
| `/and-then-skip` | Skip current task, move to next |
| `/and-then-status` | Show queue progress |
| `/and-then-cancel` | Cancel the queue |

## Signaling Completion

Simply output `<done/>` when each task is complete:

```
<done/>
```

## Plugin Structure

```
claude-marketplace/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest
├── commands/                 # Slash commands
│   ├── and-then.md
│   ├── and-then-add.md
│   ├── and-then-skip.md
│   ├── and-then-status.md
│   └── and-then-cancel.md
├── hooks/
│   ├── hooks.json           # Hook configuration
│   └── scripts/
│       └── and-then-stop-hook.sh
├── scripts/                  # Utility scripts
│   ├── setup-and-then.sh
│   ├── and-then-add.sh
│   ├── and-then-skip.sh
│   └── and-then-status.sh
└── README.md
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
