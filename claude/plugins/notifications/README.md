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
