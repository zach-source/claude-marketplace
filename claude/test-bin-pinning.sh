#!/usr/bin/env bash
# CLAUDE_HOOKS_BIN is the seam that lets a pinned deployment (nix) hand these
# hooks exact store binaries while a plain checkout keeps resolving off PATH.
#
# It needs a test because the failure is invisible in production: hooks inherit
# no interactive shell PATH, and command_exists turns a miss into a silent skip
# at exit 0. A checker that never ran and one that passed look identical from
# outside - which black actually ran is exactly what cannot be observed later.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

LINT=claude/plugins/code-quality/hooks/scripts/smart-lint.sh
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail=0
check() { # name expected-substring actual
  if [[ "$3" == *"$2"* ]]; then echo "ok   $1"
  else echo "FAIL $1: wanted '*$2*', got '$3'"; fail=1; fi
}
check_empty() { # name actual
  if [[ -z "$2" ]]; then echo "ok   $1"
  else echo "FAIL $1: wanted empty, got '$2'"; fail=1; fi
}

# Two black stubs that are distinguishable only by what they record. Whichever
# one the hook resolves writes its own name.
stub() { # dir label
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho %s >> "%s"\nexit 0\n' "$2" "$WORK/ran" >"$1/black"
  chmod +x "$1/black"
}
stub "$WORK/pinned" PINNED
stub "$WORK/decoy" DECOY

printf 'x = 1\n' >"$WORK/demo.py"
payload=$(jq -nc --arg f "$WORK/demo.py" '{tool_name:"Write",tool_input:{file_path:$f}}')

# The decoy is always on PATH, standing in for an ambient checker - on this
# machine bare `black` really does resolve to /opt/homebrew/bin/black.
run() { # [env assignments...] -> sets $out and $err
  : >"$WORK/ran"
  out=$(env PATH="$WORK/decoy:$PATH" "$@" bash "$LINT" <<<"$payload" 2>"$WORK/err")
  err=$(cat "$WORK/err")
  ran=$(cat "$WORK/ran")
}

# --- the prefix wins over whatever is ambient on PATH -----------------------
run CLAUDE_HOOKS_BIN="$WORK/pinned"
check "prefix takes precedence over PATH" "PINNED" "$ran"
check_empty "pinned run writes nothing to stdout" "$out"

# --- unset: a plain checkout still resolves off PATH ------------------------
run
check "unset falls back to PATH" "DECOY" "$ran"
check_empty "fallback run writes nothing to stdout" "$out"

# --- a prefix entry that is not a directory is announced, not swallowed -----
run CLAUDE_HOOKS_BIN="$WORK/typo-not-a-dir"
check "bad prefix entry is reported on stderr" "not a directory" "$err"
check_empty "bad prefix still writes nothing to stdout" "$out"
# Reporting it must not stop the hook doing its job off the remaining PATH.
check "bad prefix still lints via PATH" "DECOY" "$ran"

# --- a multi-entry prefix behaves like a real makeBinPath -------------------
# A real one has several dirs and most hold none of the checkers, so an entry
# that exists but has no match must fall through rather than end the search.
mkdir -p "$WORK/empty-a"
run CLAUDE_HOOKS_BIN="$WORK/empty-a:$WORK/pinned"
check "later entry resolves when earlier has no match" "PINNED" "$ran"
# Not check_empty: stderr legitimately carries the checker's own [OK] line. What
# must be absent is the misconfiguration complaint.
if [[ "$err" != *"not a directory"* ]]; then
  echo "ok   a prefix of real dirs raises no complaint"
else
  echo "FAIL a prefix of real dirs complained: $err"; fail=1
fi

exit $fail
