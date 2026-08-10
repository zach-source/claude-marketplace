# Codex plugins

Codex mirrors of the plugins in [`../claude/plugins`](../claude/plugins), following
the [Codex plugin format](https://developers.openai.com/plugins/build/plugins).

```
codex/
├── plugins/<name>/
│   ├── .codex-plugin/plugin.json   # required, and the only file in this directory
│   ├── skills/<skill>/SKILL.md
│   ├── hooks/hooks.json + hooks/scripts/
│   └── scripts/
├── validate-plugins.py
└── test-and-then-stop-hook.sh
```

The marketplace lives at [`../.agents/plugins/marketplace.json`](../.agents/plugins/marketplace.json).
The Claude tree owns `.claude-plugin/marketplace.json`; Codex reads either path, so
the two harnesses stay out of each other's way.

| Plugin | Category | Components |
|--------|----------|------------|
| [and-then](./plugins/and-then) | Productivity | Stop hook, `and-then` skill, scripts |
| [code-quality](./plugins/code-quality) | Developer Tools | PostToolUse hook |
| [context-injection](./plugins/context-injection) | Productivity | UserPromptSubmit + PreToolUse hooks |
| [notifications](./plugins/notifications) | Productivity | Stop, SubagentStop, PostToolUse hooks |
| [session-hygiene](./plugins/session-hygiene) | Developer Tools | UserPromptSubmit hook |
| [vector-memory](./plugins/vector-memory) | Productivity | PreCompact + PreToolUse hooks |
| [workflow-skills](./plugins/workflow-skills) | Productivity | 4 skills |

## How these differ from the Claude plugins

Format differences applied to every plugin:

- Manifest is `.codex-plugin/plugin.json` and points at `skills/` and
  `hooks/hooks.json` explicitly — Codex does not auto-discover components.
- `hooks/hooks.json` wraps its event map in a top-level `hooks` object.
- `${CLAUDE_PLUGIN_ROOT}` becomes `${PLUGIN_ROOT}`. Codex sets the `CLAUDE_`
  names too, but only as compatibility aliases.

Behavioural differences, per plugin:

- **notifications** drops its `Notification` hook. Codex has eleven hook events
  and `Notification` is not among them.
- **and-then** reads `last_assistant_message` off the Stop payload rather than
  walking `transcript_path`. Not just tidier: the transcript scan matched a
  top-level `.role` that no transcript actually contains, so `<done/>` was never
  detected and the queue re-fed task 1 forever. Reading the payload also avoids a
  race, since transcript writes are async and may not include the turn that
  triggered the hook. A `stop_hook_active` guard bounds the re-feed, because an
  unconditional `decision:"block"` is exactly how a Stop hook loops. Its slash
  commands became a skill, since Codex plugins have no commands.
- **vector-memory** extracts the query from `tool_input` itself and rewraps the
  result as `hookSpecificOutput.additionalContext`. `claude-vector` reads its
  query from `tool`/`arguments`, which no harness sends, and prints
  `{"role","content"}`, which is no harness's hook protocol. Both ends were
  broken, so the hook exited 0 while retrieving nothing and injecting nothing.
  Fixed in the wrapper rather than the CLI, which is nix-managed and shared with
  the Claude tree.
- **session-hygiene** drops `scripts/sync-mcp-servers.sh`, which rewrites
  `~/.claude.json`. It is wired to no hook, and editing another harness's config
  is the only thing it could do from here.

## Tool names

Codex's tool vocabulary is not Claude Code's, and the difference is easy to miss
because it fails quietly rather than loudly:

- File edits are **`apply_patch`**. `Edit` and `Write` work in a `matcher`, which
  is a regex over the tool name plus its aliases, but the payload always reports
  `tool_name: "apply_patch"` — so a script that compares `.tool_name` against
  `Write` or `Edit` never matches.
- `apply_patch` has no structured file-path field. The entire patch arrives as one
  string in `tool_input.command`, so `code-quality` and `notifications` read the
  edited path off the `*** Update File:` envelope, keeping `.tool_input.file_path`
  as a fallback.
- Shell is **`Bash`** (covering `exec_command`), subagents are **`Agent`**, and MCP
  tools are namespaced `mcp__<server>__<tool>`. `Read`, `Grep`, `Glob`, `Task` and
  `MultiEdit` do not exist, so `vector-memory`'s matcher is
  `Bash|Edit|Write|apply_patch|Agent` and the edit matchers are
  `Write|Edit|apply_patch`.

## Reading payload fields

`tool_input` and `tool_response` are documented only as "tool-specific" — their
shape is not guaranteed, and `tool_response` is measurably not always an object.
This matters more than it looks, because **indexing a non-object is a jq error
that aborts the whole expression before any `//` fallback runs**. The classic
shape is:

```jq
.tool_response.filePath // .tool_input.file_path // empty   # throws away the fallback
```

When `tool_response` is a string, that raises rather than falling through, so the
correct path sitting in `tool_input` is discarded and the hook exits 0 having done
nothing. Guard every access by type instead:

```jq
[ (.tool_response? | objects | .filePath?),
  (.tool_input?    | objects | .file_path?) ]
| map(select(type == "string" and . != "")) | first // ""
```

Hooks also receive their payload **on stdin as JSON**. There is no environment
variable carrying it — `claude-mon-hook.sh` read `$TOOL_INPUT`/`$TOOL_NAME` from
the environment, which nothing sets, so it streamed empty records and never
resolved a path.

## Writing to stdout

A hook's stdout *is* its result: the harness parses it. Two consequences that are
easy to get wrong, and that `test-hook-stdout-contract.sh` exists to catch.

**`block` is the only valid `decision`.** Omitting the field is how a hook allows;
there is no `"approve"`. Both notify hooks used to end with
`{"decision":"approve","suppressOutput":true}`, which failed validation on every
invocation.

**Anything a hook runs inherits that stdout.** Redirect *both* streams of every
helper — `>/dev/null 2>&1`, not `2>/dev/null`. `terminal-notifier` writes
"Removing previously sent notification…" to **stdout** when it replaces one, and
`nc` hands back whatever a daemon replies, either of which corrupts the JSON or,
worse, could be read as a decision. `2>/dev/null` looks like silencing and is not.

The inverse mistake is `checker 2>&1`, which *merges* a linter's diagnostics into
stdout rather than suppressing them. Send them the other way, `checker >&2`. The
go, black, rustfmt and nixfmt branches of `smart-lint.sh` all had this.

**A hook is not a filter.** The payload is not piped through it, so there is no
reason to echo it back. `inject_project_docs.py` rewrote `payload["prompt"]` and
printed the whole envelope, which on `UserPromptSubmit` — where stdout *becomes*
context — dumped `session_id`, `cwd` and every other field into the conversation
on every prompt, while the documents themselves reached the model only
incidentally, inside a `prompt` key nothing reads back. Emit
`hookSpecificOutput.additionalContext`, or nothing.

Not mirrored: `slash-commands` and `subagents`. Codex plugins have no commands or
agents component, and both plugins are nothing but those.

`code-quality` still formats and lints on `PostToolUse`, but Codex only documents
exit-2-with-stderr blocking for `PreToolUse` and `UserPromptSubmit`, so lint
failures may surface less loudly than under Claude Code.

## Checks

```bash
python3 codex/validate-plugins.py        # manifests, component paths, skills, marketplace
bash codex/test-and-then-stop-hook.sh    # and-then queue advance logic
bash codex/test-tool-payload-hooks.sh    # apply_patch handling, PreToolUse context rewrap
bash codex/test-hook-stdout-contract.sh  # every hook's stdout stays a valid result
```

`test-hook-stdout-contract.sh` discovers hooks from the `hooks.json` files rather
than a hardcoded list, so it covers new hooks automatically. It runs each one
against stub helpers that are deliberately noisy on both streams — including
checkers that always fail, since a checker only writes when it finds something and
a clean fixture proves nothing. Tool events are replayed once per file type
(`.go .py .ts .rs .yaml .nix`), because a single fixture leaves every other
per-extension branch covered by no test at all. It asserts three things about
stdout:

1. **parseable** — catches helper chatter and `checker 2>&1`.
2. **no unmeant control keys** — no `decision` other than `block`.
3. **no input-envelope keys** at top level (`session_id`, `cwd`, `tool_input`, …)
   — catches a hook written as a filter. This one is valid JSON with no bad
   control keys, so the first two miss it entirely.
4. **no keys outside the documented result fields** — catches innocuous-looking
   output nobody meant to emit. A daemon replying `{"status":"ok"}` down an `nc`
   pipe passes all three checks above; only this one sees it. Benign is not the
   same as guarded.

That contract is worth more than a test per bug: it caught the `PreCompact` leak
in a plugin nobody was looking at.

Every fix here was confirmed by reverting it and watching the suite go red on the
expected line. Reverting all four `2>&1` sites fails exactly `.go`, `.py`, `.rs`
and `.nix`, leaving `.ts` and `.yaml` green — `prettier` and `yq` were already
correct. A check that has never failed is not evidence that it works.

`validate-plugins.py` checks that every manifest parses, carries the required
`name`/`version`/`description`, uses a kebab-case name matching its directory,
keeps `.codex-plugin/` free of anything but `plugin.json`, and that each component
pointer starts with `./` and resolves inside the plugin root. It also checks the
marketplace lists exactly the plugins present on disk, with the required
`policy.installation`, `policy.authentication` and `category` on each entry.

## What is measured, what is only read

The green counts above do not distinguish between "checked against reality" and
"checked against the documentation", so state it plainly.

**The overriding caveat: none of this has been run under Codex itself.** Every
payload the suites feed is synthesised from the docs. The suites prove these hooks
behave correctly *given* the documented contract; they cannot prove the contract.

**Measured** — observed against something real:

- `claude-vector` emits `{"role","content"}` and reads its query from
  `tool`/`arguments`: read from its source and run.
- The claude-mon daemon replies `{"status":"ok"}` to an edit record: sent one over
  the real socket. That is also exactly what leaks onto a hook's stdout without the
  redirect — the leak is observed, not theorised.
- Everything the suites assert about these scripts' own behaviour.

**Documented, not observed** — taken from the hook and plugin references:

- the eleven hook events, and the absence of `Notification`
- `decision:"block"` meaning *continue* on Stop/SubagentStop, and `stop_hook_active`
- **`last_assistant_message` on the Stop payload** — load-bearing for `and-then`,
  and never seen in a captured live payload; the tests synthesise it
- tool names (`apply_patch`, `Bash`, `Agent`), `Edit`/`Write` being matcher aliases
  while `tool_name` still reports `apply_patch`, and `tool_input.command` carrying
  the patch
- `hookSpecificOutput.additionalContext` being the only channel to the model on
  `PreToolUse`, and `PLUGIN_ROOT`

**Inferred** — neither observed nor documented:

- **The `apply_patch` envelope format.** The docs say only that `tool_input.command`
  is a string; the `*** Update File:` parsing in `smart-lint.sh` and
  `claude-mon-hook.sh` comes from the format's conventional shape. If it is wrong,
  both degrade to the no-op they had before rather than misbehaving.
- The allowed result-key list in `test-hook-stdout-contract.sh` is assembled from
  the documented output fields. A legitimate field not in that list would show up as
  a false failure, not a missed bug.

## Installing

Codex copies plugins into `~/.codex/plugins/cache/$MARKETPLACE/$PLUGIN/$VERSION/`
and loads from there, so edits need a re-copy and a restart. Enabling a plugin
does not trust its hooks — hooks stay inactive until reviewed and trusted.
