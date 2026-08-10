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

`bash test-claude-mon-hook.sh` runs the hook against a stand-in daemon socket: delivery,
the stdout-leak guard, non-object `tool_input`, and the no-socket no-op.

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
