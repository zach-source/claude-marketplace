#!/usr/bin/env python3
"""Tests for ste-check.py. A stub HTTP server stands in for Jev.

Run: python3 claude/plugins/asd-ste100/test-ste-check.py
"""

import http.server
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

HOOK = Path(__file__).parent / "hooks" / "scripts" / "ste-check.py"
spec = importlib.util.spec_from_file_location("ste", HOOK)
ste = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ste)

BAD = (
    "The configuration file is loaded by the daemon when it starts, and then "
    "it is parsed and validated before any of the workers are started up. "
    "Utilize the flag."
)
GOOD = "Open the valve. Set the pressure to 5 bar. If the pressure is high, stop."


def stub_jev(score):
    """Start a fake Jev that answers `score` and records each request."""
    seen = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            seen.append((self.headers, body))
            out = json.dumps({"answers": {"ste": {"type": "noul", "noul": score}}})
            self.send_response(200)
            self.end_headers()
            self.wfile.write(out.encode())

        def log_message(self, *_):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_port}/v1/systemone", seen, server


def run(tool_input, tool_response=None, **env):
    clean = {k: v for k, v in os.environ.items() if not k.startswith(("STE_", "CF_"))}
    # The samples are short, so turn off the minimum length unless a test sets it.
    # A missing judge CLI and a fresh TMPDIR (the Jev circuit breaker lives
    # there) keep each test away from the real `claude` and from the others.
    env = {
        "STE_JEV_MIN_WORDS": "0",
        "STE_JUDGE_CLI": "/nonexistent",
        "TMPDIR": tempfile.mkdtemp(),
        **env,
    }
    payload = {"tool_input": tool_input, "tool_response": tool_response or {}}
    proc = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        check=True,
        env={**clean, **env},
    )
    return proc.stdout


def context(stdout):
    return json.loads(stdout)["hookSpecificOutput"]["additionalContext"]


def test_local_rules():
    found = ste.check(ste.prose_of("a.md", BAD))
    assert any("-word sentence" in f for f in found)
    assert any("passive voice" in f for f in found)
    assert any('"utilize" -> use' in f for f in found)
    assert ste.check(ste.prose_of("a.md", GOOD)) == []


def test_code_only_checks_comments():
    code = 'x = "utilize this string"\n# Utilize the cache.\n'
    assert ste.check(ste.prose_of("a.py", code)) == ['"utilize" -> use']


def test_skips_code_fences_and_inline_code():
    md = "Run `utilize --now`.\n\n```\nit is loaded via magic\n```\n"
    assert ste.check(ste.prose_of("a.md", md)) == []


def test_no_key_reports_local_findings_only():
    out = run({"file_path": "a.md", "content": BAD})
    assert context(out).startswith("ASD-STE100 local check on a.md")
    assert run({"file_path": "a.md", "content": GOOD}) == ""


def test_jev_pass_is_silent_even_with_local_findings():
    url, seen, server = stub_jev(0.9)
    try:
        assert (
            run({"file_path": "a.md", "content": BAD}, STE_JEV_KEY="k", STE_JEV_URL=url)
            == ""
        )
    finally:
        server.shutdown()
    assert len(seen) == 1


def test_jev_fail_asks_for_skill_review_with_headers():
    url, seen, server = stub_jev(0.15)
    try:
        out = run(
            {"file_path": "doc.md", "edits": [{"new_string": BAD}]},
            STE_JEV_KEY="k",
            STE_JEV_URL=url,
            CF_ACCESS_CLIENT_ID="id",
            CF_ACCESS_CLIENT_SECRET="secret",
        )
    finally:
        server.shutdown()
    msg = context(out)
    assert (
        "Jev scored the text you wrote in doc.md 0.15, the mean of 1 paragraph" in msg
    )
    assert "asd-ste100 skill" in msg and '"utilize" -> use' in msg
    headers, body = seen[0]
    assert headers["Authorization"] == "Bearer k"
    assert not headers["User-Agent"].startswith("Python-urllib")
    assert headers["CF-Access-Client-Id"] == "id"
    assert body["questions"]["ste"]["type"] == "noul"


def test_many_failing_paragraphs_hand_off_to_haiku_rewriter():
    url, seen, server = stub_jev(0.2)
    text = "\n\n".join([BAD] * 3)
    try:
        out = run(
            {"file_path": "/docs/guide.md", "content": text},
            STE_JEV_KEY="k",
            STE_JEV_URL=url,
        )
    finally:
        server.shutdown()
    msg = context(out)
    assert 'subagent_type "asd-ste100:ste-rewriter"' in msg
    assert "/docs/guide.md" in msg and "3 paragraphs are under the pass mark" in msg


def fake_judge(tmp, scores, out_tokens=500):
    """Write a fake `claude` that answers like `claude -p --output-format json`."""
    log = Path(tmp) / "judge.log"
    cli = Path(tmp) / "claude"
    reply = {
        "result": json.dumps(scores),
        "modelUsage": {"claude-haiku-5-5": {"outputTokens": out_tokens}},
    }
    cli.write_text(
        "#!/bin/sh\n"
        f'printf "%s\\n" "$CLAUDE_STE_DISABLE $*" >> {log}\n'
        f"echo '{json.dumps(reply)}'\n"
    )
    cli.chmod(0o755)
    return str(cli), log


