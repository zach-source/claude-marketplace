#!/usr/bin/env bash
# Every hook in the tree must emit either nothing or parseable JSON carrying no
# decision other than "block". That is the contract the harness reads back, and
# asserting it directly catches whole classes of bug without knowing about any of
# them: an invalid {"decision":"approve"}, a daemon reply down an nc pipe, or a
# helper that writes to stdout when you only redirected stderr.
#
# Hooks run against stub helpers rather than the real ones - no desktop
# notifications, no qdrant. The stubs are deliberately noisy on BOTH streams, so
# a hook that fails to redirect one gets caught.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

STUB="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$STUB" "$WORK"' EXIT

# terminal-notifier really does print this to stdout when it replaces a
# notification, which is what made the old JSON unparseable.
for cmd in terminal-notifier osascript notify-send tmux zellij nc claude-vector claude-mon; do
  cat > "$STUB/$cmd" <<EOF
#!/usr/bin/env bash
echo "* Removing previously sent notification, which was sent on: $(date)"
echo "stub $cmd noise on stderr" >&2
exit 0
EOF
  chmod +x "$STUB/$cmd"
done

# Failing checkers, chatty on both streams. A checker only writes when it finds
# something, so a clean fixture proves nothing: these always fail. This is what
# catches `checker 2>&1`, which merges diagnostics INTO stdout - it reads like
# silencing and is its exact opposite. The correct form is `checker >&2`.
for cmd in gofmt go black flake8 prettier rustfmt nixfmt yq; do
  cat > "$STUB/$cmd" <<EOF
#!/usr/bin/env bash
echo "$cmd: would reformat /some/file - diagnostics on stdout"
echo "$cmd: diagnostics on stderr" >&2
exit 1
EOF
  chmod +x "$STUB/$cmd"
done

fail=0
mkdir -p "$WORK/.claude"

# One fixture per file-type branch a lint hook might take. A single .py fixture
# would leave five of six branches exercised by no test at all - which is how
# three of the four `2>&1` sites originally shipped "verified" by inspection.
FIXTURES=(demo.go demo.py demo.ts demo.rs demo.yaml demo.nix)
for fx in "${FIXTURES[@]}"; do printf 'x = 1\n' > "$WORK/$fx"; done

# A representative payload per event. cwd points at a scratch dir so nothing a
# hook writes lands in the repo.
payload_for() {
  local event=$1
  local f=${2:-$WORK/demo.py}
  case "$event" in
    PreToolUse|PostToolUse)
      jq -nc --arg c "$WORK" --arg f "$f" \
        '{hook_event_name:"PostToolUse",session_id:"s1",cwd:$c,tool_name:"apply_patch",
          tool_use_id:"t1",tool_input:{command:("*** Begin Patch\n*** Update File: " + $f + "\n@@\n-a\n+b\n*** End Patch")},
          tool_response:{filePath:$f}}' ;;
    Stop|SubagentStop)
      jq -nc --arg c "$WORK" \
        '{hook_event_name:"Stop",session_id:"s1",cwd:$c,stop_hook_active:false,
          last_assistant_message:"finished"}' ;;
    UserPromptSubmit)
      jq -nc --arg c "$WORK" \
        '{hook_event_name:"UserPromptSubmit",session_id:"s1",cwd:$c,prompt:"hello"}' ;;
    PreCompact|PostCompact)
      jq -nc --arg c "$WORK" \
        '{hook_event_name:"PreCompact",session_id:"s1",cwd:$c,trigger:"manual"}' ;;
    SessionStart|SubagentStart)
      jq -nc --arg c "$WORK" \
        '{hook_event_name:"SessionStart",session_id:"s1",cwd:$c,source:"startup"}' ;;
    *)
      jq -nc --arg c "$WORK" --arg e "$event" \
        '{hook_event_name:$e,session_id:"s1",cwd:$c}' ;;
  esac
}

# stdout must be empty, or JSON whose only decision is "block".
assert_channel() {
  local label=$1 out=$2
  if [[ -z "$out" ]]; then
    echo "ok   $label (silent)"
    return
  fi
  if ! jq -e . <<<"$out" >/dev/null 2>&1; then
    echo "FAIL $label emitted unparseable stdout: $(head -c 160 <<<"$out")"
    fail=1
    return
  fi
  local decision
  decision=$(jq -r 'if type == "object" then (.decision // "") else "" end' <<<"$out" 2>/dev/null)
  if [[ -n "$decision" && "$decision" != "block" ]]; then
    echo "FAIL $label emitted invalid decision '$decision' (only \"block\" is valid)"
    fail=1
    return
  fi
  # A hook is not a filter - the payload is not piped through it. Getting the
  # input envelope back means the script rewrote and echoed it, which on
  # UserPromptSubmit dumps session_id and cwd straight into the conversation.
  # This is valid JSON with no bad control keys, so the checks above miss it.
  local echoed
  echoed=$(jq -r 'if type == "object"
                  then ([ "session_id","transcript_path","tool_input","tool_response",
                          "hook_event_name","prompt","cwd" ]
                        | map(select(. as $k | $in | has($k))) | join(", "))
                  else "" end' --argjson in "$out" <<<"$out" 2>/dev/null)
  if [[ -n "$echoed" ]]; then
    echo "FAIL $label echoed the input envelope back ($echoed)"
    fail=1
    return
  fi
  echo "ok   $label (clean JSON)"
}

checked=0
for hooks_json in codex/plugins/*/hooks/hooks.json; do
  plugin=$(basename "$(dirname "$(dirname "$hooks_json")")")
  while IFS=$'\t' read -r event cmd; do
    [[ -z "$cmd" ]] && continue
    # Resolve ${PLUGIN_ROOT} to this plugin's directory.
    resolved=${cmd//\$\{PLUGIN_ROOT\}/codex/plugins/$plugin}
    script=$(basename "${resolved%% *}")

    # Tool events get run once per file type, so per-extension branches inside a
    # hook are actually reached. Other events have no such branching.
    local_fixtures=("")
    case "$event" in PreToolUse|PostToolUse) local_fixtures=("${FIXTURES[@]}") ;; esac

    for fx in "${local_fixtures[@]}"; do
      [[ -n "$fx" ]] && label="$plugin/$event $script [$fx]" || label="$plugin/$event $script"
      out=$(payload_for "$event" "${fx:+$WORK/$fx}" \
            | PATH="$STUB:$PATH" PLUGIN_ROOT="codex/plugins/$plugin" \
              bash -c "$resolved" 2>/dev/null)
      assert_channel "$label" "$out"
      checked=$((checked + 1))
    done
  done < <(jq -r '.hooks | to_entries[] | .key as $e
                  | .value[]?.hooks[]? | select(.type == "command")
                  | "\($e)\t\(.command)"' "$hooks_json")
done

echo "checked $checked hook command(s)"
[[ $checked -gt 0 ]] || { echo "FAIL no hook commands discovered"; fail=1; }
exit $fail
