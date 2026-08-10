# vector-memory

Remembers what compaction throws away.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| PreCompact | `precompact_vectorize.sh` | Vectorizes the transcript into qdrant before it is compacted away |
| PreToolUse (`Task\|Write\|Edit\|MultiEdit\|Read\|Grep\|Glob`) | `retrieve_vectors.sh` | Pulls relevant prior-session context back out |

`hooks/scripts/qdrant_utils.py` holds the collection/embedding helpers.

`precompact_vectorize.sh` is a thin wrapper — its job is a side effect (write to qdrant),
so its stdout does not need to reach the model.

`retrieve_vectors.sh` is **not** thin, because `claude-vector retrieve --json` does not
speak Claude Code's hook protocol on either end:

- It reads the query from `tool`/`arguments`; Claude Code sends `tool_name`/`tool_input`,
  so the query was always empty and the CLI answered *"No query provided for vector
  retrieval."*
- It prints `{"role","content"}`. PreToolUse only surfaces stdout to the model through
  `hookSpecificOutput.additionalContext` — everything else goes to the debug log and is
  dropped.

Both failures were silent: the hook exited 0 and looked healthy while retrieving nothing
and injecting nothing. The wrapper extracts the query itself and rewraps the result. Fixed
here rather than in the CLI, which is nix-managed and shared with other harnesses.

`bash test-retrieve-wrapper.sh` covers both, against a mocked CLI.

## Requirements

- `claude-vector` on `PATH` (from `claude-vector-tools`)
- A reachable qdrant instance

Without both, every hook is a no-op — nothing is stored and nothing is injected. These hooks
run on **every** tool call in the matcher, so watch the latency before enabling on a slow
qdrant.
