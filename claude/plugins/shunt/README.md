# shunt

Denies whole-file reads of large files and hands them to a cheap subagent instead, so the
corpus never enters the main context.

Adapted from the [shunt plugin](https://github.com/sorantis/portal-ai-plugins/tree/add-shunt-claude/plugins/shunt)
in `sorantis/portal-ai-plugins`, minus its transport layer. Upstream pipes file *contents*
through `argv` to a Spotify-internal AiKA mode; here the cheap worker is an in-harness
subagent, so there is nothing to transport — no payload ceiling, no request timeout, no
external service to authenticate against.

## What it does

| Layer | |
|---|---|
| `hooks/scripts/shunt-guard.sh` | `PreToolUse` on `Read` and `Bash`. Denies a whole-file read above `SHUNT_MIN_LINES`. |
| `skills/shunt/SKILL.md` | Tells the agent what to do instead: `Explore`, or `Agent` with `model: haiku`. |

The hook is the enforcement and the skill is the instruction. Neither is much use alone — a
skill without the hook gets forgotten under load, a hook without the skill just blocks.

## What gets through

- Targeted reads — `Read` with `offset`/`limit`, `sed -n 'A,Bp'`, `head -100`.
- Pipes and redirects — `cat big.ts | grep foo`, `cat big.ts > out`. Those aren't reads
  into context.
- Anything at or under the threshold.
- Everything that isn't a read at all.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SHUNT_MIN_LINES` | `800` | Line count above which a whole-file read is denied |
| `SHUNT_GUARD_OFF` | unset | Set to `1` to pass everything through |
| `CLAUDE_HOOKS_BIN` | unset | Colon-separated bin dirs to resolve `jq`/`sed`/`wc` from first, for pinned (nix) deployments |

## Install

```bash
/plugin marketplace add zach-source/claude-marketplace
/plugin install shunt@agent-marketplace
```

## Tests

```bash
bash claude/plugins/shunt/test-shunt-guard.sh
```

20 routing cases: offset/limit reads, pipes, redirects, `2>/dev/null`, `cd x && cat big`,
`head -100` versus bare `head`, Codex's argv wrapping, and both escape hatches.
