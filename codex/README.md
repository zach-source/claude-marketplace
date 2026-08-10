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
  walking `transcript_path`, whose format the hook docs call unstable. Its slash
  commands became a skill, since Codex plugins have no commands.
- **vector-memory** rewraps `claude-vector` output as
  `hookSpecificOutput.additionalContext`. Codex ignores plain stdout on
  `PreToolUse`, so the retrieved context would otherwise never reach the model.

Not mirrored: `slash-commands` and `subagents`. Codex plugins have no commands or
agents component, and both plugins are nothing but those.

`code-quality` still formats and lints on `PostToolUse`, but Codex only documents
exit-2-with-stderr blocking for `PreToolUse` and `UserPromptSubmit`, so lint
failures may surface less loudly than under Claude Code.

## Checks

```bash
python3 codex/validate-plugins.py        # manifests, component paths, skills, marketplace
bash codex/test-and-then-stop-hook.sh    # and-then queue advance logic
```

`validate-plugins.py` checks that every manifest parses, carries the required
`name`/`version`/`description`, uses a kebab-case name matching its directory,
keeps `.codex-plugin/` free of anything but `plugin.json`, and that each component
pointer starts with `./` and resolves inside the plugin root. It also checks the
marketplace lists exactly the plugins present on disk, with the required
`policy.installation`, `policy.authentication` and `category` on each entry.

## Installing

Codex copies plugins into `~/.codex/plugins/cache/$MARKETPLACE/$PLUGIN/$VERSION/`
and loads from there, so edits need a re-copy and a restart. Enabling a plugin
does not trust its hooks — hooks stay inactive until reviewed and trusted.
