# And-Then

Sequential task queue with parallel fork support.

## Features

- **Sequential tasks** (`--task`): Execute tasks one at a time
- **Parallel fork tasks** (`--fork`): Spawn multiple subagents concurrently
- **Auto-completion**: Tasks advance automatically when you output `<done/>`
- **Dynamic additions**: Add tasks while queue is running

## Usage

Codex plugins have no slash commands, so the queue is driven by running the
scripts directly. The bundled `and-then` skill tells the model how; these are the
same calls by hand:

```bash
# Sequential tasks
${PLUGIN_ROOT}/scripts/setup-and-then.sh --task "Build the API" --task "Write tests" --task "Update docs"

# Mix sequential and parallel tasks
${PLUGIN_ROOT}/scripts/setup-and-then.sh \
    --task "Build the API" \
    --fork "Unit tests" "Integration tests" "E2E tests" \
    --task "Deploy to staging"
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/setup-and-then.sh` | Create a new task queue |
| `scripts/and-then-add.sh` | Add tasks to existing queue |
| `scripts/and-then-skip.sh` | Skip current task |
| `scripts/and-then-status.sh` | Show queue progress |
| `rm .claude/and-then-queue.json` | Cancel the queue |

## How It Works

1. Queue stored in `.claude/and-then-queue.json`
2. Work on current task
3. Output `<done/>` when complete
4. Stop hook advances to next task
5. For forks: launch parallel subagents, wait for all, then `<done/>`

The Stop hook reads the finished turn from `last_assistant_message` on the hook
payload, which is what the hook docs point at for `Stop`. It also honours
`stop_hook_active`: once it has blocked a stop, a second stop with no readable
completion signal is allowed through rather than re-fed forever.

## Examples

### Parallel Testing Pipeline

```bash
${PLUGIN_ROOT}/scripts/setup-and-then.sh \
    --task "Build the application" \
    --fork "Run unit tests" "Run integration tests" "Run linting" \
    --task "Deploy to staging"
```

### Research-Then-Implement

```bash
${PLUGIN_ROOT}/scripts/setup-and-then.sh \
    --fork "Research auth libraries" "Review security requirements" \
    --task "Implement authentication" \
    --task "Write tests"
```
