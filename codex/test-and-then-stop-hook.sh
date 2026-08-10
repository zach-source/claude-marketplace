#!/usr/bin/env bash
# Drives the and-then Stop hook through a 3-task queue using Codex's Stop payload.
# Guards the queue-advance logic and the decision:"block" contract that makes it work.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

HOOK=codex/plugins/and-then/hooks/scripts/and-then-stop-hook.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/.claude"

fail=0
check() {
  local label="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "       want: $want"
    echo "       got:  $got"
    fail=1
  fi
}

# Feed the hook one Stop event; returns its stdout.
stop() {
  jq -nc --arg cwd "$WORK" --arg msg "$1" \
    '{hook_event_name:"Stop",cwd:$cwd,stop_hook_active:false,last_assistant_message:$msg}' \
    | bash "$HOOK" 2>/dev/null
}

reset_queue() {
  cat > "$WORK/.claude/and-then-queue.json" <<'EOF'
{"current_index":0,"tasks":[
  {"type":"standard","prompt":"first task"},
  {"type":"standard","prompt":"second task"},
  {"type":"fork","workers":2,"subtasks":["a","b","c"]}
]}
EOF
}

reset_queue

# <done/> advances to the next task and blocks the stop so the session continues.
out=$(stop "all set <done/>")
check "advances on <done/>" "block|second task" \
      "$(jq -r '"\(.decision)|\(.reason)"' <<<"$out")"
check "index advanced" "1" "$(jq -r .current_index "$WORK/.claude/and-then-queue.json")"

# No completion signal: re-feed the same task, index unmoved.
out=$(stop "still working")
check "re-feeds without <done/>" "block|second task" \
      "$(jq -r '"\(.decision)|\(.reason)"' <<<"$out")"
check "index unchanged" "1" "$(jq -r .current_index "$WORK/.claude/and-then-queue.json")"

# <done></done> is the other accepted spelling of the signal.
out=$(stop "finished <done></done>")
check "accepts <done></done>" "2" "$(jq -r .current_index "$WORK/.claude/and-then-queue.json")"
check "fork task labelled" "true" \
      "$(jq -r '.systemMessage | test("FORK workers=2")' <<<"$out")"

# Last task done: no output at all, so Codex lets the session exit.
out=$(stop "<done/>")
check "silent on queue exhaustion" "" "$out"
check "queue file removed" "gone" \
      "$([[ -f "$WORK/.claude/and-then-queue.json" ]] && echo present || echo gone)"

# No queue file at all: the hook must stay out of the way.
out=$(stop "anything")
check "no-op without a queue" "" "$out"

exit $fail
