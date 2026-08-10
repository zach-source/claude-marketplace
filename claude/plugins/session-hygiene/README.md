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

## Test

`python3 test-session-staleness.py` drives the whole herdr compact-and-resend path against a
synthetic stale transcript with a fake `herdr` on `PATH`: it asserts the prompt is refused
(exit 2) and that `/compact` and then the refused prompt are dispatched to `HERDR_PANE_ID`,
in that order. The dispatch is detached and sleeps before typing, so the test polls rather
than assuming it has run by the time the hook exits.

No pytest needed — it runs standalone, and `nix flake check` runs it.

## Utility

`scripts/sync-mcp-servers.sh` strips `mcpServers` out of `~/.claude.json`, where it shadows
`~/.claude/mcp_servers.json`. Not wired as a hook — run it by hand or drop it on `PATH`.

## Requirements

`python3`, `jq`.
