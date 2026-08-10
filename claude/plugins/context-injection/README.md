# context-injection

Puts the things Claude keeps forgetting into every prompt.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| UserPromptSubmit | `inject_project_docs.sh` → `.py` | Injects `STATUS.md` / `TASKS.md` / `SESSION_HISTORY.md` so they get read before work starts |
| UserPromptSubmit | `detect-library-hook.py` | Spots external library mentions and nudges toward the `context7` skill |
| UserPromptSubmit | `inject-context.py` | Injects working context — k8s cluster/namespace, AWS profile/region, env vars, custom notes |
| PreToolUse (`Bash`) | `remember-dir.sh` | Reminds Claude which directory it is actually in |

## Working context

`scripts/context-manager.py` is the state store behind `inject-context.py`, and the
backend for the `/prompt:context` command in the **slash-commands** plugin. Context is
per-project, keyed on git root (or cwd).

```bash
python3 scripts/context-manager.py view
python3 scripts/context-manager.py set k8s prod-cluster api
python3 scripts/context-manager.py set aws production us-west-2
python3 scripts/context-manager.py clear all
```

## Requirements

`python3`, `jq`. Everything degrades to a no-op when the inputs are absent — no project
docs, no injection.

## Output contract

`inject_project_docs.py` emits `hookSpecificOutput.additionalContext`, and nothing at all
when there is nothing to inject.

It used to rewrite `payload["prompt"]` and print the whole payload back, on the assumption
that a hook is a filter the harness pipes the payload through. It isn't. UserPromptSubmit
adds a hook's raw stdout to the context, so that dumped the entire JSON envelope —
`session_id`, `cwd`, every tool field — into the conversation on **every prompt**, and did
it even with no project docs present. The documents reached the model only incidentally,
buried in a `prompt` key nothing reads back.

Covered by `bash claude/test-hook-contract.sh` at the repo root, which asserts no hook
echoes its input envelope back.
