# session-hygiene

Keeps long sessions from quietly getting expensive.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| UserPromptSubmit | `session-staleness.py` | **Blocks** (exit 2) the prompt when a resumed session's prompt cache has lapsed and the context is big enough for the miss to hurt, forcing a `/compact` first |

No hook output can trigger compaction directly, so refusing the submission is the closest
available behaviour.

### Tuning

| Env var | Default | Meaning |
|---------|---------|---------|
| `CLAUDE_STALE_BLOCK` | `1` | `0` = warn instead of block |
| `CLAUDE_CACHE_TTL_SECONDS` | `300` | Raise to `3600` if you have extended cache TTL |
| `CLAUDE_STALE_MIN_TOKENS` | `200000` | Below this, never block |
| `CLAUDE_STALE_SETTLE_SECONDS` | `3` | Re-read delay, to let an in-flight `/compact` land |

At the 300s default any five-minute pause on a large session refuses the next prompt. Set
the TTL to the cache you actually have.

The Claude build also ships `scripts/sync-mcp-servers.sh`, which rewrites
`~/.claude.json`. It is not carried over here: it is wired to no hook, and Codex
keeps its MCP configuration somewhere else entirely, so the only thing it could
do in this tree is edit another harness's config by surprise.

## Requirements

`python3`, `jq`.
