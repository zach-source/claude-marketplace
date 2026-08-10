#!/usr/bin/env bash
# Custom Claude Code status line
# Reads JSON from stdin and formats: Model | Context% (ctx,r) | ⎇ branch | (+adds,-dels)

# Read JSON from stdin
read -r input

# Parse with jq - extract fields
model=$(echo "$input" | jq -r '.model.displayName // .model.name // "Unknown"' 2>/dev/null)
ctx_used=$(echo "$input" | jq -r '.contextWindow.used // 0' 2>/dev/null)
ctx_max=$(echo "$input" | jq -r '.contextWindow.max // 200000' 2>/dev/null)

# Calculate percentage
if [ "$ctx_max" -gt 0 ] 2>/dev/null; then
    ctx_pct=$(awk "BEGIN {printf \"%.1f\", ($ctx_used / $ctx_max) * 100}")
else
    ctx_pct="0.0"
fi

# Get git info from current directory (more reliable than JSON input)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ -n "$branch" ]; then
    # Truncate long branch names
    if [ ${#branch} -gt 20 ]; then
        branch="${branch:0:17}..."
    fi

    # Get staged/unstaged changes
    adds=$(git diff --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
    dels=$(git diff --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')
    staged_adds=$(git diff --cached --numstat 2>/dev/null | awk '{s+=$1} END {print s+0}')
    staged_dels=$(git diff --cached --numstat 2>/dev/null | awk '{s+=$2} END {print s+0}')
    total_adds=$((adds + staged_adds))
    total_dels=$((dels + staged_dels))
fi

# Build status line with colors (ANSI)
# Blue for model, Cyan for context, Green for branch, Yellow for changes
blue=$'\e[38;5;75m'
cyan=$'\e[38;5;80m'
green=$'\e[38;5;114m'
yellow=$'\e[38;5;220m'
gray=$'\e[38;5;245m'
reset=$'\e[0m'

output="${blue}${model}${reset}"
output+="${gray} | ${reset}"
output+="${cyan}${ctx_pct}% (ctx,r)${reset}"

if [ -n "$branch" ]; then
    output+="${gray} | ${reset}"
    output+="${green}⎇ ${branch}${reset}"
    output+="${gray} | ${reset}"
    output+="${yellow}(+${total_adds},-${total_dels})${reset}"
fi

echo "$output"
