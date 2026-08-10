#!/usr/bin/env bash
# Checks the and-then Stop hook: completion detection off last_assistant_message,
# queue advance/exhaust, fork prompts, and the stop_hook_active loop guard.
# Run: bash claude/plugins/and-then/test-stop-hook.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/hooks/scripts/and-then-stop-hook.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/.claude"

QUEUE="$WORK/.claude/and-then-queue.json"
fail=0

seed() { echo "$1" > "$QUEUE"; }

# run <last_assistant_message> [stop_hook_active]
run() {
  jq -nc --arg m "${1:-}" --argjson active "${2:-false}" --arg cwd "$WORK" \
    '{hook_event_name:"Stop", cwd:$cwd, last_assistant_message:$m, stop_hook_active:$active}' \
    | bash "$HOOK" 2>/dev/null
}

check() { # name expected actual
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: wanted '$2', got '$3'"; fail=1; fi
}

TWO='{"current_index":0,"tasks":[{"type":"standard","prompt":"first task"},{"type":"standard","prompt":"second task"}]}'

# --- completion detection -------------------------------------------------
seed "$TWO"
out=$(run 'all set <done/>')
check "done advances to next task"  "second task" "$(jq -r '.reason' <<<"$out")"
check "index persisted"             "1"           "$(jq -r '.current_index' "$QUEUE")"

seed "$TWO"
out=$(run 'still working on it')
check "no done re-feeds current"    "first task"  "$(jq -r '.reason' <<<"$out")"
check "index unchanged"             "0"           "$(jq -r '.current_index' "$QUEUE")"

seed "$TWO"
check "<done></done> also counts"   "second task" "$(jq -r '.reason' <<<"$(run 'wrapped up <done></done>')")"

seed "$TWO"
check "done mid-sentence counts"    "second task" "$(jq -r '.reason' <<<"$(run 'Finished.\n\n<done/>\n')")"

# The bug this file exists for: the old code read a top-level .role that Claude Code
# never emits, so LAST_OUTPUT was always empty and this case looked like "not done".
seed "$TWO"
check "blocks, not allows, on done" "block"       "$(jq -r '.decision' <<<"$(run 'done here <done/>')")"

# --- queue exhaustion -----------------------------------------------------
seed '{"current_index":1,"tasks":[{"type":"standard","prompt":"a"},{"type":"standard","prompt":"b"}]}'
out=$(run 'finished <done/>')
check "last task exits silently"    ""            "$out"
[[ -f "$QUEUE" ]] && { echo "FAIL queue file should be removed when exhausted"; fail=1; } \
                  || echo "ok   queue file removed when exhausted"

# --- loop guard -----------------------------------------------------------
seed "$TWO"
check "stop_hook_active short-circuits" "" "$(run 'still working' true)"

# --- no queue, no opinion -------------------------------------------------
rm -f "$QUEUE"
check "no queue file is a no-op"    ""            "$(run 'anything <done/>')"

# --- missing signal does not crash ---------------------------------------
seed "$TWO"
check "absent message re-feeds"     "first task"  "$(jq -r '.reason' <<<"$(run '')")"

# --- fork prompts ---------------------------------------------------------
seed '{"current_index":0,"tasks":[{"type":"fork","subtasks":["x","y","z"],"workers":2}]}'
out=$(run 'not yet')
grep -q "LIMITED CONCURRENCY of 2" <<<"$(jq -r '.reason' <<<"$out")" \
  && echo "ok   fork honours workers" || { echo "FAIL fork workers prompt"; fail=1; }
grep -q "workers=2" <<<"$(jq -r '.systemMessage' <<<"$out")" \
  && echo "ok   fork label shows workers" || { echo "FAIL fork label"; fail=1; }

seed '{"current_index":0,"tasks":[{"type":"fork","subtasks":["x","y"]}]}'
grep -q "in PARALLEL" <<<"$(jq -r '.reason' <<<"$(run 'not yet')")" \
  && echo "ok   fork without workers is fully parallel" || { echo "FAIL fork parallel"; fail=1; }

# --- malformed state ------------------------------------------------------
seed 'not json at all'
check "invalid state file exits"    ""            "$(run 'x <done/>')"

exit $fail
