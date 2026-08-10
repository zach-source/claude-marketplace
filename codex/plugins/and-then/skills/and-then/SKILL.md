---
name: and-then
description: "Queue up a sequence of tasks that run one after another in this session, with optional parallel fork steps farmed out to subagents. The Stop hook auto-advances the queue whenever the assistant outputs <done/>. Use when the user asks to line up several tasks, run a list of things back to back, fan work out in parallel then continue, or asks about queue status/skip/cancel. Triggers on: and-then, task queue, queue these tasks, run these in order, then do, fork these subtasks, and-then-status, and-then-skip, and-then-cancel."
---

# and-then — sequential task queue

A queue lives in `.claude/and-then-queue.json` under the session's working
directory. A `Stop` hook reads it every time a turn ends: if the last assistant
message contained `<done/>`, the queue advances and feeds the next task back in;
otherwise the current task is re-fed. When the last task completes the queue file
is deleted and the session is allowed to exit normally.

Codex plugins have no slash commands, so drive the queue by running these scripts
directly with Bash.

## Creating a queue

```bash
${PLUGIN_ROOT}/scripts/setup-and-then.sh --task "Build API" --task "Write tests" --task "Deploy"
```

| Flag | Short | Meaning |
|---|---|---|
| `--task` | `-t` | A standard task, run sequentially |
| `--fork` | `-f` | A fork task; every following bare argument is a subtask run in parallel via subagents |
| `--workers N` | `-w N` | Cap concurrent subagents on the preceding `--fork` (default: all at once) |

Fork steps, all at once and rate-limited:

```bash
${PLUGIN_ROOT}/scripts/setup-and-then.sh --fork "Unit tests" "Integration tests" "E2E tests"
${PLUGIN_ROOT}/scripts/setup-and-then.sh --fork --workers 2 "Task A" "Task B" "Task C" "Task D"
```

Mixed sequential and parallel:

```bash
${PLUGIN_ROOT}/scripts/setup-and-then.sh \
  --task "Build API" \
  --fork --workers 3 "Test 1" "Test 2" "Test 3" "Test 4" \
  --task "Deploy to staging"
```

## Managing a running queue

```bash
${PLUGIN_ROOT}/scripts/and-then-add.sh --task "Another task"   # append, even mid-run
${PLUGIN_ROOT}/scripts/and-then-status.sh                      # progress + remaining tasks
${PLUGIN_ROOT}/scripts/and-then-skip.sh                        # abandon current, move to next
rm .claude/and-then-queue.json                                 # cancel the whole queue
```

## Signalling completion

The queue only moves when a turn ends with `<done/>` (or `<done></done>`) in the
assistant message. Emit it once the current task is genuinely finished — not
before, or the next task starts on top of unfinished work. For a fork task, wait
for every subagent to return and summarise their results first, then emit
`<done/>`.
