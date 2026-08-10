# vector-memory

Remembers what compaction throws away.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| PreCompact | `precompact_vectorize.sh` | Vectorizes the transcript into qdrant before it is compacted away |
| PreToolUse (`Bash\|Edit\|Write\|apply_patch\|Agent`) | `retrieve_vectors.sh` | Pulls relevant prior-session context back out |

Both are thin wrappers over the `claude-vector` CLI. `hooks/scripts/qdrant_utils.py` holds
the collection/embedding helpers.

## Requirements

- `claude-vector` on `PATH` (from `claude-vector-tools`)
- A reachable qdrant instance

Without both, every hook is a no-op — nothing is stored and nothing is injected. These hooks
run on **every** tool call in the matcher, so watch the latency before enabling on a slow
qdrant.
