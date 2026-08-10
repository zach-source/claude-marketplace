# Pi Extensions

TypeScript ports of the Claude Code hooks in [`claude/`](../claude), for the
[Pi coding agent](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent).

## Pi has no plugin format

The other two trees in this repo package things: `claude/plugins/<name>/` has a
`.claude-plugin/plugin.json`, `codex/plugins/<name>/` has its own manifest. Pi
has neither. A Pi extension is a single `.ts` module with a default export that
receives an `ExtensionAPI`, dropped into `~/.pi/agent/extensions/`:

```ts
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    /* ... */
  });
}
```

That is the whole contract. No manifest, no marketplace entry, no grouping into
plugins — so this tree is a flat directory of extensions, and the plugin names
the Claude tree uses (`code-quality`, `context-injection`, …) appear here only
as the "Claude plugin" column below.

Deployment is by [`pi.nix`](https://github.com/zach-source/dotfiles) — one
`home.file.".pi/agent/extensions/<name>.ts"` entry per file, same as the
extensions from the `pi-agent-extensions` flake input.

## What ported

| Extension            | Claude hook              | Claude plugin     | Pi events            |
| -------------------- | ------------------------ | ----------------- | -------------------- |
| `smart-lint.ts`      | `smart-lint.sh`          | code-quality      | `tool_result`        |
| `project-docs.ts`    | `inject_project_docs.py` | context-injection | `before_agent_start` |
| `working-context.ts` | `inject-context.py`      | context-injection | `before_agent_start` |
| `detect-library.ts`  | `detect-library-hook.py` | context-injection | `before_agent_start` |
| `cache-staleness.ts` | `session-staleness.py`   | session-hygiene   | `input`, `turn_end`  |
| `notify.ts`          | `notify-hook.sh` (Stop)  | notifications     | `agent_end`          |
| `follow-mode.ts`     | `follow-mode-notify.sh`  | — (nvim plugin)   | `tool_result`        |

Three of these do the job better in Pi than the hook could:

- **`smart-lint.ts`** — a PostToolUse hook can only write to stderr and exit 2
  and hope the harness surfaces it. `tool_result` handlers return
  `{ content }`, so the lint failure is appended to the tool result the model
  actually reads. It does not set `isError`: the write succeeded, and saying
  otherwise would be a lie the model has to work around.
- **`project-docs.ts`** — the Python hook re-injects STATUS.md, TASKS.md and
  SESSION_HISTORY.md into _every_ prompt. Pi's injected message persists in the
  session, so this re-injects only when the content changed.
- **`cache-staleness.ts`** — most of `session-staleness.py` exists because a
  Claude hook cannot trigger compaction: it refuses the prompt, and inside herdr
  it types `/compact` into the pane and replays the prompt by hand. Pi has
  `ctx.compact({ onComplete })` and `pi.sendUserMessage()`, so the workaround
  collapses to compact-then-resend. **Off by default** — see below.

### Notes on individual ports

`working-context.ts` reads `~/.claude/contexts/<project-id>.json`, the store
Claude's `/prompt:context` writes, and does not write to it. Which cluster and
which AWS profile you are pointed at is a fact about the machine, not about the
harness; a second writer in the same format would only drift.

`detect-library.ts` checks `pi.getActiveTools()` and stays silent unless a docs
tool is actually loaded. The Claude hook hardcodes `mcp__context7__*`; Pi's tool
set is whatever `mcp-server.ts` discovered from `~/.pi/mcp.json`, which on this
machine is headroom only. Telling a model to call a tool it does not have is
worse than saying nothing.

`cache-staleness.ts` is opt-in via `PI_STALE_AUTOCOMPACT=1`. The upstream hook's
1-hour TTL was verified against real Claude Code transcripts
(`ephemeral_1h_input_tokens`); Pi is multi-provider and the default model here is
`codex-5.3`, so that number carries no authority. Set `PI_CACHE_TTL_SECONDS` to
the cache TTL of the model you actually run before turning it on.

`follow-mode.ts` sends the nvim plugin's own script a Claude-shaped payload on
purpose. The socket path, line-finding and nvim remote calls all live in
`follow-mode-notify.sh`, and it already accepts `.tool_input.path` — which is
exactly Pi's field name.

## What does not port

Stated plainly, because a fake port is worse than an honest gap.

**No Pi event exists.**

- **`subagent-stop-hook.sh`** (SubagentStop) — Pi has no subagents. Nothing in
  the `ExtensionEvent` union fires for one, so there is nothing to hook.
- **`notify-hook.sh`, Notification half** — Claude's Notification event means
  "the agent is blocked waiting for permission or input". Pi asks through
  `ctx.ui.confirm()` / `select()` / `input()`, which is in-band in the TUI. The
  Stop half is ported; this half has no trigger. (The `notifications` plugin's
  `claude-statusline.sh` is a different shape again: Pi builds its footer from
  `ctx.ui.setStatus()` / `setFooter()` components, not from a script fed session
  JSON on stdin.)

**Claude-specific plumbing.**

- **`sync-mcp-servers.sh`** — strips `mcpServers` from `~/.claude.json` so it
  stops shadowing `~/.claude/mcp_servers.json`. Pi reads `~/.pi/mcp.json` through
  the `mcp-server.ts` extension and has no shadowing problem to fix.
- **`ccswitch autoswitch`** (SessionStart) — rotates Claude Code OAuth accounts.
  Pi authenticates via its own `/login` and does not read Claude's credential
  store.
- **`claude-mon-hook.sh`** — streams edits to the claude-mon TUI and daemon over
  a cwd-hashed unix socket, in Claude's `tool_input` schema. A Pi session writing
  to it would show up as a phantom Claude session in someone else's monitor.
- **`bd prime --hook-json`** (SessionStart) — ports mechanically, but Pi's
  `SYSTEM.md` uses Graphiti rather than beads, and the `graphiti.ts` extension
  already primes memory at session start. It would be dead weight.

**Ports mechanically, but the port would be wrong.**

- **`remember-dir.sh`** (PreToolUse Bash) — logs `cd` out of bash commands to
  `~/.claude/sessions/<id>/directory-history.md` and `current-dir.md`. Pi's bash
  tool is built with a fixed `cwd` (`createBashToolDefinition(cwd, …)`) and every
  command runs in it, so a `cd` in one call has no effect on the next. The log
  would faithfully record directories Pi is not in. Extensions that want the
  working directory read `ctx.cwd`.
- **`context-manager.py`** — the CLI _writer_ behind `/prompt:context`, not a
  hook. `working-context.ts` reads what it writes; adding a second writer in the
  same format is how the two stores drift apart.
- **vector-memory** (`precompact_vectorize`, `retrieve_vectors`,
  `qdrant_utils`) — the events line up (`session_before_compact`, `tool_call`),
  so this is a mechanical port. But it is commented out in `claude-hooks.nix`, and
  Pi already ships `custom-compaction.ts` (context preservation across
  compaction, Graphiti-backed) and `graphiti.ts`. Porting dead code to duplicate
  a live system is not an improvement.

**Already exists upstream** — in
[`pi-agent-extensions`](https://github.com/zach-source/pi-agent-extensions), not
duplicated here:

- **`dangerous-command-blocker`** → `permission-gate.ts` (blocks destructive
  bash via `tool_call` returning `{ block: true, reason }`).
- **`herdr-agent-state.sh`** (SessionStart) → `herdr-agent-state.ts`.

## Typecheck

```sh
./typecheck.sh
```

Resolves the installed pi package and runs `tsc` against its real `.d.ts`. The
npm package has been renamed twice (`@mariozechner/pi-coding-agent` →
`@earendil-works/pi-coding-agent`, plus the `@oh-my-pi` fork) while extensions
still import the original name, so the path is discovered at runtime rather than
pinned in `tsconfig.json`. `@types/node` comes transitively from the pi install —
the same Node types the extensions run against.
