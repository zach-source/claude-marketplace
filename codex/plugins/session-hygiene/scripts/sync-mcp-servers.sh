#!/usr/bin/env bash
# sync-mcp-servers.sh
# Ensures ~/.claude.json does NOT contain mcpServers (avoids shadowing ~/.claude/mcp_servers.json)
# Claude Code reads MCP config from ~/.claude/mcp_servers.json (managed by nix)
# Having mcpServers in ~/.claude.json overrides/shadows that file, causing issues
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}i${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}!${NC} $1"; }

CLAUDE_JSON="$HOME/.claude.json"
MCP_SOURCE="$HOME/.claude/mcp_servers.json"

# Verify nix-managed MCP config exists
if [[ ! -f "$MCP_SOURCE" ]]; then
    warning "MCP source not found: $MCP_SOURCE (run 'make apply')"
    exit 0
fi

# Show what's configured in the nix-managed file
SERVER_COUNT=$(jq '.mcpServers | keys | length' "$MCP_SOURCE")
info "MCP servers in ~/.claude/mcp_servers.json: $SERVER_COUNT"
info "Servers: $(jq -r '.mcpServers | keys | join(", ")' "$MCP_SOURCE")"

# Remove mcpServers from ~/.claude.json if present (prevents shadowing)
if [[ -f "$CLAUDE_JSON" ]] && jq -e '.mcpServers' "$CLAUDE_JSON" > /dev/null 2>&1; then
    warning "Removing mcpServers from ~/.claude.json (use ~/.claude/mcp_servers.json instead)"
    TEMP_FILE=$(mktemp)
    jq 'del(.mcpServers)' "$CLAUDE_JSON" > "$TEMP_FILE"
    if jq empty "$TEMP_FILE" 2>/dev/null; then
        /bin/mv "$TEMP_FILE" "$CLAUDE_JSON"
        success "Cleaned mcpServers from ~/.claude.json"
    else
        rm -f "$TEMP_FILE"
        warning "Failed to update ~/.claude.json, skipping"
    fi
else
    success "~/.claude.json clean (no mcpServers to remove)"
fi

success "MCP sync complete - servers managed via ~/.claude/mcp_servers.json"
