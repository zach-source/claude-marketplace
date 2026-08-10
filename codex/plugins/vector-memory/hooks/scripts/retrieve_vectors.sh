#!/usr/bin/env bash
# PreToolUse: pull relevant prior-session context back out of qdrant.
#
# Codex ignores plain stdout on PreToolUse - context only reaches the model via
# hookSpecificOutput.additionalContext. claude-vector emits its own
# {"role","content"} shape, so rewrap it here. Empty and "no results" responses
# are dropped so the model is not handed filler.
set -euo pipefail

claude-vector retrieve --json 2>/dev/null \
  | jq -c 'select(type == "object")
           | select(.content != null and .content != "")
           | select(.content | test("^No relevant context found\\.$|^No query provided") | not)
           | {hookSpecificOutput: {
               hookEventName: "PreToolUse",
               additionalContext: .content
             }}'
