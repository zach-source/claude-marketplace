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

### Nix

The flake exposes the tree as one package. Both marketplace manifests name their
plugins by path relative to the repo root, so the root is the unit that can be
installed — there is no per-harness output to split out.

```nix
{
  inputs.claude-marketplace.url = "github:zach-source/claude-marketplace";

  # home-manager
  home.file.".claude/marketplaces/zach-source".source =
    inputs.claude-marketplace.packages.${pkgs.system}.default;

  # Pi loads flat modules, so point it at the subdirectory
  home.file.".pi/agent/extensions".source =
    "${inputs.claude-marketplace.packages.${pkgs.system}.default}/pi/extensions";
}
```

The hooks shell out to `jq` plus whatever checker matches the edited file
(`gofmt`, `black`, `nixfmt`, …). None of those are wrapped into the derivation —
every one is guarded by `command_exists` and the branch is skipped when it is
missing, so put the ones you want on your own `PATH`.

`nix flake check` runs the four hook-contract suites. `pi/typecheck.sh` is not
among them: it resolves the Pi types from a global npm install, which the sandbox
does not have.

## What is measured, and what is not

The test counts are identical whether the contract is right or invented, so:

- **Measured against reality** — transcript structure (no top-level `.role`; 0 of 3214
  lines), `tool_response` shape distribution (string ~2% of Edit/Write results), the tool
  inventory (no `MultiEdit`), and the claude-mon daemon payload (a running daemon replies
  `{"status":"ok"}`).
- **Documented but not observed live** — `last_assistant_message` on the Stop payload,
  which and-then's completion detection depends on. The suites synthesise it; transcripts
  record hook summaries, not hook inputs. Degrades to the pre-fix behaviour if absent.
- **Never run as installed plugins.** These scripts have been exercised against
  synthesised payloads, not loaded by Claude Code from this marketplace. The suites prove
  the hooks honour the documented contract; they cannot prove the contract.

That last point applies to every fix here, but the fixes do not all rest on it equally.
Some correct a **measured fact about the harness** and hold whether or not the docs are
right; others are **contract-dependent** and would be no-ops, not misbehaviour, if the
documented contract turned out to be wrong:

| Fix | Bug established by | Fix rests on |
|-----|--------------------|--------------|
| and-then `<done/>` never detected | measured — 0 of 3214 transcript lines have top-level `.role` | `last_assistant_message` (documented, unobserved) |
| smart-lint skipped ~2% of edits | measured — 14 of 628 `tool_response` values are strings | jq robustness only |
| claude-mon never read its payload | measured — no stdin read; real daemon accepts the new shape | measured |
| terminal-notifier stdout leak | measured — observed on stdout | contract (stdout is parsed) |
| checker `2>&1` inversion | measured — stubs show output on stdout | contract (stdout is parsed) |
| `decision: "approve"` | documented — `"block"` is the only value | contract |
| vector-memory retrieved nothing | measured — CLI reads `tool`/`arguments`, harness sends `tool_name`/`tool_input` | `additionalContext` (documented) |
| precompact piped a CLI into the result | documented — `continue:false` halts compaction | contract |
| inject_project_docs echoed the payload | measured — observed | contract (stdout becomes context) |

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
