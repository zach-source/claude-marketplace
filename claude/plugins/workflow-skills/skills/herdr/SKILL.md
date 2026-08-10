---
name: herdr
description: "Control herdr from inside it. Manage workspaces and tabs, split panes, spawn agents, read output, and wait for state changes — all via CLI commands that talk to the running herdr instance over a local unix socket. Use when running inside herdr (HERDR_ENV=1)."
---

# herdr — agent multiplexer self-control

Before using this skill, verify `HERDR_ENV=1`. If unset, you're not operating within a herdr-managed pane — do not attempt external control.

You operate inside herdr, a terminal-native agent multiplexer offering workspaces, tabs, and panes. Each pane functions as an independent terminal with its own shell or process.

**Capabilities:**
- Observing other panes and agents
- Creating tabs for separate subcontexts
- Splitting panes and executing commands
- Running servers, monitoring logs, executing tests in sibling panes
- Blocking until specific output appears
- Waiting for other agents to complete
- Spawning additional agent instances

The `herdr` binary provides workspace, tab, pane, and wait commands via local unix socket communication.

## concepts

**Workspaces** represent project contexts containing one or more tabs. **Tabs** are subcontexts within workspaces, each containing panes. **Panes** are terminal splits running independent processes. **Agent status** is auto-detected by herdr: `idle`, `working`, `blocked`, `done`, `unknown`. **IDs** are session-specific (workspaces: `1`, `2`; tabs: `1:1`, `1:2`; panes: `1-1`, `1-2`). IDs can compact when tabs, panes, or workspaces are closed — do not treat them as durable.

## discover yourself

```bash
herdr pane list
herdr workspace list
```

## tab management

```bash
herdr tab list --workspace 1
herdr tab create --workspace 1
herdr tab create --workspace 1 --label "logs"
herdr tab rename 1:2 "logs"
herdr tab focus 1:2
herdr tab close 1:2
```

## read another pane

```bash
herdr pane read 1-1 --source recent --lines 50
```

Options: `--source visible`, `--source recent`, `--source recent-unwrapped`

## split a pane and run a command

```bash
herdr pane split 1-2 --direction right --no-focus
NEW_PANE=$(herdr pane split 1-2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
herdr pane split 1-2 --direction down --no-focus
```

## wait for output

```bash
herdr wait output 1-3 --match "ready on port 3000" --timeout 30000
herdr wait output 1-3 --match "server.*ready" --regex --timeout 30000
```

## wait for an agent status

```bash
herdr wait agent-status 1-1 --status done --timeout 60000
```

## send text or keys to a pane

```bash
herdr pane send-text 1-1 "hello from the agent"
herdr pane send-keys 1-1 Enter
herdr pane run 1-1 "echo hello"
```

## workspace management

