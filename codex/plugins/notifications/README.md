# notifications

Tells you when the agent wants you back.

## Hooks

| Event | Script | What it does |
|-------|--------|--------------|
| Stop | `notify-hook.sh stop` | Alert when the agent finishes a turn |
| SubagentStop | `subagent-stop-hook.sh` | Alert when a subagent completes |
| PostToolUse (`Write\|Edit\|apply_patch`) | `claude-mon-hook.sh` | Streams edits to the claude-mon TUI and daemon |

`claude-mon-hook.sh` is a no-op if claude-mon is not running.

The Claude build of this plugin also fires on `Notification` to alert when the
agent needs input. Codex has no `Notification` event, so that alert is missing
here — `Stop` is the closest signal available.

## Statusline

Not a hook, and not wired by the plugin — `statusline/` is carried over for use
with a host that reads a statusline command from its own config. Two options:

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
