#!/usr/bin/env bash
# Does smart-lint respect the project's own formatter configuration?
#
# Every fixture is a project whose config says the file is FINE. The hook is
# invoked the way a PostToolUse hook actually is - from an unrelated working
# directory - so anything that resolves config from cwd (flake8, prettier's
# ignore file) fails here unless the hook moves to the project root first.
#
# Pre-fix, 5 of these 7 failed.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hooks/scripts/smart-lint.sh"
W=$(mktemp -d)
OUTSIDE=$(mktemp -d)
trap 'rm -rf "$W" "$OUTSIDE"' EXIT

fails=0

# Runs the hook from $OUTSIDE and reports whether it accepted the file.
# want=accept -> exit 0, want=reject -> exit 2
check() {
  local want="$1" desc="$2" target="$3" rc
  (cd "$OUTSIDE" && printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$target" |
    bash "$HOOK" >/dev/null 2>&1)
  rc=$?
  if { [[ "$want" == accept && $rc -eq 0 ]] || [[ "$want" == reject && $rc -eq 2 ]]; }; then
    printf '  ok    %s\n' "$desc"
  else
    printf '  FAIL  %-46s (exit %s, wanted %s)\n' "$desc" "$rc" "$want"
    fails=$((fails + 1))
  fi
}

skip_or() { # skip the case when the checker is not installed
  # Through CLAUDE_HOOKS_BIN, not the bare PATH: that is how the hook resolves
  # its checkers, and a pinned install has them nowhere else.
  PATH="${CLAUDE_HOOKS_BIN:-}:$PATH" command -v "$1" >/dev/null 2>&1 && return 1
  printf '  skip  %s (%s not installed)\n' "$2" "$1"
  return 0
}

# A permissive flake8 config, for fixtures that are testing black. Both run on
# .py, so without this the fixture's deliberately odd spacing trips flake8 and
# the case fails for a reason it was not asking about.
ignore_flake8() {
  printf '[flake8]\nmax-line-length = 500\nextend-ignore = E2,E3,E5,W2,W3\n' >"$1/setup.cfg"
}

echo "project config is honoured:"

# flake8 reads setup.cfg from the CURRENT directory, not the file's.
if ! skip_or flake8 "flake8 max-line-length from setup.cfg"; then
  mkdir -p "$W/py"
  printf '[flake8]\nmax-line-length = 200\n' >"$W/py/setup.cfg"
  printf 'x = "%s"\n' "$(printf 'a%.0s' {1..120})" >"$W/py/long.py"
  check accept "flake8 max-line-length from setup.cfg" "$W/py/long.py"
fi

if ! skip_or black "black line-length from pyproject.toml"; then
  mkdir -p "$W/blk"
  printf '[tool.black]\nline-length = 200\n' >"$W/blk/pyproject.toml"
  ignore_flake8 "$W/blk"
  printf 'xxxx = {"a": 1, "b": 2, "c": 3, "d": 4, "e": 5, "f": 6, "g": 7, "h": 8, "i": 9, "j": 10}\n' >"$W/blk/w.py"
  check accept "black line-length from pyproject.toml" "$W/blk/w.py"

  mkdir -p "$W/exc"
  # TOML literal string: in a basic string \. is an illegal escape and black
  # dies parsing the config rather than applying it.
  printf "[tool.black]\nforce-exclude = 'generated_.*\\\\.py'\n" >"$W/exc/pyproject.toml"
  ignore_flake8 "$W/exc"
  printf 'x  =  1\n' >"$W/exc/generated_pb2.py"
  check accept "black force-exclude" "$W/exc/generated_pb2.py"
fi

if ! skip_or prettier "prettier .prettierignore"; then
  mkdir -p "$W/js"
  printf '{}\n' >"$W/js/package.json"
  printf 'vendor.js\n' >"$W/js/.prettierignore"
  printf 'const x   =   1\n' >"$W/js/vendor.js"
  check accept "prettier .prettierignore" "$W/js/vendor.js"
fi

if ! skip_or rustfmt "rustfmt edition from Cargo.toml"; then
  mkdir -p "$W/rs/src"
  printf '[package]\nname = "p"\nedition = "2021"\n' >"$W/rs/Cargo.toml"
  printf 'async fn f() {}\n\nfn g(_: &dyn std::fmt::Debug) {}\n' >"$W/rs/src/lib.rs"
  check accept "rustfmt edition from Cargo.toml" "$W/rs/src/lib.rs"
fi

# A treefmt project has chosen its formatter; nixfmt must not overrule it.
mkdir -p "$W/nx"
printf 'projectRootFile = "flake.nix"\n' >"$W/nx/treefmt.toml"
printf '{\n  x = {a = 1;};\n}\n' >"$W/nx/f.nix"
check accept "nix skipped when project declares treefmt" "$W/nx/f.nix"

echo "and a genuinely bad file is still caught:"

# No project config anywhere: our defaults apply and must still fire.
if ! skip_or black "unconfigured project still rejects bad python"; then
  mkdir -p "$W/bare"
  printf '{}\n' >"$W/bare/package.json" # marker only, no python config
  printf 'x  =  1\n' >"$W/bare/bad.py"
  check reject "unconfigured project still rejects bad python" "$W/bare/bad.py"
fi

if command -v nixfmt >/dev/null 2>&1; then
  mkdir -p "$W/nx2"
  printf '{}\n' >"$W/nx2/package.json"
  printf '{\n  x = {a = 1;};\n}\n' >"$W/nx2/bad.nix"
  check reject "no treefmt config, nixfmt still checks" "$W/nx2/bad.nix"
fi

if [[ $fails -gt 0 ]]; then
  echo "FAILED: $fails case(s)"
  exit 1
fi
echo "PASS"
