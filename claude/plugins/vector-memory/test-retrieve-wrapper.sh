#!/usr/bin/env bash
# Checks retrieve_vectors.sh against a mocked claude-vector: query extraction
# from a Claude Code PreToolUse payload, and the hookSpecificOutput rewrap.
# Run: bash claude/plugins/vector-memory/test-retrieve-wrapper.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/hooks/scripts/retrieve_vectors.sh"
MOCK="$(mktemp -d)"
trap 'rm -rf "$MOCK"' EXIT

cat > "$MOCK/claude-vector" <<'EOF'
#!/usr/bin/env bash
echo "Loading weights: 100%" >&2   # the real CLI is noisy on stderr
q=$(jq -r '.query // ""')
[ -z "$q" ] && { echo '{"role":"context","content":"No query provided for vector retrieval."}'; exit 0; }
jq -nc --arg q "$q" '{role:"context",content:("prior note about " + $q)}'
EOF
chmod +x "$MOCK/claude-vector"

fail=0
check() { # name expected-substring payload [path-override]
  local name=$1 want=$2 payload=$3 path=${4:-$MOCK:$PATH}
  local got; got=$(echo "$payload" | PATH="$path" bash "$HOOK" 2>/dev/null)
  if [[ "$got" == *"$want"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: wanted '*$want*', got '$got'"; fail=1
  fi
}

check "grep pattern becomes the query" \
  '"additionalContext":"prior note about handleAuth"' \
  '{"tool_name":"Grep","tool_input":{"pattern":"handleAuth"}}'

check "explicit prompt beats description" \
  'prior note about refactor the auth flow' \
  '{"tool_name":"Task","tool_input":{"description":"short desc","prompt":"refactor the auth flow"}}'

check "file_path is the last-resort query" \
  'prior note about /src/auth.go' \
  '{"tool_name":"Read","tool_input":{"file_path":"/src/auth.go"}}'

check "wraps as PreToolUse hook output" \
  '"hookEventName":"PreToolUse"' \
  '{"tool_name":"Grep","tool_input":{"pattern":"x"}}'

check "no extractable query stays silent" "" \
  '{"tool_name":"Read","tool_input":{}}'

check "malformed payload stays silent" "" 'not json'

check "missing claude-vector stays silent" "" \
  '{"tool_name":"Grep","tool_input":{"pattern":"x"}}' "/usr/bin:/bin"

# Silence checks above pass trivially on any output, so assert emptiness directly.
for payload in '{"tool_name":"Read","tool_input":{}}' 'not json'; do
  got=$(echo "$payload" | PATH="$MOCK:$PATH" bash "$HOOK" 2>/dev/null)
  [[ -z "$got" ]] || { echo "FAIL expected empty stdout for: $payload"; fail=1; }
done

# Whatever we do emit must be parseable, or Claude Code reports a JSON error.
echo '{"tool_name":"Grep","tool_input":{"pattern":"x"}}' \
  | PATH="$MOCK:$PATH" bash "$HOOK" \
  | python3 -c 'import json,sys; json.load(sys.stdin)' \
  && echo "ok   emits valid JSON" || { echo "FAIL invalid JSON"; fail=1; }

exit $fail
