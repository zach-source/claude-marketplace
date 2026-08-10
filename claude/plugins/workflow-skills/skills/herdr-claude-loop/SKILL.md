---
name: herdr-claude-loop
description: "Fan out autonomous Claude /loop sessions across git worktrees, one per epic/task, using herdr. Use when you have a set of independent work items (beads epics, issues, PRs) and want each driven by its own self-paced Claude session in an isolated worktree + herdr workspace. Triggers on: launch subsessions per epic, parallelize epics, one worktree per task, herdr claude loop, fan out agents on worktrees."
---

# herdr-claude-loop — one autonomous Claude /loop per worktree

Spawn N isolated, autonomous Claude sessions — each in its own git worktree and
herdr workspace, each running a self-paced `/loop` scoped to exactly one work item
(a beads epic, an issue, a PR). Use for parallel feature work where items are
independent enough to live on separate branches.

**Preconditions (verify first):**
- `HERDR_ENV=1` (you're inside herdr). If unset, stop — you can't drive panes.
- You're in a git repo with a clean-ish main and a remote (`origin/main`).
- The work items exist and are addressable (e.g. `bd show <id>` works).

**Non-negotiable rules for async loops:**
- **Always isolate each async loop in its own git worktree** — never start an
  autonomous `/loop` directly in the main working tree or a shared checkout.
  Worktrees keep loops from clobbering each other and your checkout.
- **Commit and push main when done.** A finished loop must land its work on main
  and push `origin main` (step 6) — not leave it stranded on a worktree branch.

> Cost warning: each session is a full autonomous Claude instance that may
> auto-edit, commit, push, and (if configured) auto-merge. Launching 8+ at once is
> heavy and, when items touch overlapping files, produces merge conflicts the loops
> must rebase through. Prefer the most-independent items; confirm the count with the
> user before launching many.

## procedure

### 1. Create one worktree + workspace per item

Use herdr's native `worktree create` — it makes the git worktree **and** the
workspace bound to it in one step (checkout lands under
`~/.herdr/worktrees/<repo>/<branch>`), so you never hand-manage `git worktree add`
paths. Branch off `origin/main` (`--base`) so every session starts current; run the
fetch with **`git -C <MAIN_REPO>` and ABSOLUTE paths** (a `cd` + relative-path batch
is brittle and has been observed to fail mid-loop).

Pass `--cwd` = the **main repo dir** (your current directory, `$M`) — NOT the worktree
checkout path. herdr groups the new worktree workspace under that repo in the browser
bar, so all of a repo's loops nest together under the parent instead of scattering as
loose top-level entries.

```bash
M=/abs/path/to/repo
PROJECT=$(basename "$(git -C "$M" rev-parse --show-toplevel)")   # workspace label prefix
git -C "$M" fetch origin --quiet
OUT=$(herdr worktree create --cwd "$M" --branch epic/<id>-<slug> --base origin/main \
  --no-focus --label "$PROJECT/<id>" --json)
RP=$(echo "$OUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')
WS=$(echo "$OUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["workspace"]["workspace_id"])')
```

`$PROJECT` is the launching repo's name (e.g. `nix`); prefixing the `--label` with it
keeps spaces from different projects grouped in the sidebar (`nix/<id>`, `ripple/<id>`).
Worktrees inherit the parent repo's trust, so Claude will NOT show a "do you trust
this folder?" prompt. Capture `WS` (workspace id) now — teardown needs it.

### 2. Launch Claude in the worktree's pane

Launch with `claude-smart --new`, not bare `claude`: it loads the strict
MCP config (`~/.claude/mcp_servers.json` + any project-local `.mcp.json`), the default
Opus model, and — critically for this skill — `CLAUDE_CODE_LOOP_PERSISTENT=1` (so the
`/loop` survives CLI restarts) and `CLAUDE_CODE_WORKFLOWS=1` (dynamic self-paced
`/loop`). `--new` guarantees a fresh session (the worktree is new anyway).

**Mailbox channels load automatically.** claude-smart defaults `--channels` ON whenever
the `mailbox` MCP server is configured, so you no longer pass the flag — these parallel
loops can see and message each other out of the box: a peer session's DM / info-request
/ broadcast pushes in as a `<channel source="mailbox" ...>` event **injected directly
into the idle session** (no polling) instead of being missed. Fanned-out loops working
related items coordinate (announce a shared-file edit, ask a sibling a question) rather
than colliding blind. It costs the startup dialogs dismissed in step 2b; pass
`--no-channels` if you want the loops fully isolated.

The channel launch also writes a `./.mcp.json` in the worktree (mirroring the `mailbox`
entry from `~/.claude/mcp_servers.json`) — the dev-channels resolver only reads standard
`.mcp.json`/`~/.claude.json`, never `--mcp-config`, so this file is what lets the
channel resolve. It's throwaway (the worktree is torn down); no need to commit it.

```bash
herdr pane run "$RP" "claude-smart --new"   # channels auto-load (mailbox configured)
```

### 2b. Dismiss the startup dialogs — ONE AT A TIME, never blind-send Enter

The auto-loaded mailbox channel (claude-smart defaults it on when `mailbox` is
configured) triggers up to three sequential full-screen prompts before the session
loads, and **the session can't start until each is dismissed**. These are NOT
suppressible by any setting — handling them here is mandatory. In order:

1. **Folder trust** — "Is this a project you trust?" (usually skipped in worktrees,
   which inherit the parent repo's trust).
2. **New MCP server consent** — "New MCP server found in this project: mailbox" (from
   the `./.mcp.json` that the channel launch writes).
3. **Development-channels warning** — `--dangerously-load-development-channels` is not
   allowlisted in the research preview.

> ⚠️ **Do NOT fire a timed `for … send-keys Enter; sleep 2` loop.** Observed failure:
> the prompts **raced** — an Enter was sent before the next dialog had rendered, landed
> on a dialog whose default was **"No, exit"**, and **claude-smart exited to the shell**.
> The loop then kept typing into a bare shell. Enter is *not* uniformly safe: the
> highlighted default differs per dialog and across versions, so **never assume option 1**.

**Rules:**
- **Read before every keypress.** Never send a key until a `pane read` shows which
  dialog is actually on screen.
- **Choose explicitly** from what you just read — don't trust a remembered default.
  If the wanted option isn't highlighted, arrow to it (`Up`/`Down`) *then* `Enter`.
- **Re-read after every keypress** to confirm it advanced to the next dialog rather
  than exiting.

Handle them as a judgment loop — one dialog per iteration, reading between each:

```bash
# Repeat until the plain-text version banner appears. Decide each step from the READ,
# do not script the keypresses blind.
herdr pane read "$RP" --source visible --lines 30
#  → identify the dialog and which option is highlighted, then send ONE of:
#      herdr pane send-keys "$RP" Enter            # highlighted option is the one you want
#      herdr pane send-keys "$RP" Up               # move off a destructive default ("No, exit")
#      herdr pane send-text "$RP" "1"              # numbered list: pick explicitly
herdr pane read "$RP" --source visible --lines 30   # confirm it ADVANCED (not exited)
```

**Recovery — claude-smart exited to the shell.** If a read shows a shell prompt instead
of a dialog or the Claude TUI, a stray Enter hit "No, exit". Leftover keystrokes may
still sit on the input line, so **clear it before relaunching** or the next command gets
concatenated onto the garbage:

```bash
herdr pane send-keys "$RP" ctrl+u        # clear the input line
herdr pane run "$RP" "claude-smart --new"
# then work the dialogs again, one read per keypress
```

> herdr key syntax is `ctrl+u` — verified. tmux-style `C-u`/`ctrl-u` are rejected with
> `{"error":{"code":"invalid_key"}}`, which silently leaves the line uncleared.

Confirm the channel actually registered (the eval found `--strict-mcp-config` alone
silently fails): the banner should read `Channels (experimental) messages from
server:mailbox inject directly in this session` **without** a following
`server:mailbox · no MCP server configured with that name` line. If you see that error,
the `./.mcp.json` wasn't written/discovered — the channel is dead and peers can't reach
this loop.

### 3. Wait for Claude to be ready, then send the `/loop` prompt

The TUI's box-drawing defeats most `wait output` regexes, but the startup **version
banner is plain text** — match that, then confirm idle:

```bash
herdr wait output "$RP" --match "Claude Code v" --timeout 40000
herdr wait agent-status "$RP" --status idle --timeout 20000
herdr pane run "$RP" "$LOOP_PROMPT"
```

Scope the prompt to ONE item (no interval = dynamic/self-paced mode). Template:

```
/loop Work only on <item-ref>. First run <how to read it, e.g. bd show ID> to read
the decision/notes and child tasks. Owner decision: <one-line decision to honor>.
Implement and test each task on THIS worktree branch, commit incrementally, run the
project build + tests + lint, open a PR per task and update the tracker. Merges are
approved. When every task is done, make sure all work is committed and merged to
main, then push origin main before going idle. After release, verify on the live
system via logs or e2e. Stay strictly within this item; do not touch others.
```

### 4. CRITICAL gotcha — the prompt may type but not submit

If the prompt is sent while the input box is still initializing, the text lands in
the box but the trailing Enter is swallowed → the pane sits **idle** with an unsent
prompt. Always verify, and press Enter for any that didn't start:

```bash
for p in $PANES; do
  st=$(herdr pane get "$p" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["pane"]["agent_status"])')
  [ "$st" = idle ] && herdr pane send-keys "$p" Enter   # nudge unsent prompts
done
```

### 5. Confirm all sessions are working

```bash
for p in $PANES; do
  printf "%-8s %s\n" "$p" "$(herdr pane get "$p" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["pane"]["agent_status"])')"
done
```

All should read `working`. To inspect one: `herdr pane read <pane> --source visible --lines 30`.

### 6. On completion — commit and push main

A finished loop must land its work on main, not leave it stranded on a worktree
branch. When a session goes `idle`/`done` and its work is verified, ensure main is
current and pushed:

```bash
herdr wait agent-status "$RP" --status done --timeout 600000
# the loop commits/merges its own branch; the orchestrator guarantees main is current:
git -C "$M" fetch origin --quiet
git -C "$M" checkout main && git -C "$M" merge --ff-only epic/<id>-<slug>
git -C "$M" push origin main
```

If `--ff-only` fails (main moved), have the loop rebase its branch onto
`origin/main` and re-merge — never force-push main.

## monitoring & teardown

- Check progress: `herdr pane read <pane> --source recent --lines 60`, or
  `herdr wait agent-status <pane> --status idle` to block until a loop pauses.
- A loop that has finished its item goes `idle`/`done`; read it, then close.
- Tear a session down when its work is merged — `worktree remove` closes the
  workspace and deletes the checkout in one call; the branch stays for `branch -d`:
  ```bash
  herdr worktree remove --workspace "$WS" --force
  git -C "$M" branch -d epic/<id>-<slug>   # -D if not yet merged
  ```

## notes

- Pane/workspace IDs are session-specific and can compact when others close — don't
  hardcode them across runs; re-list with `herdr pane list`.
- `auto mode on` in the status line means edits auto-accept (good for autonomy). The
  session's permission posture is the user's to set — don't escalate it for them.
- Keep prompts single-quoted in bash and free of apostrophes/embedded double quotes
  to avoid `herdr pane run` quoting issues.
- With channels on (the default), tell each loop (in its `/loop` prompt) to `register_session` with
  a one-line objective at start and to answer peer info-requests — otherwise siblings
  can see it via the mailbox but it won't proactively coordinate. See the `mailbox`
  skill for the protocol.
- This composes with the `herdr` skill (low-level pane control) — read that for the
  full command surface.
