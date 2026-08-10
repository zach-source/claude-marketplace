#!/usr/bin/env bash
#
# Wrapper script for inject_project_docs.py hook
# Injects critical project documentation (STATUS.md, TASKS.md, SESSION_HISTORY.md)
# into Claude's context to ensure they are read before any work begins.
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/inject_project_docs.py"

# Check if the Python script exists
if [[ ! -f "${PYTHON_SCRIPT}" ]]; then
    echo "[ERROR] Python script not found: ${PYTHON_SCRIPT}" >&2
    # Pass through input unchanged if script is missing
    cat
    exit 0
fi

# Use the nix Python with required packages
# We need sentence-transformers for consistency with other hooks
exec /usr/bin/env python3 "${PYTHON_SCRIPT}"