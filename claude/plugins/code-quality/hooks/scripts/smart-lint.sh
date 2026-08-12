#!/usr/bin/env bash
set +e  # Don't use set -e - we need to control exit codes carefully

# Source common helpers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common-helpers.sh"

# Get the payload
payload="$(cat)"
tool_name=$(jq -r '.tool_name' <<<"$payload" 2>/dev/null || echo "")

# Only run on write operations
[[ "$tool_name" =~ ^(Write|Edit|MultiEdit)$ ]] || exit 0

# Get the file that was modified.
#
# tool_response is not always an object: ~2% of real Edit/Write results come back
# as a plain string. `.tool_response.filePath` then errors out ("cannot index
# string"), which aborts the whole expression before `//` can reach the
# tool_input fallback - so the hook skipped linting entirely on those calls,
# silently and at exit 0. The `?` keeps an unindexable tool_response from taking
# the fallback down with it.
file=$(jq -r '
  [ .tool_response.filePath?, .tool_input.file_path ]
  | map(select(type == "string" and . != ""))
  | first // empty
' <<<"$payload" 2>/dev/null || echo "")
[[ -z "$file" || ! -f "$file" ]] && exit 0

# Configuration from environment
CLAUDE_HOOKS_LINT_ENABLED="${CLAUDE_HOOKS_LINT_ENABLED:-true}"
[[ "$CLAUDE_HOOKS_LINT_ENABLED" != "true" ]] && exit 0

# Absolutise before the cd below, or a relative path stops resolving.
file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"

# Run every checker from the project root, so the ones that read their config
# from the current directory - flake8, and prettier for .prettierignore - see the
# project's settings instead of our defaults. Measured before this: a setup.cfg
# raising max-line-length and a .prettierignore listing the file were both
# ignored outright.
project_dir="$(project_root "$file")"
cd "$project_dir" || exit 0
log_debug "checking $file from $project_dir"

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
      # rustfmt does not read Cargo.toml, and standalone it assumes edition
      # 2015 - which cannot even parse `async fn` or `dyn Trait`. Every 2018+
      # crate therefore came back "badly formatted" when it was only unparseable.
      # rustfmt.toml is found from the file's own path, so that part was already
      # right; only the edition has to be handed over.
      edition=$(sed -n 's/^[[:space:]]*edition[[:space:]]*=[[:space:]]*"\([0-9]*\)".*/\1/p' \
        "$project_dir/Cargo.toml" 2>/dev/null | head -1)
      if rustfmt --check ${edition:+--edition "$edition"} "$file" >&2; then
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
    # A project that declares its own formatter has already answered this
    # question. treefmt is usually pointed at alejandra or nixpkgs-fmt, whose
    # output nixfmt rejects wholesale - so checking anyway means reporting a
    # correctly formatted file as broken on every single edit. Defer instead of
    # reformatting: running treefmt here would rewrite the file, and this hook
    # has never written to the tree.
    if [[ -f treefmt.toml || -f .treefmt.toml || -f treefmt.nix ]]; then
      log_debug "project declares its own formatter (treefmt); skipping nixfmt"
    elif command_exists nixfmt && [[ -f "$file" ]]; then
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