#!/usr/bin/env python3
"""End-to-end check for session-staleness.py's herdr compact-and-resend.

Runs the hook against a synthetic stale transcript with a fake `herdr` on PATH,
and asserts it refuses the prompt (exit 2) while dispatching /compact and then
the refused prompt to the pane named by HERDR_PANE_ID.

Ported from the dotfiles copy this plugin was extracted from, so the hook keeps
the coverage it had there. Only the path to the hook changed - it lives under
hooks/scripts/ here rather than beside the test.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOOK = Path(__file__).parent / "hooks" / "scripts" / "session-staleness.py"
PROMPT = "the refused prompt"


def test_autocompact_dispatches_compact_then_resend(tmp_path):
    stale = datetime.now(timezone.utc) - timedelta(hours=2)
    transcript = tmp_path / "t.jsonl"
    transcript.write_text(
        json.dumps(
            {
                "type": "assistant",
                "timestamp": stale.isoformat().replace("+00:00", "Z"),
                "message": {"usage": {"cache_read_input_tokens": 300_000}},
            }
        )
        + "\n"
    )

    calls = tmp_path / "calls.log"
    bindir = tmp_path / "bin"
    bindir.mkdir()
    herdr = bindir / "herdr"
    herdr.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> {calls}\n')
    herdr.chmod(0o755)

    env = {
        **os.environ,
        "PATH": f"{bindir}:{os.environ['PATH']}",
        "HERDR_ENV": "1",
        "HERDR_PANE_ID": "w9:p1",
        "CLAUDE_STALE_SETTLE_SECONDS": "0",  # nothing is racing us here
        "TMPDIR": str(tmp_path),  # keep the once-per-session marker out of /tmp
    }
    proc = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps(
            {
                "transcript_path": str(transcript),
                "session_id": "test-session",
                "prompt": PROMPT,
            }
        ),
        capture_output=True,
        text=True,
        env=env,
    )

    assert proc.returncode == 2, proc.stderr
    assert "resending" in proc.stderr

    # The dispatch is detached and sleeps before typing, so poll rather than
    # assume it has run by the time the hook exits.
    for _ in range(80):
        if calls.exists() and len(calls.read_text().splitlines()) == 2:
            break
        time.sleep(0.1)

    compact, resend = calls.read_text().splitlines()
    assert compact.startswith("agent prompt w9:p1 /compact --wait --until idle")
    assert resend == f"agent prompt w9:p1 {PROMPT}"


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as d:
        test_autocompact_dispatches_compact_then_resend(Path(d))
    print("ok   session-staleness dispatches /compact then resends the prompt")
