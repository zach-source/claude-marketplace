# claude-marketplace

Community plugins for Claude Code.

## Plugins

| Plugin | Category | Description |
|--------|----------|-------------|
| [and-then](./plugins/and-then) | productivity | Sequential task queue with parallel fork support |

## Installation

### Install specific plugin

```bash
# From Claude Code
/plugin install and-then@zach-source/claude-marketplace
```

### Install from source

Clone and add to your `.claude/plugins.json`:

```json
{
  "plugins": [
    "/path/to/claude-marketplace/plugins/and-then"
  ]
}
```

## Structure

```
claude-marketplace/
├── .claude-plugin/
│   └── marketplace.json      # Plugin directory
├── plugins/
│   └── and-then/             # Task queue plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── commands/
│       ├── hooks/
│       ├── scripts/
│       └── README.md
└── README.md
```

## Contributing

1. Create plugin in `plugins/your-plugin/`
2. Add `.claude-plugin/plugin.json` manifest
3. Add entry to `.claude-plugin/marketplace.json`
4. Submit PR

## License

MIT
