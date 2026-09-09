---
name: shunt
description: "Shunt I/O-heavy work off the main context onto a cheap subagent — reading large files, answering questions spanning several files, summarizing big diffs, generating boilerplate from a reference. Use when a file is over ~800 lines, when a question spans 3+ files, or when the shunt-guard PreToolUse hook denies a read. Triggers on: shunt, bulk read, large file, delegate the read, too many tokens, context is filling up, read these files, summarize this diff, generate boilerplate."
---

# shunt — send bulk I/O to a cheap model

Reading a 4,000-line file costs ~33k tokens of *your* context and you keep paying for it
every turn afterwards. A subagent reads it in its own context and hands back an answer
measured in hundreds of tokens. The files never enter this conversation.

Codex's built-in instructions say not to spawn subagents unless a skill or AGENTS.md
explicitly asks for delegation. **This skill asks for it**, for the cases below. You do not
need to check with the user first.

Requires `features.multi_agent = true` in `~/.codex/config.toml`. Without it there is no
`spawn_agent` tool and the guard's denials have nowhere to send you — read in spans instead,
or set `SHUNT_GUARD_OFF=1`.

## When to shunt

- Any file over ~800 lines you want to understand rather than edit.
- A question that spans 3+ files ("where is auth enforced?", "which handlers touch the DB?").
- Summarizing a large diff or log.
- Boilerplate: tests, config, type stubs, docstrings — anything >80% predictable from a
  reference file that already exists in the repo.

## When NOT to shunt

- **Editing.** An edit needs the exact bytes in your context. Read the span you need with
  `sed -n 'A,Bp'`. Never edit from a summary.
- **Debugging.** You need the reasoning, not a précis of it. Keep it local.
- **Small files.** Under the threshold the round-trip costs more than it saves.
- **Architecture and judgment calls.** Those are why you are the one being asked.

## How

`spawn_agent`, then `wait_agent` only if the result blocks your
very next step. Otherwise keep working and collect it when it lands.

```
spawn_agent(task_name: "read_service", fork_turns: "none",
  message: "Read src/Service.java and src/Handler.java. List every method that opens a
  DB connection as `file:line — method — what it does`. Bullets only, no prose.")
```

**Model.** Leave it unset unless `SHUNT_MODEL` is set. The subagent then inherits yours,
which is what Codex's own guidance asks for, and the saving here comes from *context
isolation* rather than from a cheaper worker — the corpus lands in the subagent's window,
not yours, whatever model reads it.

When `SHUNT_MODEL` is set, pass it as `model:`. You do not have to go looking: the guard
names it in its denial, so the value reaches you at the moment you need it.

```bash
SHUNT_MODEL=gpt-5.4    # per-deployment override; unset = inherit
```

Set it to an id your *provider* serves, not merely one Codex names. `codex debug models`
lists tiers a gateway in front of it may reject — `gpt-5.4-mini` is listed but answers
`400 Invalid model name` on at least one gateway in production use, and a rejected id surfaces as a dead
subagent rather than a clear error. That mismatch is why this is an environment variable
and not a value baked into the skill.

`fork_turns: "none"` sends no conversation history — right for a read, since the paths and
the question are the whole brief. Use `"all"` only when the subtask genuinely needs to know
what came before; it costs the subagent's context, not yours.

Name the exact paths and the exact question. A vague brief comes back as a vague summary you
then have to re-derive, which costs more than the read would have.

Run independent reads in parallel — several `spawn_agent` calls in one round, one
`wait_agent` at the end — rather than serially.

## Verify before you act on it

A summary is evidence, not fact. Before you edit based on a shunted read, confirm the
specific line numbers and identifiers you are about to touch — one `sed -n 'A,Bp'` or a
`grep`. Cheap models transpose line numbers.

## The guard

This plugin's `PreToolUse` hook denies shell reads of files over `SHUNT_MIN_LINES` (default
800) — `cat`, `head`, `bat`, `less`, `more`. It allows targeted reads, pipes, and redirects.
If it denies something you genuinely need whole, either read it in spans or raise the
threshold for the session:

```bash
SHUNT_MIN_LINES=5000   # per-session override
SHUNT_GUARD_OFF=1      # disable the guard entirely
SHUNT_MODEL=...        # model for the subagent; unset = inherit
```
