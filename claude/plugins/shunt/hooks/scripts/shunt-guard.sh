#!/usr/bin/env bash
# Deny whole-file reads of large files and point the agent at the shunt skill.
#
# Adapted from the shunt plugin in sorantis/portal-ai-plugins, minus its whole
# transport layer. Upstream pipes file *contents* through argv to a
# Spotify-internal AiKA mode; here the cheap worker is an in-harness subagent
# (Agent/Explore on Haiku), so there is nothing to transport and no payload
# ceiling to police.
#
# Dispatches on the *shape* of tool_input rather than the tool name, so the same
# logic serves the Codex copy of this plugin: Codex has no read tool at all — it
# cats files through the shell — and passes its command as an argv array.
#
#   SHUNT_MIN_LINES    deny whole-file reads above this many lines (default 800)
#   SHUNT_GUARD_OFF=1  pass everything through
#   CLAUDE_HOOKS_BIN   colon-separated bin dirs to resolve jq/sed/wc from first
#
# Silence means allow: the hook contract reads an empty exit 0 as "no opinion".
set -uo pipefail

# Same seam as code-quality/context-injection: a pinned deployment (nix) hands
# us exact store binaries, a plain checkout keeps resolving off PATH. Announce a
# bad entry rather than letting it degrade to a silent skip.
if [[ -n "${CLAUDE_HOOKS_BIN:-}" ]]; then
  while IFS= read -r _bin_dir; do
    [[ -z "$_bin_dir" || -d "$_bin_dir" ]] \
      || echo "shunt-guard: CLAUDE_HOOKS_BIN: not a directory: $_bin_dir" >&2
  done <<<"${CLAUDE_HOOKS_BIN//:/$'\n'}"
  export PATH="${CLAUDE_HOOKS_BIN}:${PATH}"
fi

command -v jq >/dev/null 2>&1 || exit 0

min_lines=${SHUNT_MIN_LINES:-800}
[[ $min_lines =~ ^[0-9]+$ ]] || min_lines=800
if [[ ${SHUNT_GUARD_OFF:-0} == 1 ]]; then exit 0; fi

input=$(cat)

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r,
    },
  }'
  exit 0
}

deny_read() {
  deny "shunt: $1 is $2 lines (threshold $min_lines) — do not pull it into this context.
Use the shunt skill: hand the read to a cheap subagent and take back only the answer.
If you need exact text to edit, re-read just the span: Read with offset/limit, or sed -n 'A,Bp'."
}

# Prints the line count when a path is a file that busts the threshold, else fails.
too_big() {
  local n
  [[ -f $1 && -r $1 ]] || return 1
  n=$(wc -l <"$1" 2>/dev/null | tr -d ' ') || return 1
  [[ ${n:-0} =~ ^[0-9]+$ ]] || return 1
  ((n > min_lines)) || return 1
  printf '%s' "$n"
}

# ── Read-tool shape ─────────────────────────────────────────────────────────
# A read carrying offset or limit is already targeted — that is the behaviour
# the deny message asks for, so never fight it.
file_path=$(jq -r '.tool_input.file_path // .tool_input.path // empty' <<<"$input")
targeted=$(jq -r 'if (.tool_input.offset // .tool_input.limit) then "y" else "n" end' <<<"$input")
if [[ -n $file_path ]]; then
  if [[ $targeted == y ]]; then exit 0; fi
  if lines=$(too_big "$file_path"); then deny_read "$file_path" "$lines"; fi
  exit 0
fi

# ── Shell-tool shape ────────────────────────────────────────────────────────
command=$(jq -r '
  (.tool_input.command // .tool_input.cmd // empty)
  | if type == "array" then join(" ") else . end
' <<<"$input")
[[ -n $command ]] || exit 0

# Drop stderr plumbing first: `cat big.ts 2>/dev/null` is a plain read, and
# leaving the 2> in place would make it look like an output redirect below.
command=${command//2>&1/}
command=${command//2>\/dev\/null/}
# Peel a login-shell wrapper (Codex sends ["bash","-lc","cat x"]) so the reader
# lands at the head of a segment.
command=$(sed -E 's/^(env +[A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*(ba|z|)sh +-[a-z]*c +//' <<<"$command")

# Split on && || ; and test each segment's first word. Misses readers hidden in
# $(...) or behind xargs; those are rare enough to leave to the skill.
while IFS= read -r segment; do
  read -r -a argv <<<"$segment" || true
  [[ ${#argv[@]} -gt 1 ]] || continue
  case ${argv[0]} in
    cat | bat | less | more | head | tail) ;;
    *) continue ;;
  esac
  # A pipe or a redirect means the bytes are being filtered or written out, not
  # read into context.
  if [[ $segment == *"|"* || $segment == *">"* ]]; then continue; fi
  # A count flag on head/tail means the read is already bounded. Test the argv
  # tokens, not the whole segment: a path like /build/tmp-3xy would otherwise
  # read as a flag and wave the file straight through.
  if [[ ${argv[0]} == head || ${argv[0]} == tail ]]; then
    for a in "${argv[@]:1}"; do
      case $a in -[0-9]* | -n* | --lines*) continue 2 ;; esac
    done
  fi
  for arg in "${argv[@]:1}"; do
    if [[ $arg == -* ]]; then continue; fi
    arg=${arg%\"}; arg=${arg#\"}
    arg=${arg%\'}; arg=${arg#\'}
    if lines=$(too_big "$arg"); then deny_read "$arg" "$lines"; fi
  done
done < <(sed -E 's/(&&|\|\||;)/\n/g' <<<"$command")

exit 0
