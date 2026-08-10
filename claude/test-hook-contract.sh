#!/usr/bin/env bash
# Contract check across every Claude hook in the repo: whatever a hook writes to
# stdout, the harness parses as JSON. So stdout must be empty, or parseable JSON
# whose control keys are ones we actually meant.
#
# Two things make this worth more than the per-plugin tests:
#   - it DISCOVERS hooks from the hooks.json manifests, so a hook nobody thought
#     to test is covered the moment it is registered;
#   - it stubs every helper a hook might shell out to, each one noisy on BOTH
#     streams, so a helper writing to stdout shows up here rather than in prod.
#
# Run: bash claude/test-hook-contract.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUBS="$(mktemp -d)"
trap 'rm -rf "$STUBS"' EXIT

# Helpers that hooks shell out to. Each is deliberately chatty on stdout AND
# stderr: if a hook forgets to redirect one, this test sees it. claude-vector and
# nc are stubbed too - without that, a hook would quietly reach the real qdrant or
# a real socket and the leak would stay hidden.
for helper in terminal-notifier osascript notify-send zellij claude-vector bd; do
  cat > "$STUBS/$helper" <<EOF
#!/usr/bin/env bash
echo "* $helper chatter on stdout"
echo "* $helper chatter on stderr" >&2
exit 0
EOF
  chmod +x "$STUBS/$helper"
done

# nc gets the shape the real claude-mon daemon actually returns, measured by
# probing it: {"status":"ok"}. That is valid JSON carrying no control key, so it
# slips past the parseable/decision/envelope assertions - it is caught only by
# the allowed-keys one below. A stub emitting obvious garbage would have made
# this test look stronger than it is.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "{\"status\":\"ok\"}"' \
  'echo "* nc chatter on stderr" >&2' \
  'exit 0' > "$STUBS/nc"
chmod +x "$STUBS/nc"

WORK="$(mktemp -d)"; trap 'rm -rf "$STUBS" "$WORK"' EXIT
printf 'package main\nfunc main(){}\n' > "$WORK/edited.go"

PAYLOAD=$(jq -nc --arg cwd "$WORK" '{
  session_id: "contract-test",
  hook_event_name: "PostToolUse",
  cwd: $cwd,
  prompt: "check the contract",
  tool_name: "Edit",
  tool_input: { file_path: "\($cwd)/edited.go", old_string: "a", new_string: "b" },
  tool_response: { filePath: "\($cwd)/edited.go" },
  last_assistant_message: "no completion signal here",
  stop_hook_active: false
}')

fail=0 checked=0

while IFS= read -r manifest; do
  plugin="$(basename "$(dirname "$(dirname "$manifest")")")"
  proot="$(dirname "$(dirname "$manifest")")"

  while IFS=$'\t' read -r event cmd; do
    # hooks.json ships the command unexpanded; the harness substitutes this.
    resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$proot}"
    checked=$((checked + 1))

    out=$(cd "$WORK" && echo "$PAYLOAD" | PATH="$STUBS:$PATH" timeout 20 bash -c "$resolved" 2>/dev/null)

    label="$plugin/$event"
    if [[ -z "$out" ]]; then
      echo "ok   $label emits nothing"
    elif ! jq -e . >/dev/null 2>&1 <<<"$out"; then
      echo "FAIL $label emitted unparseable stdout: $(head -c 120 <<<"$out")"
      fail=1
    elif jq -e 'has("decision") and .decision != "block"' >/dev/null 2>&1 <<<"$out"; then
      echo "FAIL $label emitted a decision that is not \"block\": $(head -c 120 <<<"$out")"
      fail=1
    elif jq -e 'has("continue") and .continue == false' >/dev/null 2>&1 <<<"$out"; then
      # continue:false halts the session outright and takes precedence over
      # decision. No hook here means to do that.
      echo "FAIL $label emitted continue:false: $(head -c 120 <<<"$out")"
      fail=1
    elif jq -e 'has("session_id") or has("transcript_path") or has("tool_input") or has("hook_event_name")' >/dev/null 2>&1 <<<"$out"; then
      # A hook is not a filter the payload is piped through. Seeing the input
      # envelope's own keys come back means the script rewrote the payload and
      # echoed it - which on UserPromptSubmit dumps session_id, cwd and every
      # tool field straight into the conversation. Valid JSON, entirely wrong.
      echo "FAIL $label echoed its input payload back: $(head -c 120 <<<"$out")"
      fail=1
    elif [[ -n "$(jq -r 'keys[] | select(. as $k | ["continue","stopReason","suppressOutput","systemMessage","terminalSequence","decision","reason","hookSpecificOutput"] | index($k) | not)' <<<"$out" 2>/dev/null)" ]]; then
      # Anything outside the documented top-level result fields is not a hook
      # result - it is some helper's reply that reached stdout. The real
      # claude-mon daemon answers {"status":"ok"}, which is valid JSON with no
      # control key and no envelope key, so every assertion above waves it
      # through. Benign today is not the same as guarded.
      echo "FAIL $label emitted undocumented result keys ($(jq -r '[keys[] | select(. as $k | ["continue","stopReason","suppressOutput","systemMessage","terminalSequence","decision","reason","hookSpecificOutput"] | index($k) | not)] | join(",")' <<<"$out" 2>/dev/null)): $(head -c 80 <<<"$out")"
      fail=1
    else
      echo "ok   $label emits valid JSON ($(jq -c 'keys | join(",")' <<<"$out" 2>/dev/null))"
    fi
  done < <(jq -r 'to_entries[] | .key as $e | .value[]?.hooks[]? | [$e, .command] | @tsv' "$manifest")
done < <(find "$ROOT/claude/plugins" -name hooks.json -path '*/hooks/*' | sort)

echo
echo "$checked hook commands checked"
exit $fail
