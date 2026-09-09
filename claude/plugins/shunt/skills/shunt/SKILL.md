---
name: shunt
description: "Shunt I/O-heavy work off the main context onto a cheap subagent — reading large files, answering questions spanning several files, summarizing big diffs, generating boilerplate from a reference. Use when a file is over ~800 lines, when a question spans 3+ files, or when the shunt-guard PreToolUse hook denies a read. Triggers on: shunt, bulk read, large file, delegate the read, too many tokens, context is filling up, read these files, summarize this diff, generate boilerplate."
---

# shunt — send bulk I/O to a cheap model

Reading a 4,000-line file costs ~33k tokens of *your* context and you keep paying for it
every turn afterwards. A subagent reads it in its own context and hands back an answer
measured in hundreds of tokens. The files never enter this conversation.

This skill is your standing authorization to spawn subagents for the cases below. You do
not need to ask first.

## When to shunt

- Any file over ~800 lines you want to understand rather than edit.
- A question that spans 3+ files ("where is auth enforced?", "which handlers touch the DB?").
- Summarizing a large diff or log.
- Boilerplate: tests, config, type stubs, docstrings — anything >80% predictable from a
  reference file that already exists in the repo.

## When NOT to shunt

- **Editing.** An edit needs the exact bytes in your context. Read the span you need with
  `Read` + offset/limit, or `sed -n 'A,Bp'`. Never edit from a summary.
- **Debugging.** You need the reasoning, not a précis of it. Keep it local.
- **Small files.** Under the threshold the round-trip costs more than it saves.
- **Architecture and judgment calls.** Those are why you are the one being asked.

## How

Use the `Explore` agent for search-shaped questions ("find every place that…"), and the
`Agent` tool with `model: haiku` for read-shaped ones. Name the exact paths and the exact
question; a vague brief comes back as a vague summary you then have to re-derive.

```
Agent(model: haiku, prompt: "Read src/Service.java and src/Handler.java.
List every method that opens a DB connection, as `file:line — method — what it does`.
Bullets only, no prose.")
```

For boilerplate, use `model: sonnet` and give it the reference file plus the target path.
Generation is execution-tier work; reading is not.

Those two tiers are defaults. If `SHUNT_MODEL` is set, pass that instead — the guard names
it in its denial, so you do not have to check the environment yourself.

## Verify before you act on it

A summary is evidence, not fact. Before you edit based on a shunted read, confirm the
specific line numbers and identifiers you are about to touch — one targeted `Read` with
offset/limit, or a `grep`. Cheap models transpose line numbers.

## The guard

This plugin's `PreToolUse` hook denies whole-file reads over `SHUNT_MIN_LINES` (default
800), for `Read` and for `cat`/`head`/`bat`/`less` in the shell. It allows targeted reads,
pipes, and redirects. If it denies something you genuinely need whole, either read it in
spans or raise the threshold for the session:

```bash
SHUNT_MIN_LINES=5000   # per-session override
SHUNT_GUARD_OFF=1      # disable the guard entirely
SHUNT_MODEL=...        # model for the subagent; unset = inherit
```
