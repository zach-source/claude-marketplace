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