#!/usr/bin/env bash
# Checks smart-lint's payload handling: which tools it acts on, and that it finds
# the edited file whatever shape tool_response arrives in.
# Run: bash claude/plugins/code-quality/test-payload-parsing.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/hooks/scripts/smart-lint.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Badly formatted on purpose: gofmt must have something to complain about, or
# "linted" and "skipped" both look like success.
BAD="$WORK/bad.go"
printf 'package main\nfunc main(){}\n' > "$BAD"

# The clean control is Python, not Go: `go vet` fails on any file outside a
# module, so a well-formatted .go in a temp dir exits 2 for reasons that have
# nothing to do with payload parsing.
GOOD="$WORK/good.py"
printf 'x = 1\n' > "$GOOD"

fail=0
if ! command -v gofmt >/dev/null; then
  echo "SKIP: gofmt not on PATH, nothing to assert against"; exit 0
fi

# run <payload-json> -> exit code (2 = lint failed = the hook did its job)
run() { echo "$1" | bash "$HOOK" >/dev/null 2>&1; echo $?; }

check() { # name expected actual
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: wanted exit $2, got $3"; fail=1; fi
}

# The regression: a string tool_response used to abort the jq expression before
# the tool_input fallback, so the file was never found and nothing was linted.
check "string tool_response still finds the file" 2 \
  "$(run "{\"tool_name\":\"Edit\",\"tool_response\":\"File has been updated.\",\"tool_input\":{\"file_path\":\"$BAD\"}}")"

check "object tool_response with filePath" 2 \
  "$(run "{\"tool_name\":\"Edit\",\"tool_response\":{\"filePath\":\"$BAD\"},\"tool_input\":{\"file_path\":\"$BAD\"}}")"

check "array tool_response falls back" 2 \
  "$(run "{\"tool_name\":\"Write\",\"tool_response\":[1,2],\"tool_input\":{\"file_path\":\"$BAD\"}}")"

check "absent tool_response falls back" 2 \
  "$(run "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$BAD\"}}")"

check "null filePath falls back to tool_input" 2 \
  "$(run "{\"tool_name\":\"Edit\",\"tool_response\":{\"filePath\":null},\"tool_input\":{\"file_path\":\"$BAD\"}}")"

check "well-formatted file passes" 0 \
  "$(run "{\"tool_name\":\"Edit\",\"tool_response\":{\"filePath\":\"$GOOD\"},\"tool_input\":{\"file_path\":\"$GOOD\"}}")"

check "non-edit tool is ignored" 0 \
  "$(run "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}")"

check "missing file is ignored" 0 \
  "$(run '{"tool_name":"Edit","tool_input":{"file_path":"/nonexistent/x.go"}}')"

check "no path anywhere is ignored" 0 \
  "$(run '{"tool_name":"Edit","tool_response":"done","tool_input":{}}')"

check "malformed payload does not crash" 0 "$(run 'not json')"

check "disabled by env" 0 \
  "$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$BAD\"}}" \
     | CLAUDE_HOOKS_LINT_ENABLED=false bash "$HOOK" >/dev/null 2>&1; echo $?)"

exit $fail
