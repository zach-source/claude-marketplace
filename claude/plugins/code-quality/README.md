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
| `.go` | `gofmt -l`, plus `go vet` when the file sits in a module |
| `.py` | `black --check`, `flake8` |
| `.js` `.jsx` `.ts` `.tsx` | `prettier --check` |
| `.rs` | `rustfmt --check` |
| `.yaml` `.yml` | `yq e` (syntax only) |
| `.nix` | `nixfmt --check` |

Failures exit 2, which surfaces the diff to Claude as a blocking error so it fixes the file
instead of moving on.

Set `CLAUDE_HOOKS_LINT_ENABLED=false` to disable, `CLAUDE_HOOKS_DEBUG=1` for verbose output.

## Pinning the checkers (`CLAUDE_HOOKS_BIN`)

"Whichever checker is on `PATH`" is the weak point for a declarative install: hooks inherit
no interactive shell `PATH`, and a missing tool is skipped at exit 0 — so a checker that was
never found and one that passed look the same from outside.

Set `CLAUDE_HOOKS_BIN` to a colon-separated list of bin directories and they are searched
first. Unset, nothing changes and a plain checkout keeps working.

```nix
# home-manager: pin the exact store binaries, use the plugin script unmodified
programs.claude-code.settings.env.CLAUDE_HOOKS_BIN = lib.makeBinPath [
  pkgs.coreutils pkgs.jq pkgs.go pkgs.black pkgs.python3Packages.flake8
  pkgs.prettier pkgs.rustfmt pkgs.nixfmt pkgs.yq-go
];
```

This is deliberately one search path rather than a variable per command: it covers every
checker at once, including ones the script gains later, and it is the same shape as
`wrapProgram --prefix PATH`. An entry that is not a directory is reported on stderr rather
than ignored — silently falling through to the ambient tool is the failure this exists to
prevent.

`bash ../../test-bin-pinning.sh` covers precedence, `PATH` fallback, and the bad-entry
report.

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
