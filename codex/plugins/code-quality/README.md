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
