#!/usr/bin/env bash
# PreToolUse: pull relevant prior-session context back out of qdrant.
#
# Two impedance mismatches with `claude-vector retrieve --json`, both handled here
# rather than in the CLI, which is nix-managed and shared with the Claude tree:
#
#   1. It reads the query from `tool`/`arguments`, but the hook payload carries
#      `tool_name`/`tool_input`. The query came out empty on every call, so the
#      CLI answered "No query provided for vector retrieval." We extract the
#      query ourselves and hand it the `{"query": ...}` shape it understands.
#
#   2. It prints {"role","content"}, which is not a Codex hook protocol. On
#      PreToolUse, stdout only reaches the model as
#      hookSpecificOutput.additionalContext - anything else is dropped.
#
# Both bugs were silent: the hook exited 0 and looked healthy while retrieving
# nothing and injecting nothing.
set -uo pipefail

payload="$(cat)"

# First non-empty field that reads like intent. Order matters: an explicit
# prompt/query beats a command string. Codex routes shell and edits through
# tool_input.command; prompt/query/description cover agent and MCP tools.
query="$(jq -r '
  [ .tool_input.prompt,
    .tool_input.query,
    .tool_input.description,
    .tool_input.command ]
  | map(select(type == "string" and . != ""))
  | first // ""
' <<<"$payload" 2>/dev/null)"

if [[ -z "$query" ]]; then
  exit 0
fi

# stderr is noisy (model weight loading); it only reaches the debug log anyway.
content="$(jq -nc --arg q "$query" '{query: $q}' \
  | claude-vector retrieve --json 2>/dev/null \
  | jq -r '.content // ""' 2>/dev/null)"

# Nothing useful to say is not a failure - stay quiet rather than burn context.
if [[ -z "$content" || "$content" == "No relevant context found." || "$content" == No\ query\ provided* ]]; then
  exit 0
fi

jq -nc --arg c "$content" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $c
  }
}'
