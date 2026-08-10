# claude-marketplace

Plugins for AI coding harnesses. One top-level tree per harness.

```
claude-marketplace/
├── .claude-plugin/
│   └── marketplace.json     # Claude Code marketplace (must live at this exact path)
├── claude/plugins/          # Claude Code plugins
├── codex/plugins/           # Codex plugins (.agents/plugins/marketplace.json)
└── pi/                      # Pi extensions (plain .ts, no manifest)
```

Each Claude plugin follows the standard layout:

```
claude/plugins/<name>/
├── .claude-plugin/plugin.json
├── commands/  agents/  skills/
├── hooks/hooks.json + hooks/scripts/
└── scripts/
```

Plugins vendor everything they need. Nothing is shared across plugin or harness
boundaries — `common-helpers.sh` is duplicated on purpose so each plugin installs
standalone.

## Claude plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| [and-then](./claude/plugins/and-then) | productivity | Sequential task queue with parallel fork support |
| [context-injection](./claude/plugins/context-injection) | context | Project docs, working context (k8s/aws/env), context7 hints, cwd memory |
| [session-hygiene](./claude/plugins/session-hygiene) | productivity | Stale prompt-cache guard, MCP config sync |
| [code-quality](./claude/plugins/code-quality) | quality | Format/lint every file Claude writes |
| [notifications](./claude/plugins/notifications) | notifications | Desktop/tmux alerts, claude-mon stream, statusline |
| [vector-memory](./claude/plugins/vector-memory) | memory | Qdrant vectorization on precompact, retrieval on tool use |
| [subagents](./claude/plugins/subagents) | agents | 80 specialized subagents |
| [slash-commands](./claude/plugins/slash-commands) | productivity | 18 slash commands |
| [workflow-skills](./claude/plugins/workflow-skills) | workflow | granted, 1password, herdr, herdr-claude-loop |

## Codex plugins

Seven of the nine are mirrored for Codex under [`codex/plugins/`](./codex), with
their own marketplace at `.agents/plugins/marketplace.json`. `subagents` and
`slash-commands` are not — Codex plugins have no agents or commands component.
See [codex/README.md](./codex/README.md) for the per-plugin differences.

## Pi extensions

Pi has no plugin format at all — an extension is a single `.ts` module with a
default export taking an `ExtensionAPI`, loaded from `~/.pi/agent/extensions/`.
So [`pi/`](./pi) is a flat directory of extensions rather than a plugin tree.
Seven of the hooks are ported there; the rest are documented as not porting,
with the reason for each. See [pi/README.md](./pi/README.md).

## Installation

```bash
/plugin marketplace add zach-source/claude-marketplace
/plugin install code-quality@claude-marketplace
```

Or point at a local checkout in `.claude/plugins.json`:

```json
{ "plugins": ["/path/to/claude-marketplace/claude/plugins/code-quality"] }
```

## Contributing

1. Create the plugin under the tree for its harness — `claude/plugins/<name>/`.
2. Add `.claude-plugin/plugin.json`.
3. Register it in `.claude-plugin/marketplace.json` with an explicit relative
   `source`, e.g. `./claude/plugins/<name>`.
4. Codex keeps its own manifest at `.agents/plugins/marketplace.json`; do not add
   a second `marketplace.json` under `.claude-plugin/`. Pi has no manifest —
   drop the `.ts` file in `pi/extensions/` and document it in `pi/README.md`.

## License

MIT
