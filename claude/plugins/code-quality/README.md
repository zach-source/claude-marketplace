# code-quality

Formats and lints every file Claude writes, before you see it.

## Hooks

| Event | Script |
|-------|--------|
| PostToolUse (`Write\|Edit\|MultiEdit`) | `smart-lint.sh` |

Detects the language from the extension and runs whichever checker is on `PATH`. Missing
tool = skipped, not failed.

| Extension | Checker |
|-----------|---------|
| `.go` | `gofmt -l` |
| `.py` | `black --check`, `flake8` |
| `.js` `.jsx` `.ts` `.tsx` | `prettier --check` |
| `.rs` | `rustfmt --check` |
| `.nix` | `nixfmt --check` |

Failures exit 2, which surfaces the diff to Claude as a blocking error so it fixes the file
instead of moving on.

Set `CLAUDE_HOOKS_LINT_ENABLED=false` to disable, `CLAUDE_HOOKS_DEBUG=1` for verbose output.

## Finding the edited file

`tool_response` is not always an object — roughly 2% of real Edit/Write results arrive as
a plain string. Reading `.tool_response.filePath` on one of those is a jq error, and the
error aborts the expression before `//` can reach the `tool_input.file_path` fallback, so
the hook used to skip those edits entirely, silently and at exit 0. The path lookup now
tolerates any `tool_response` shape.

`bash test-payload-parsing.sh` covers the shapes (string, array, object, absent, null
`filePath`) plus tool gating and the disable switch.

`MultiEdit` is still in the matcher but never appears in practice — 0 occurrences across
25 transcripts, against 499 `Edit` and 143 `Write`. Harmless to keep for older clients.
