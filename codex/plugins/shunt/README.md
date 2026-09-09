# shunt

Denies whole-file reads of large files and hands them to a cheap subagent instead, so the
corpus never enters the main context.

Adapted from the [shunt plugin](https://github.com/sorantis/portal-ai-plugins/tree/add-shunt-claude/plugins/shunt)
in `sorantis/portal-ai-plugins`, minus its transport layer. Upstream pipes file *contents*
through `argv` to a Spotify-internal AiKA mode; here the cheap worker is `spawn_agent`, so
there is nothing to transport — no payload ceiling, no request timeout, no external service
to authenticate against.

## Requires multi_agent

```toml
[features]
multi_agent = true
```

Without it there is no `spawn_agent` tool, so the guard's denials have nowhere to send the
model. Enable the feature, or set `SHUNT_GUARD_OFF=1` and take the skill as advice.

## What it does

| Layer | |
|---|---|
| `hooks/scripts/shunt-guard.sh` | `PreToolUse` on every tool. Denies a shell read (`cat`/`head`/`bat`/`less`/`more`) of a file above `SHUNT_MIN_LINES`. |
| `skills/shunt/SKILL.md` | Tells the agent what to do instead: `spawn_agent` with `fork_turns: "none"`. |

The hook is the enforcement and the skill is the instruction. Neither is much use alone — a
skill without the hook gets forgotten under load, a hook without the skill just blocks.

Codex has no read tool — `Read` does not exist, and files come in through the shell, whose
command arrives as an argv array like `["bash","-lc","cat x"]`. So the guard inspects
commands rather than a file-path argument, and matches `Bash`, the name
[codex/README.md](../../README.md#tool-names) records for the shell tool (it covers
`exec_command`). The read arm of the script is inert here; it is kept so the two harness
copies stay diffable.

## What gets through

- Targeted reads — `sed -n 'A,Bp'`, `head -100`.
- Pipes and redirects — `cat big.ts | grep foo`, `cat big.ts > out`. Those aren't reads
  into context.
- Anything at or under the threshold.
- Everything that isn't a read at all.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `SHUNT_MIN_LINES` | `800` | Line count above which a whole-file read is denied |
| `SHUNT_GUARD_OFF` | unset | Set to `1` to pass everything through |

## Install

Add the marketplace at `.agents/plugins/marketplace.json`, then install `shunt`.

## Tests

```bash
bash claude/plugins/shunt/test-shunt-guard.sh   # one suite, runs against both copies
```
