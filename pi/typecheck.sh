#!/usr/bin/env bash
# Typecheck the extensions against the Pi types of whichever pi build is
# installed. The published package has been renamed more than once
# (@mariozechner -> @earendil-works, plus the @oh-my-pi fork), while the
# extensions keep importing the original name - so the path is resolved here
# rather than pinned in tsconfig.json. `paths` cannot be set on the tsc command
# line (TS6064), hence the generated config.
set -euo pipefail

cd "$(dirname "$0")"

root=$(npm root -g 2>/dev/null || echo "")
entry=""
for pkg in @earendil-works/pi-coding-agent @mariozechner/pi-coding-agent; do
	if [[ -f "$root/$pkg/dist/index.d.ts" ]]; then
		entry="$root/$pkg/dist/index.d.ts"
		break
	fi
done

if [[ -z $entry ]]; then
	echo "No pi-coding-agent install found under $root - install pi first." >&2
	exit 1
fi

generated=.tsconfig.typecheck.json
trap 'rm -f "$generated"' EXIT
cat >"$generated" <<EOF
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "paths": { "@mariozechner/pi-coding-agent": ["$entry"] }
  }
}
EOF

tsc -p "$generated"
