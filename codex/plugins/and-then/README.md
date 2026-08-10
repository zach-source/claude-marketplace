# And-Then

Sequential task queue with parallel fork support for Claude Code.

## Features

- **Sequential tasks** (`--task`): Execute tasks one at a time
- **Parallel fork tasks** (`--fork`): Spawn multiple subagents concurrently
- **Auto-completion**: Tasks advance automatically when you output `<done/>`
- **Dynamic additions**: Add tasks while queue is running

## Usage

```bash
# Sequential tasks
/and-then --task "Build the API" --task "Write tests" --task "Update docs"

# Mix sequential and parallel tasks
/and-then --task "Build the API" \
          --fork "Unit tests" "Integration tests" "E2E tests" \
          --task "Deploy to staging"
```

## Commands

| Command | Description |
|---------|-------------|
| `/and-then` | Create a new task queue |
| `/and-then-add` | Add tasks to existing queue |
| `/and-then-skip` | Skip current task |
| `/and-then-status` | Show queue progress |
| `/and-then-cancel` | Cancel the queue |

## How It Works

1. Queue stored in `.claude/and-then-queue.local.md`
2. Work on current task
3. Output `<done/>` when complete
4. Stop hook advances to next task
5. For forks: launch parallel subagents, wait for all, then `<done/>`

## Examples

### Parallel Testing Pipeline

```bash
/and-then --task "Build the application" \
          --fork "Run unit tests" "Run integration tests" "Run linting" \
          --task "Deploy to staging"
```

### Research-Then-Implement

```bash
/and-then --fork "Research auth libraries" "Review security requirements" \
          --task "Implement authentication" \
          --task "Write tests"
```