Always **prefix a new workspace's label with the launching project's name** (the
basename of the repo/cwd it's created from) so spaces from different projects stay
grouped and distinguishable in the sidebar — `nix/api`, `ripple/db`, etc.

```bash
PROJECT=$(basename "$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")")
herdr workspace create --cwd /path/to/project --label "$PROJECT/api server"
herdr workspace create --cwd /path/to/project          # cwd-named (no label)
herdr workspace create --no-focus
herdr workspace focus 2
herdr workspace rename 1 "$PROJECT/api server"
herdr workspace close 2
```

## worktree isolation (segregate work)

To keep parallel or autonomous work off your main checkout, herdr can create a git
worktree **and a workspace bound to it in one step**. Each worktree is an isolated
branch + checkout (default under `~/.herdr/worktrees/<repo>/<branch>`), so sibling
agents never touch each other's files or your working tree. Prefer this over a bare
`herdr workspace create` whenever a task should live on its own branch.

```bash
# New branch + worktree + workspace, from inside the repo:
herdr worktree create --cwd "$PWD" --branch feat/api --no-focus --json
#   --base main    branch point (default: current HEAD; use origin/main to start current)
#   --path PATH    override checkout location
#   --label TEXT   workspace label (default: branch name)

herdr worktree open --cwd "$PWD" --branch feat/api --no-focus   # re-open an existing worktree as a workspace
herdr worktree list --cwd "$PWD" --json                          # worktrees for this repo
herdr worktree remove --workspace <WS_ID> --force                # tear down worktree + its workspace
```

`worktree create` returns the new `result.workspace.workspace_id`,
`result.root_pane.pane_id`, and `result.worktree.path` — parse these to drive the
isolated workspace. `worktree remove` deletes the checkout and closes the workspace
but leaves the branch (delete it with `git branch -d` once merged).

**Segregate a task into its own worktree + agent:**
```bash
# 1. isolate: new branch/worktree/workspace, capture ids
J=$(herdr worktree create --cwd "$PWD" --branch feat/api --base origin/main --no-focus --json)
WS=$(echo "$J" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"])')
PANE=$(echo "$J" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')
# 2. run an agent in the isolated checkout
herdr pane run "$PANE" "claude-smart --new"
herdr wait output "$PANE" --match ">" --timeout 15000
herdr pane run "$PANE" "implement the feature on this branch, then commit"
# 3. when merged, tear down (branch stays for git branch -d)
herdr worktree remove --workspace "$WS" --force
```

## close a pane

```bash
herdr pane close 1-3
```

## recipes

**Run a server and wait until it is ready:**
```bash
NEW_PANE=$(herdr pane split 1-2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
herdr wait output "$NEW_PANE" --match "ready" --timeout 30000
herdr pane read "$NEW_PANE" --source recent --lines 20
```

**Run tests in a separate pane and inspect the result:**
```bash
herdr pane split 1-2 --direction down --no-focus
herdr pane run 1-3 "cargo test"
herdr wait output 1-3 --match "test result" --timeout 60000
herdr pane read 1-3 --source recent --lines 30
```

**Check what another agent is working on:**
```bash
herdr pane list
herdr pane read 1-1 --source recent --lines 80
```

**Watch another pane robustly:**
```bash
herdr pane read 1-3 --source recent --lines 40
herdr wait output 1-3 --match "ready" --timeout 30000
herdr pane read 1-3 --source recent-unwrapped --lines 40
```

**Spawn a new agent and give it a task:**

Launch with `claude-smart`, not bare `claude` — it's the same wrapper your own
session uses, so the spawned agent inherits the full setup: strict MCP config
(`~/.claude/mcp_servers.json` + project-local `.mcp.json`), the default Opus model,
and the workflow / agent-team / persistent-loop env. `--new` forces a fresh
conversation (without it, claude-smart auto-resumes the most recent session for the
cwd — wrong for a sibling in this shared checkout). `--no-channels` skips the mailbox
channel (auto-on when `mailbox` is configured) and its startup warning dialog — a quick
supervised helper doesn't need peer messaging, and the dialog would break the `>` wait.

```bash
herdr pane split 1-2 --direction right --no-focus
herdr pane run 1-3 "claude-smart --new --no-channels"
herdr wait output 1-3 --match ">" --timeout 15000
herdr pane run 1-3 "review the test coverage in src/api/"
```

**If you want channels on this spawn** (peer messaging), drop `--no-channels`.
claude-smart then loads the mailbox channel via a research-preview dev flag that shows
a **dev-channels warning dialog before the prompt appears** — it is NOT suppressible by
any config, so the launching agent must read and dismiss it before you `wait output`.

**Handle it one dialog at a time: `pane read` → decide → send ONE key → `pane read` to
confirm it advanced.** Never fire a timed `send-keys Enter` loop and never assume the
highlighted default is safe — a stray Enter has been observed landing on **"No, exit"**,
killing claude-smart back to the shell. If that happens, clear the leftover input line
with `herdr pane send-keys <pane> ctrl+u` (herdr syntax — `C-u` is rejected) before
relaunching. See the **herdr-claude-loop** skill step 2b for the full sequence.

> A sibling pane shares this checkout — fine for a quick, supervised helper. For an
> **autonomous/async `/loop`**, never run it in the shared checkout: isolate it with
> `herdr worktree create` (see **worktree isolation** above) and launch the loop in
> that workspace, and have it commit and push main when done. See the
> **herdr-claude-loop** skill for the full procedure.

**Coordinate with another agent:**
```bash
herdr wait agent-status 1-1 --status done --timeout 120000
herdr pane read 1-1 --source recent --lines 100
```

## notes

- JSON output: `workspace list`, `workspace create`, `tab list`, `tab create`, `tab get`, `tab focus`, `tab rename`, `tab close`, `pane list`, `pane get`, `pane split`, `wait output`, `wait agent-status`
- `pane read` outputs text
- `pane read --format ansi` or `--ansi` returns ANSI-rendered snapshots
- `pane send-text`, `pane send-keys`, `pane run` produce no output on success
- Parse new IDs from responses: `workspace create` returns `result.workspace`, `result.tab`, `result.root_pane`; `tab create` returns `result.tab`, `result.root_pane`; `pane split` returns the new pane at `result.pane.pane_id`
- Use `pane read` for existing output; use `wait output` for anticipated future output
- `--no-focus` maintains your current terminal context
- Default naming: workspaces use cwd-based names; tabs use numbered names; `--label` applies custom names immediately. When you supply `--label` for a new workspace, prefix it with the launching project's name (`<project>/<label>`, project = basename of the repo/cwd)
- Environment variable `HERDR_ENV=1` indicates a herdr execution context