# A configured Jev route that does not answer: an outage.
DEAD = {
    "STE_JEV_KEY": "k",
    "STE_JEV_URL": "http://127.0.0.1:9/x",
    "STE_JEV_TIMEOUT": "1",
}


def test_jev_outage_uses_haiku_judge_in_isolation():
    with tempfile.TemporaryDirectory() as d:
        cli, log = fake_judge(d, [0.3])
        out = run({"file_path": "a.md", "content": BAD}, STE_JUDGE_CLI=cli, **DEAD)
        call = log.read_text()
    msg = context(out)
    assert "Claude Haiku 5.5 (Jev unavailable) scored" in msg and "0.30" in msg
    assert call.startswith("1 ")  # CLAUDE_STE_DISABLE=1: no recursion
    assert "--model claude-haiku-5-5" in call and "--tools" in call


def test_haiku_judge_pass_is_silent():
    with tempfile.TemporaryDirectory() as d:
        cli, _ = fake_judge(d, [0.99])
        out = run(
            {"file_path": "a.md", "content": GOOD + " " + GOOD},
            STE_JUDGE_CLI=cli,
            **DEAD,
        )
        assert out == ""


def test_short_or_malformed_judge_reply_degrades_to_local_rules():
    with tempfile.TemporaryDirectory() as d:
        for scores, tokens in (([0.3], 20), ([0.3, 0.4], 500), (["x"], 500)):
            cli, _ = fake_judge(d, scores, tokens)
            out = run({"file_path": "a.md", "content": BAD}, STE_JUDGE_CLI=cli, **DEAD)
            assert context(out).startswith("ASD-STE100 local check"), scores


def test_judge_can_be_turned_off():
    with tempfile.TemporaryDirectory() as d:
        cli, log = fake_judge(d, [0.3])
        out = run(
            {"file_path": "a.md", "content": BAD},
            STE_JUDGE_CLI=cli,
            STE_JUDGE="0",
            **DEAD,
        )
        assert not log.exists()
    assert context(out).startswith("ASD-STE100 local check")


def test_jev_failure_opens_breaker_and_skips_jev_next_time():
    url, seen, server = stub_jev(0.9)
    with tempfile.TemporaryDirectory() as d:
        cli, _ = fake_judge(d, [0.3])
        tmp = tempfile.mkdtemp()
        dead = {
            "STE_JEV_KEY": "k",
            "STE_JEV_URL": "http://127.0.0.1:9/x",
            "STE_JEV_TIMEOUT": "1",
        }
        run(
            {"file_path": "a.md", "content": BAD}, STE_JUDGE_CLI=cli, TMPDIR=tmp, **dead
        )
        try:
            out = run(
                {"file_path": "a.md", "content": BAD},
                STE_JUDGE_CLI=cli,
                TMPDIR=tmp,
                STE_JEV_KEY="k",
                STE_JEV_URL=url,
            )
        finally:
            server.shutdown()
    assert seen == []  # the breaker skipped the working Jev
    assert "Claude Haiku 5.5 (Jev unavailable)" in context(out)


def test_no_jev_key_means_no_judge():
    with tempfile.TemporaryDirectory() as d:
        cli, log = fake_judge(d, [0.3])
        out = run({"file_path": "a.md", "content": BAD}, STE_JUDGE_CLI=cli)
        assert not log.exists()
    assert context(out).startswith("ASD-STE100 local check")


def test_judge_skips_code_comments():
    with tempfile.TemporaryDirectory() as d:
        cli, log = fake_judge(d, [0.3])
        code = "\n".join("# " + line for line in BAD.split(". "))
        run({"file_path": "a.py", "content": code}, STE_JUDGE_CLI=cli, **DEAD)
        assert not log.exists()


def test_direct_route_answers_when_gateway_is_down_without_cf_headers():
    url, seen, server = stub_jev(0.9)
    try:
        out = run(
            {"file_path": "a.md", "content": BAD},
            STE_JEV_DIRECT_KEY="apikey_x",
            STE_JEV_DIRECT_URL=url,
            CF_ACCESS_CLIENT_ID="id",
            CF_ACCESS_CLIENT_SECRET="secret",
            **DEAD,
        )
    finally:
        server.shutdown()
    assert out == ""  # direct Jev scored 0.9: a pass
    headers = seen[0][0]
    assert headers["Authorization"] == "Bearer apikey_x"
    assert "CF-Access-Client-Secret" not in headers


def test_unreachable_jev_degrades_to_local_rules():
    out = run(
        {"file_path": "a.md", "content": BAD},
        STE_JEV_KEY="k",
        STE_JEV_URL="http://127.0.0.1:9/nothing",
        STE_JEV_TIMEOUT="1",
    )
    assert context(out).startswith("ASD-STE100 local check")


