#!/usr/bin/env bash
# Common helpers shared by all hooks

# Color definitions
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Logging functions
log_debug() {
  [[ "${CLAUDE_HOOKS_DEBUG:-0}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" >&2
}

log_info() {
  echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
  echo -e "${GREEN}[OK]${NC} $*" >&2
}

# Command existence check
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Binary resolution.
#
# A pinned deployment (nix) needs the exact store binaries; a plain checkout has
# to keep working off whatever is on PATH. One prefix serves both: set
# CLAUDE_HOOKS_BIN to a colon-separated list of bin directories - in nix,
# `lib.makeBinPath [ coreutils jq go black ... ]` - and every command resolves
# there first. Unset, nothing changes, so a PATH user needs no configuration.
#
# It has to be a prefix rather than a per-command variable because hooks inherit
# no interactive shell PATH, and command_exists turns a miss into a silent skip
# at exit 0 - a checker that was never found and one that passed look identical
# from outside. Pinning the search path fixes that for every command at once,
# including ones added later.
#
# An entry that is not a directory is reported, not ignored: that is exactly the
# case where a "pinned" checker quietly reverts to the ambient one.
if [[ -n "${CLAUDE_HOOKS_BIN:-}" ]]; then
  while IFS= read -r _hook_bin_dir; do
    [[ -z "$_hook_bin_dir" || -d "$_hook_bin_dir" ]] \
      || log_error "CLAUDE_HOOKS_BIN: not a directory: $_hook_bin_dir"
  done <<<"${CLAUDE_HOOKS_BIN//:/$'\n'}"
  export PATH="${CLAUDE_HOOKS_BIN}:${PATH}"
fi