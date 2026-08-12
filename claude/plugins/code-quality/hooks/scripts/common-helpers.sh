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

# Nearest ancestor directory of $1 that looks like a project root.
#
# Checkers disagree about where configuration lives. black and prettier resolve
# their config by walking up from the FILE, but flake8 reads setup.cfg/.flake8/
# tox.ini from the CURRENT DIRECTORY, and prettier looks for .prettierignore
# there too. A hook inherits whatever cwd the harness happened to have, so those
# two silently ignored the project's own settings and reported violations of our
# defaults instead. Running every checker from here fixes that class at once.
#
# Nearest marker wins, not outermost: in a monorepo the sub-package's
# package.json or pyproject.toml is the config that governs the file, which is
# the same rule the tools themselves use.
project_root() {
  local dir marker
  dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd) || return 1
  while [[ "$dir" != "/" ]]; do
    for marker in .git flake.nix treefmt.toml .treefmt.toml package.json \
      pyproject.toml setup.cfg .flake8 tox.ini Cargo.toml go.mod; do
      if [[ -e "$dir/$marker" ]]; then
        printf '%s\n' "$dir"
        return 0
      fi
    done
    dir=$(dirname "$dir")
  done
  dirname "$1"
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