def test_short_edit_skips_jev():
    url, seen, server = stub_jev(0.1)
    try:
        out = run(
            {"file_path": "a.md", "content": BAD},
            STE_JEV_KEY="k",
            STE_JEV_URL=url,
            STE_JEV_MIN_WORDS="60",
        )
    finally:
        server.shutdown()
    assert seen == [] and context(out).startswith("ASD-STE100 local check")


def edited(tmp, old, now, tool_input):
    """Write the file as it is after the edit and run the hook on it."""
    path = Path(tmp) / "doc.md"
    path.write_text(now)
    return run({"file_path": str(path), **tool_input}, {"originalFile": old})


GOOD_WITH_DETAILS = "Set `SNAPCTL_BUCKET`. Then run `snapctl restore --clean`."


def test_detail_check_names_removed_details():
    with tempfile.TemporaryDirectory() as d:
        out = edited(
            d,
            GOOD_WITH_DETAILS,
            "Set the bucket. Then run the restore.",
            {"old_string": GOOD_WITH_DETAILS, "new_string": "Set the bucket."},
        )
    msg = context(out)
    assert "removed these technical details" in msg
    assert "`snapctl restore --clean`" in msg and "`SNAPCTL_BUCKET`" in msg


def test_detail_moved_elsewhere_in_file_is_not_reported():
    with tempfile.TemporaryDirectory() as d:
        # Both details move from inline code into a code block.
        now = "Set the bucket.\n\n```\nexport SNAPCTL_BUCKET=b\nsnapctl restore --clean\n```\n"
        out = edited(
            d,
            GOOD_WITH_DETAILS,
            now,
            {"old_string": GOOD_WITH_DETAILS, "new_string": "Set the bucket."},
        )
    assert out == ""


def test_detail_check_on_write_uses_original_file():
    with tempfile.TemporaryDirectory() as d:
        out = edited(
            d,
            "Put the settings in `~/.config/snapctl/config.yaml`. Grant `s3:DeleteObject`.",
            "Put the settings in the config file.",
            {"content": "Put the settings in the config file."},
        )
    msg = context(out)
    assert "`~/.config/snapctl/config.yaml`" in msg and "`s3:DeleteObject`" in msg


def test_detail_check_ignores_code_files():
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "main.py"
        path.write_text("x = 1\n")
        out = run(
            {
                "file_path": str(path),
                "old_string": "y = '--clean'",
                "new_string": "x = 1",
            }
        )
    assert out == ""


SESSION = Path(__file__).parent / "hooks" / "scripts" / "ste-session.py"


def test_session_brief_is_hook_json_and_can_be_disabled():
    out = subprocess.run([sys.executable, str(SESSION)], capture_output=True, text=True)
    hso = json.loads(out.stdout)["hookSpecificOutput"]
    assert hso["hookEventName"] == "SessionStart"
    assert "Keep every technical detail" in hso["additionalContext"]
    env = {**os.environ, "CLAUDE_STE_DISABLE": "1"}
    off = subprocess.run(
        [sys.executable, str(SESSION)], capture_output=True, text=True, env=env
    )
    assert off.stdout == ""


LOOKUP = Path(__file__).parent / "skills" / "asd-ste100" / "scripts" / "ste-lookup.py"
# Three made-up entries in the dictionary's JSONL shape, so no ASD text ships here.
FIXTURE = [
    {
        "name": "utilize",
        "status": "rejected",
        "type_": "v",
        "alternatives": [{"name": "USE", "type_": "v", "ste_example": ["USE IT."]}],
    },
    {"name": "use", "status": "rejected", "type_": "n", "alternatives": []},
    {
        "name": "key",
        "status": "rejected",
        "type_": "adj",
        "alternatives": [{"name": "KEY", "type_": "n"}],
    },
    {
        "name": "USE",
        "status": "approved",
        "type_": "v",
        "meanings": [{"value": "To make something do its function"}],
    },
]


def lookup(*args, stdin=""):
    with tempfile.TemporaryDirectory() as d:
        vocab = Path(d) / "asdste100_issue9_base.jsonl"
        vocab.write_text("\n".join(json.dumps(e) for e in FIXTURE))
        return subprocess.run(
            [sys.executable, str(LOOKUP), *args],
            input=stdin,
            capture_output=True,
            text=True,
            env={**os.environ, "STE_VOCAB_PATH": d},
        )


def test_lookup_finds_base_form_and_alternative():
    out = lookup("utilized").stdout
    assert "base form of 'utilized'" in out and "use instead: USE (v)" in out


def test_lookup_fuzzy_match():
    assert "Similar: utilize" in lookup("utilise").stdout


def test_text_scan_skips_words_approved_in_some_part_of_speech():
    out = lookup("--text", "-", stdin="Utilizing the key, use the tool.").stdout
    assert out.strip() == "Utilizing -> USE"


def test_lookup_without_dictionary_exits_2():
    env = {**os.environ, "STE_VOCAB_PATH": "/nonexistent"}
    proc = subprocess.run(
        [sys.executable, str(LOOKUP), "use"], capture_output=True, text=True, env=env
    )
    assert proc.returncode == 2 and "biz-dfch-asdste100vocab" in proc.stderr


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print(f"ok   {name}")
