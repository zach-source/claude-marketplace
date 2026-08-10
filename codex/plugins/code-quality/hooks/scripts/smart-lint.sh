#!/usr/bin/env bash
set +e  # Don't use set -e - we need to control exit codes carefully

# Source common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-helpers.sh"

# Get the payload
payload="$(cat)"
tool_name=$(jq -r '.tool_name' <<<"$payload" 2>/dev/null || echo "")

# Only run on write operations. Codex reports edits as apply_patch - Edit/Write
# are matcher aliases only and never appear in the payload.
[[ "$tool_name" =~ ^(apply_patch|Write|Edit)$ ]] || exit 0

# Get the file that was modified. apply_patch carries the whole patch as one
# string in tool_input.command with no structured path field, so read the paths
# off the patch envelope. Falls back to the structured fields.
#
# Every access is type-guarded. tool_response is documented only as "tool-specific
# output" and is not always an object; indexing a string raises a jq error that
# aborts the whole expression, taking the `//` fallbacks down with it - which is
# how the correct path gets thrown away while the hook still exits 0.
file=$(jq -r '
  [ (.tool_response? | objects | .filePath?),
    (.tool_input?    | objects | .file_path?) ]
  | map(select(type == "string" and . != ""))
  | first // ""
' <<<"$payload" 2>/dev/null || echo "")

if [[ -z "$file" ]]; then
  patch=$(jq -r '.tool_input? | objects | .command? | strings // ""' <<<"$payload" 2>/dev/null || echo "")
  # *** Add File: p / *** Update File: p / *** Move to: p - lint the last one touched.
  file=$(grep -oE '^\*\*\* (Add|Update|Move to) File: .+$|^\*\*\* Move to: .+$' <<<"$patch" 2>/dev/null \
         | sed -E 's/^\*\*\* [A-Za-z ]+: //' | tail -1)
fi

[[ -z "$file" || ! -f "$file" ]] && exit 0

# Configuration from environment
CLAUDE_HOOKS_LINT_ENABLED="${CLAUDE_HOOKS_LINT_ENABLED:-true}"
[[ "$CLAUDE_HOOKS_LINT_ENABLED" != "true" ]] && exit 0

# Track errors
declare -a ERRORS=()

# Function to add error
add_error() {
  ERRORS+=("$1")
  log_error "$1"
}

# Get file extension
filename=$(basename "$file")
extension="${filename##*.}"

# Lint based on file type
case "$extension" in
  go)
    if command_exists gofmt && [[ -f "$file" ]]; then
      if ! gofmt -l "$file" | grep -q .; then
        log_success "Go formatting OK: $file"
      else
        add_error "Go formatting issues in $file"
        gofmt -d "$file" >&2
      fi
    fi
    # Run go vet on the package containing the edited file
    if command_exists go && [[ -f "$file" ]]; then
      pkg_dir=$(dirname "$file")
      if [[ -f "$pkg_dir/go.mod" ]] || (cd "$pkg_dir" && go env GOMOD 2>/dev/null | grep -q .); then
        if go vet "$pkg_dir/..." >&2; then
          log_success "Go vet OK: $file"
        else
          add_error "Go vet issues in $file"
        fi
      fi
    fi
    ;;
    
  py)
    if command_exists black && [[ -f "$file" ]]; then
      if black --check --quiet "$file" >&2; then
        log_success "Python formatting OK: $file"
      else
        add_error "Python formatting issues in $file (run black to fix)"
      fi
    fi
    
    if command_exists flake8 && [[ -f "$file" ]]; then
      if flake8 "$file" >&2; then
        log_success "Python linting OK: $file"
      else
        add_error "Python linting issues in $file"
      fi
    fi
    ;;
    
  js|jsx|ts|tsx)
    if command_exists prettier && [[ -f "$file" ]]; then
      if prettier --check "$file" >&2; then
        log_success "JavaScript formatting OK: $file"
      else
        add_error "JavaScript formatting issues in $file"
      fi
    fi
    ;;
    
  rs)
    if command_exists rustfmt && [[ -f "$file" ]]; then
      if rustfmt --check "$file" >&2; then
        log_success "Rust formatting OK: $file"
      else
        add_error "Rust formatting issues in $file"
      fi
    fi
    ;;
    
  yaml|yml)
    # Validate YAML syntax to catch structural errors early
    # Use yq (preferred) to avoid requiring PyYAML in the hook runtime.
    if command_exists yq && [[ -f "$file" ]]; then
      if yq e '.' "$file" >/dev/null 2>&1; then
        log_success "YAML syntax OK: $file"
      else
        add_error "YAML syntax error in $file"
      fi
    fi
    ;;

  nix)
    if command_exists nixfmt && [[ -f "$file" ]]; then
      if nixfmt --check "$file" >&2; then
        log_success "Nix formatting OK: $file"
      else
        add_error "Nix formatting issues in $file"
      fi
    fi
    ;;
esac

# Summary
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo -e "\n${RED}✗ Code quality check failed${NC}" >&2
  echo -e "${RED}Found ${#ERRORS[@]} issue(s) that must be fixed:${NC}" >&2
  for error in "${ERRORS[@]}"; do
    echo -e "  ${RED}•${NC} $error" >&2
  done
  exit 2
fi

exit 0