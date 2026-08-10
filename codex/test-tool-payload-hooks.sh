#!/usr/bin/env bash
# Checks the hooks that read Codex tool payloads. Both were silent no-ops before:
# Codex reports edits as apply_patch with the patch text in tool_input.command,
# and PreToolUse context only reaches the model via hookSpecificOutput.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

MOCK="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$MOCK" "$WORK"' EXIT

fail=0
check() { # name expected-substring actual
  if [[ "$3" == *"$2"* ]]; then echo "ok   $1"
  else echo "FAIL $1: wanted '*$2*', got '$3'"; fail=1; fi
}
check_empty() { # name actual
  if [[ -z "$2" ]]; then echo "ok   $1"
  else echo "FAIL $1: wanted empty, got '$2'"; fail=1; fi
}

patch_for() { # path -> an apply_patch envelope touching it
  printf '*** Begin Patch\n*** Update File: %s\n@@\n-a\n+b\n*** End Patch\n' "$1"
}

# ---------------------------------------------------------------- vector-memory
cat > "$MOCK/claude-vector" <<'EOF'
#!/usr/bin/env bash
echo "Loading weights: 100%" >&2   # the real CLI is noisy on stderr
q=$(jq -r '.query // ""')
[ -z "$q" ] && { echo '{"role":"context","content":"No query provided for vector retrieval."}'; exit 0; }
jq -nc --arg q "$q" '{role:"context",content:("prior note about " + $q)}'
EOF
chmod +x "$MOCK/claude-vector"

RETRIEVE=codex/plugins/vector-memory/hooks/scripts/retrieve_vectors.sh
retrieve() { PATH="${2:-$MOCK:$PATH}" bash "$RETRIEVE" <<<"$1" 2>/dev/null; }

check "bash command becomes the query" '"additionalContext":"prior note about go test ./..."' \
  "$(retrieve '{"tool_name":"Bash","tool_input":{"command":"go test ./..."}}')"
check "explicit prompt beats command" 'prior note about refactor the auth flow' \
  "$(retrieve '{"tool_name":"Agent","tool_input":{"command":"noise","prompt":"refactor the auth flow"}}')"
check "wraps as PreToolUse hook output" '"hookEventName":"PreToolUse"' \
  "$(retrieve '{"tool_name":"Bash","tool_input":{"command":"ls"}}')"
check_empty "no extractable query stays silent" \
  "$(retrieve '{"tool_name":"Bash","tool_input":{}}')"
check_empty "malformed payload stays silent" "$(retrieve 'not json')"
check_empty "missing claude-vector stays silent" \
  "$(retrieve '{"tool_name":"Bash","tool_input":{"command":"ls"}}' "/usr/bin:/bin")"

# Whatever we do emit must parse, or Codex reports a JSON error.
if retrieve '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
     | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  echo "ok   emits valid JSON"
else
  echo "FAIL emits valid JSON"; fail=1
fi

# ------------------------------------------------------------------ code-quality
LINT=codex/plugins/code-quality/hooks/scripts/smart-lint.sh
printf 'x = 1\n' > "$WORK/demo.py"

out=$(jq -nc --arg p "$(patch_for "$WORK/demo.py")" \
        '{hook_event_name:"PostToolUse",tool_name:"apply_patch",tool_input:{command:$p}}' \
      | CLAUDE_HOOKS_DEBUG=1 bash "$LINT" 2>&1)
check "apply_patch reaches the linter" "$WORK/demo.py" "$out"

out=$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"ls"}}' \
      | bash "$LINT" 2>&1)
check_empty "non-edit tool is ignored" "$out"

out=$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"apply_patch",
               tool_input:{command:"*** Update File: /nope/gone.py"}}' \
      | bash "$LINT" 2>&1)
check_empty "missing file is ignored" "$out"

# The Claude-shaped payload must keep working - the fallback is still there.
out=$(jq -nc --arg f "$WORK/demo.py" \
        '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}' \
      | CLAUDE_HOOKS_DEBUG=1 bash "$LINT" 2>&1)
check "file_path payload still works" "$WORK/demo.py" "$out"

exit $fail
