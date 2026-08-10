#!/usr/bin/env python3
"""
Warn when resuming a session whose prompt cache has almost certainly expired.

Anthropic's prompt cache offers exactly two TTLs: 5 minutes (the API default)
and 1 hour (`cache_control: {"type": "ephemeral", "ttl": "1h"}`). The TTL is
refreshed at no cost on every cache hit, so the clock runs from the last read -
which is why this measures idle from the last assistant turn.

Claude Code writes to the 1-HOUR cache. Verified from real transcripts, where
every write lands in the 1h bucket and the 5m bucket is always zero:

    "cache_creation": {"ephemeral_5m_input_tokens": 0,
                       "ephemeral_1h_input_tokens": 957}

Hence the 3600s default below - a 300s default would refuse prompts during
coffee-break gaps where the cache is in fact still warm.

The cost asymmetry is what makes a miss worth avoiding. Cache reads bill at
0.1x base input; 1h cache writes bill at 2x. So a lapsed cache does not merely
cost "full price" - re-establishing it costs ~20x what reading it would have.
Bedrock supports both TTLs identically, so this holds there too.

This hook runs on UserPromptSubmit. When the session has been idle past the TTL
AND the context is large enough for the miss to actually hurt, it tells Claude
to compact before doing anything else.

It cannot compact by itself. No hook output triggers compaction - PreCompact
only *reacts* to one. The closest available behaviour is to refuse the prompt,
which is what this does by default: exit 2 blocks the submission and feeds the
reason back, so the session gets compacted before any expensive request goes
out. Set CLAUDE_STALE_BLOCK=0 for advisory mode, which lets the prompt through
and only injects a recommendation.

Inside herdr the refusal can be made self-healing: the pane is addressable, so
the hook types /compact into it and resends the refused prompt once the agent
settles. See autocompact().

Blocking interacts sharply with CLAUDE_CACHE_TTL_SECONDS: at the 300s default,
any five-minute pause on a large session will refuse your next prompt. Raise
the TTL to match the cache you actually have (3600 for extended TTL) or the
block will fire far more often than the cache genuinely lapses.

Everything is derived from the transcript, which already records per-entry
timestamps and real token usage - so there is no state file to drift.

Config (all optional):
  CLAUDE_CACHE_TTL_SECONDS  cache lifetime; default 3600 (Claude Code uses 1h)
  CLAUDE_STALE_MIN_TOKENS   don't bother below this context size; default 200000
  CLAUDE_STALE_BLOCK        "0" for advisory mode; blocking is the default
  CLAUDE_STALE_SETTLE_SECONDS  re-check delay before acting, to let an
                            in-flight /compact finish writing; default 3, 0 off
  CLAUDE_STALE_AUTOCOMPACT  "0" to disable the herdr compact-and-resend
  CLAUDE_HOOKS_DEBUG        "1" to log decisions to stderr
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone

TTL_SECONDS = int(os.getenv("CLAUDE_CACHE_TTL_SECONDS", "3600"))
MIN_TOKENS = int(os.getenv("CLAUDE_STALE_MIN_TOKENS", "200000"))
BLOCK = os.getenv("CLAUDE_STALE_BLOCK", "1") != "0"
DEBUG = os.getenv("CLAUDE_HOOKS_DEBUG", "0") == "1"
SETTLE_SECONDS = float(os.getenv("CLAUDE_STALE_SETTLE_SECONDS", "3"))
AUTOCOMPACT = os.getenv("CLAUDE_STALE_AUTOCOMPACT", "1") != "0"

# Don't auto-compact twice in a row. If the resend is refused again - compaction
# failed, or left the context still over MIN_TOKENS - the pair would otherwise
# recompact and resend forever.
AUTOCOMPACT_COOLDOWN = 300

# Only the tail matters - we want the most recent entries. Transcripts grow to
# many MB and a single entry can be large, so take a generous slice rather than
# reading the whole file on every prompt.
TAIL_BYTES = 1_048_576


def debug(msg):
    if DEBUG:
        print(f"[session-staleness] {msg}", file=sys.stderr)


def tail_entries(path):
    """Yield parsed JSON entries from the tail of a .jsonl transcript, newest first."""
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > TAIL_BYTES:
                f.seek(size - TAIL_BYTES)
                f.readline()  # discard the partial line the seek landed in
            chunk = f.read().decode("utf-8", errors="replace")
    except OSError as e:
        debug(f"cannot read transcript: {e}")
        return

    for line in reversed(chunk.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def parse_ts(value):
    if not value:
        return None
    try:
        # transcripts use e.g. 2026-07-13T01:53:12.376Z
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def inspect(path):
    """Return (idle_seconds, context_tokens). Either may be None if unavailable.

    Both are read from the most recent *assistant* entry, deliberately.

    Anchoring on the last assistant turn is what makes the idle measurement
    correct: it is the last moment the cache was written, so now - that is
    exactly how long the cache has been sitting. Using the newest entry of any
    type would be wrong - Claude Code appends the incoming user prompt and
    various untimestamped metadata entries (last-prompt, mode, ai-title) around
    hook time, so if the user entry lands first the gap would read as ~0 and the
    hook would never fire.

    Scanning stops at a compact boundary. A /compact appends only two records -
    a `system` entry carrying compactMetadata and a `user` entry flagged
    isCompactSummary - and no assistant entry at all. Without this guard the
    walk continues past them onto the *pre-compact* assistant turn and reports
    its stale timestamp and pre-compact token count, so in blocking mode the
    hook refuses the prompt, the user compacts, resubmits, and is refused again
    by the very same entry. Reaching the boundary means the context was just
    rebuilt, which is precisely the not-stale case.
    """
    for entry in tail_entries(path):
        if entry.get("compactMetadata") or entry.get("isCompactSummary"):
            debug("hit compact boundary before any assistant turn; context is fresh")
            return None, None
        if entry.get("type") != "assistant":
            continue

        usage = entry.get("message", {}).get("usage") or {}
        # What the next request would have to re-read. cache_read dominates on a
        # warm session; on a miss the whole lot is billed at the full rate.
        tokens = (
            usage.get("input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0)
            + usage.get("cache_read_input_tokens", 0)
        )
        ts = parse_ts(entry.get("timestamp"))
        if tokens > 0 and ts:
            return (datetime.now(timezone.utc) - ts).total_seconds(), tokens

    return None, None


def autocompact(session_id, prompt):
    """Under herdr, drive the compact-and-resend by hand. True if it was launched.

    The hook has no way to compact directly, but herdr exports the pane holding
    this very Claude, so it can be typed into like any other: /compact, wait for
    the agent to settle, resend the prompt that was just refused.

    Detached, because the parent has to exit(2) now - blocking here would leave
    Claude busy running the hook, and the /compact it is waiting on would sit in
    the input queue behind that. The sleep is the other half of that ordering:
    it lets the refusal land so /compact is submitted to an idle agent, which is
    what makes --wait observe a real working -> idle transition rather than
    matching the completion of the refused turn.
    """
    pane = os.environ.get("HERDR_PANE_ID")
    herdr = shutil.which("herdr")
    if not (AUTOCOMPACT and pane and os.environ.get("HERDR_ENV") == "1" and herdr):
        debug("no herdr pane to drive; leaving the compact to the user")
        return False

    marker = os.path.join(
        tempfile.gettempdir(), f"claude-stale-autocompact-{session_id}"
    )
    try:
        if time.time() - os.path.getmtime(marker) < AUTOCOMPACT_COOLDOWN:
            debug("auto-compact already fired for this session; not retrying")
            return False
    except OSError:
        pass  # no marker yet, or unreadable - either way, go
    open(marker, "w").close()

    subprocess.Popen(
        [
            "/bin/sh",
            "-c",
            # Resend even if the wait fails (herdr answers agent_prompt_stalled
            # when it sees no state change): losing the prompt is worse than
            # queueing it early, and a prompt queued mid-compact is exactly what
            # the settle re-check in main() already covers.
            'sleep 2; "$1" agent prompt "$2" /compact --wait --until idle '
            '--timeout 900000 >/dev/null 2>&1; exec "$1" agent prompt "$2" "$3"',
            "sh",
            herdr,
            pane,
            prompt,
        ],
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    debug(f"auto-compact dispatched to pane {pane}")
    return True


def main():
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)  # not our problem; never break the prompt

    transcript = payload.get("transcript_path")
    if not transcript or not os.path.exists(transcript):
        debug("no transcript path")
        sys.exit(0)

    idle, tokens = inspect(transcript)
    debug(f"idle={idle} tokens={tokens} ttl={TTL_SECONDS} min={MIN_TOKENS}")

    if idle is None or tokens is None:
        sys.exit(0)
    if idle < TTL_SECONDS or tokens < MIN_TOKENS:
        sys.exit(0)

    # The compact boundary guard in inspect() only helps once the records are on
    # disk, and they are not written when compaction finishes - real transcripts
    # show up to ~3s between the summary's own timestamp and the boundary
    # landing. A prompt queued during that window is dequeued mid-flush, so the
    # walk still sees the pre-compact assistant turn and refuses a prompt whose
    # context was in fact just rebuilt. Re-read once after it settles; hitting
    # the boundary makes inspect() return None, which is the not-stale answer.
    if SETTLE_SECONDS > 0:
        time.sleep(SETTLE_SECONDS)
        idle, tokens = inspect(transcript)
        if idle is None or tokens is None or idle < TTL_SECONDS or tokens < MIN_TOKENS:
            debug("compaction landed while settling; context is fresh")
            sys.exit(0)

    idle_min = idle / 60
    ttl_min = TTL_SECONDS / 60
    # Reads bill at 0.1x base input, 1h writes at 2x - so re-establishing a
    # lapsed cache costs ~20x what reading it would have, not merely "full
    # price". Express the delta in base-input-token equivalents.
    wasted = int(tokens * (2.0 - 0.1))
    diagnosis = (
        f"Session has been idle {idle_min:.0f}m, past the {ttl_min:.0f}m prompt-cache "
        f"TTL, and carries ~{tokens:,} tokens of context. The next request is a "
        f"near-certain cache miss: re-writing that context bills at 2x base input "
        f"versus 0.1x to read it cached - roughly {wasted:,} base-input-tokens of "
        f"avoidable spend (~20x the cost of a cache hit)."
    )

    if BLOCK:
        driven = autocompact(
            payload.get("session_id", "unknown"), payload.get("prompt", "")
        )
        recovery = (
            "This prompt was not submitted. Compacting this herdr pane now and "
            "resending it once that finishes - nothing to do."
            if driven
            else "This prompt was not submitted. Run /compact, then send it again."
        )
        # exit 2 = blocking error; the prompt is NOT submitted and stderr is fed
        # back. Say so plainly, or it reads like something went wrong.
        print(
            f"{diagnosis}\n\n"
            f"{recovery}\n"
            f"To send it as-is anyway, set CLAUDE_STALE_BLOCK=0 (advisory mode) "
            f"or raise CLAUDE_CACHE_TTL_SECONDS if your cache TTL is longer than "
            f"{ttl_min:.0f}m.",
            file=sys.stderr,
        )
        sys.exit(2)

    msg = (
        f"{diagnosis}\n\n"
        f"Run /compact before continuing if this session has more work left - it "
        f"pays the miss once and makes everything after it cheap. Skip compacting "
        f"if you only need one more short exchange, since compaction itself has to "
        f"read the full context too."
    )

    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "UserPromptSubmit",
                    "additionalContext": msg,
                },
                "systemMessage": (
                    f"⚠ Stale session: idle {idle_min:.0f}m, ~{tokens:,} tokens "
                    f"of context. Prompt cache likely expired - consider /compact."
                ),
            }
        )
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
