#!/usr/bin/env bash
# Routing check for shunt-guard, run against BOTH harness copies of the script.
#
# The two copies differ only in their header (the Claude one honours
# CLAUDE_HOOKS_BIN), so the same cases must hold for both — and running them
# together is what catches a fix landing on one side and not the other.
#
# Run: bash claude/plugins/shunt/test-shunt-guard.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
big="$WORK/big.ts"; seq 1 900 >"$big"
small="$WORK/small.ts"; seq 1 10 >"$small"
# A directory whose name looks like a count flag. The flag check must read argv
# tokens, not the whole command string, or this file reads as an -n bounded read.
mkdir -p "$WORK/tmp-3xy"; flagish="$WORK/tmp-3xy/big.ts"; seq 1 900 >"$flagish"

fail=0 checked=0

check() { # want(deny|allow) desc payload
  local want=$1 desc=$2 payload=$3 got
  checked=$((checked + 1))
  got=$(printf '%s' "$payload" | SHUNT_MIN_LINES=800 bash "$GUARD" 2>/dev/null)
  if [[ -z $got ]]; then
    got=allow
  else
    got=$(jq -r '.hookSpecificOutput.permissionDecision // "MALFORMED"' <<<"$got" 2>/dev/null) \
      || got=UNPARSEABLE
  fi
  if [[ $got == "$want" ]]; then
    echo "ok   $HARNESS $desc"
  else
    echo "FAIL $HARNESS $desc: wanted $want, got $got"
    fail=1
  fi
}

read_payload() { jq -nc --arg p "$1" '{tool_name:"Read",tool_input:{file_path:$p}}'; }
bash_payload() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

for GUARD in claude/plugins/shunt/hooks/scripts/shunt-guard.sh \
             codex/plugins/shunt/hooks/scripts/shunt-guard.sh; do
  HARNESS="[$(cut -d/ -f1 <<<"$GUARD")]"
  [[ -f $GUARD ]] || { echo "FAIL missing $GUARD"; fail=1; continue; }

  check deny  "Read: large file"                 "$(read_payload "$big")"
  check allow "Read: small file"                 "$(read_payload "$small")"
  check allow "Read: missing file"               "$(read_payload "$WORK/nope.ts")"
  check allow "Read: large file, offset set"     "$(jq -nc --arg p "$big" '{tool_name:"Read",tool_input:{file_path:$p,offset:10,limit:20}}')"

  check deny  "shell: cat large"                 "$(bash_payload "cat $big")"
  check allow "shell: cat small"                 "$(bash_payload "cat $small")"
  check allow "shell: cat large piped to grep"   "$(bash_payload "cat $big | grep 42")"
  check allow "shell: cat large redirected"      "$(bash_payload "cat $big > $WORK/out")"
  check deny  "shell: cat large, stderr silenced" "$(bash_payload "cat $big 2>/dev/null")"
  check deny  "shell: cd && cat large"           "$(bash_payload "cd $WORK && cat $big")"
  check deny  "shell: head large, no count flag" "$(bash_payload "head $big")"
  check allow "shell: head -100 large"           "$(bash_payload "head -100 $big")"
  check allow "shell: sed -n range on large"     "$(bash_payload "sed -n '1,20p' $big")"
  check allow "shell: not a read at all"         "$(bash_payload 'git status')"
  check deny  "shell: cat large among many args" "$(bash_payload "cat $small $big")"
  check deny  "shell: head large under a -3-looking path" "$(bash_payload "head $flagish")"

  # Codex sends argv, wrapped in a login shell, under its own tool names.
  check deny  "codex argv: cat large"            "$(jq -nc --arg c "cat $big" '{tool_name:"shell",tool_input:{command:["bash","-lc",$c]}}')"
  check allow "codex argv: cat small"            "$(jq -nc --arg c "cat $small" '{tool_name:"shell",tool_input:{command:["bash","-lc",$c]}}')"
  check deny  "codex exec_command .cmd"          "$(jq -nc --arg c "cat $big" '{tool_name:"exec_command",tool_input:{cmd:$c}}')"

  # The escape hatches have to work or this is unshippable.
  checked=$((checked + 2))
  if [[ -z $(read_payload "$big" | SHUNT_GUARD_OFF=1 bash "$GUARD") ]]; then
    echo "ok   $HARNESS SHUNT_GUARD_OFF=1 passes through"
  else
    echo "FAIL $HARNESS SHUNT_GUARD_OFF=1 did not pass through"; fail=1
  fi
  if [[ -z $(read_payload "$big" | SHUNT_MIN_LINES=5000 bash "$GUARD") ]]; then
    echo "ok   $HARNESS a raised SHUNT_MIN_LINES passes through"
  else
    echo "FAIL $HARNESS a raised SHUNT_MIN_LINES did not pass through"; fail=1
  fi
done

echo
echo "$checked cases checked"
exit $fail
