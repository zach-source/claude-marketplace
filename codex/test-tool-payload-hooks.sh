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

# The .py branch only says anything if a Python checker is on PATH, so a real
# black/flake8 makes these assertions a property of the machine: they pass here
# and fail on any box without one. Stub the checker - what is under test is that
# the path is extracted from the payload, not that black works.
STUBS="$MOCK/stubs"; mkdir -p "$STUBS"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/black"
chmod +x "$STUBS/black"
lint() { PATH="$STUBS:$PATH" CLAUDE_HOOKS_DEBUG=1 bash "$LINT" 2>&1; }

out=$(jq -nc --arg p "$(patch_for "$WORK/demo.py")" \
        '{hook_event_name:"PostToolUse",tool_name:"apply_patch",tool_input:{command:$p}}' \
      | lint)
check "apply_patch reaches the linter" "$WORK/demo.py" "$out"

out=$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"ls"}}' \
      | bash "$LINT" 2>&1)
check_empty "non-edit tool is ignored" "$out"

out=$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"apply_patch",
               tool_input:{command:"*** Update File: /nope/gone.py"}}' \
      | bash "$LINT" 2>&1)
check_empty "missing file is ignored" "$out"

# The structured payload must keep working - the fallback is still there.
out=$(jq -nc --arg f "$WORK/demo.py" \
        '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}' \
      | lint)
check "file_path payload still works" "$WORK/demo.py" "$out"

# tool_response is only "tool-specific output" - it is not always a map. Indexing
# a string is a jq error that kills the whole pick, throwing away the correct
# path sitting in the tool_input fallback. Python here on purpose: go vet fails
# on any file outside a module, so a .go control exits 2 for unrelated reasons.
for shape in '"a plain string"' '["an","array"]' 'null' '42'; do
  out=$(jq -nc --arg f "$WORK/demo.py" --argjson r "$shape" \
          '{hook_event_name:"PostToolUse",tool_name:"Write",
            tool_response:$r,tool_input:{file_path:$f}}' \
        | lint)
  check "tool_response as $shape falls back to tool_input" "$WORK/demo.py" "$out"
done

# Neither field usable: stay quiet rather than error.
out=$(jq -nc '{hook_event_name:"PostToolUse",tool_name:"Write",
               tool_response:"str",tool_input:"also a string"}' \
      | bash "$LINT" 2>&1)
check_empty "unusable payload stays silent" "$out"

# A non-map tool_input must not break query extraction either.
check_empty "retrieve survives non-map tool_input" \
  "$(retrieve '{"tool_name":"Bash","tool_input":"a string"}')"

# ----------------------------------------------------------------- claude-mon
# This hook read $TOOL_INPUT/$TOOL_NAME from the environment, which no harness
# sets, so it streamed empty lines and never resolved a path. It reads the
# payload now; with no claude-mon socket it must still exit cleanly.
MON=codex/plugins/notifications/hooks/scripts/claude-mon-hook.sh
out=$(jq -nc --arg p "$(patch_for "$WORK/demo.py")" \
        '{hook_event_name:"PostToolUse",tool_name:"apply_patch",tool_input:{command:$p}}' \
      | bash "$MON" 2>/dev/null)
rc=$?
check "claude-mon exits 0" "0" "$rc"

# Whether a claude-mon socket exists is a property of the machine, not the hook,
# so assert what actually matters: nothing it writes may be read back as a hook
# decision. A daemon reply leaking onto stdout would be exactly that.
if [[ -z "$out" ]]; then
  echo "ok   claude-mon writes nothing to stdout"
elif jq -e 'has("decision") or has("continue") or has("hookSpecificOutput")' <<<"$out" >/dev/null 2>&1; then
  echo "FAIL claude-mon emitted hook-control fields: $out"; fail=1
else
  echo "FAIL claude-mon wrote stray stdout: $out"; fail=1
fi

out=$(echo 'not json' | bash "$MON" 2>/dev/null); rc=$?
check "claude-mon survives malformed payload" "0" "$rc"

# It must take tool_name/tool_input from the payload, not from the environment,
# which is where they used to come from and were never set.
if grep -qE '^HOOK_INPUT="\$\(cat\)"' "$MON" \
   && grep -qE '^TOOL_NAME=.*jq.*tool_name' "$MON" \
   && grep -qE '^TOOL_INPUT=.*jq.*tool_input' "$MON"; then
  echo "ok   claude-mon sources tool fields from the payload"
else
  echo "FAIL claude-mon sources tool fields from the payload"; fail=1
fi

exit $fail
