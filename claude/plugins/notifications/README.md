# notifications

Tells you when Claude wants you back.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| Notification | `notify-hook.sh notification` | Desktop + tmux alert when Claude needs input |
| Stop | `notify-hook.sh stop` | Alert when Claude finishes a turn |
| SubagentStop | `subagent-stop-hook.sh` | Alert when a subagent completes |
| PostToolUse (`Write\|Edit\|MultiEdit`) | `claude-mon-hook.sh` | Streams edits to the claude-mon TUI and daemon |

`claude-mon-hook.sh` is a no-op if claude-mon is not running.

### claude-mon payload handling

The hook used to take `TOOL_INPUT` and `TOOL_NAME` from the **environment** — a legacy
env-var hook interface that no harness sets. Claude Code delivers the payload as JSON on
stdin, so both were always empty: the TUI received blank lines and `FILE_PATH` never
resolved, which meant the daemon branch never ran at all. It now reads stdin, and takes
the workspace from the payload's `cwd` rather than the hook process's own.

Both `nc` sends are redirected to `/dev/null`. `nc`'s stdout is the hook's stdout, and
PostToolUse stdout is parsed for hook decisions — a daemon replying with a `decision` or
`continue` key could otherwise steer the session. Nothing that socket says is for Claude.

### Stdout discipline

The harness parses hook stdout as JSON, so everything here keeps its stdout empty. Two
things used to break that:

- `notify-hook.sh` and `subagent-stop-hook.sh` emitted `{"decision": "approve", ...}`.
  `"block"` is the only valid `decision`; omitting it is how you allow the action. The
  `"approve"` payload failed schema validation on every notification and every subagent
  completion.
- `terminal-notifier` writes to **stdout** when it replaces an earlier notification, and
  only its stderr was redirected — so that line landed in the JSON the harness tried to
  parse. All notifier calls now redirect both streams.

`bash test-notifications.sh` covers claude-mon delivery against a stand-in daemon socket,
the daemon-reply leak guard, non-object `tool_input`, the no-socket no-op, and asserts
every hook in the plugin emits either nothing or parseable JSON with no stray `decision`.

## Statusline

Not a hook — Claude Code takes the statusline from `settings.json`, so plugins cannot wire
it. Two options in `statusline/`:

`claude-statusline.sh` — model | context% | branch | diff stat:

```json
{ "statusLine": { "type": "command", "command": "/path/to/claude/plugins/notifications/statusline/claude-statusline.sh", "padding": 0 } }
```

`ccstatusline-settings.json` — config for the richer [ccstatusline](https://github.com/sirmalloc/ccstatusline):

```json
{ "statusLine": { "type": "command", "command": "ccstatusline --config /path/to/ccstatusline-settings.json", "padding": 0 } }
```

## Requirements

`jq`. macOS uses `osascript` for desktop notifications; tmux alerts need `tmux`.

Every one of those is looked up on `PATH`, which hooks do not inherit from an interactive
shell. Set `CLAUDE_HOOKS_BIN` to a colon-separated list of bin directories to have them
searched first — see [code-quality](../code-quality/README.md#pinning-the-checkers-claude_hooks_bin)
for the mechanism and the `lib.makeBinPath` wiring. Unset, nothing changes.

The daemon payload shape is confirmed against a running claude-mon, not only a stand-in
socket: it replies `{"status":"ok"}`. That reply is also what would land on the hook's
stdout without the redirect — benign today, and benign is not the same as guarded, which
is why the redirect rather than the contract assertion is what protects it.
