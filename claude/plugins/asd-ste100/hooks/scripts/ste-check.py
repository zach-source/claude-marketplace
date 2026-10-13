#!/usr/bin/env python3
"""
Keep written prose in ASD-STE100 Simplified Technical English.

PostToolUse hook for Write|Edit|MultiEdit. It checks the text Claude just
wrote: all of it in prose files (.md, .txt, ...), only comment lines in code.
It never blocks a write. When the text fails, it returns additionalContext that
tells Claude to do a full review with the asd-ste100 skill.

Two passes:
  1. Jev (TypeSafe AI System One model) scores each paragraph 0..1 for STE
     compliance, in parallel, in ~0.3-0.5s. When the mean is at or above the
     pass mark, the check ends. Per paragraph, not per file: Jev's score for a
     whole document is ~0.2 even when most of its paragraphs pass.
  2. The full review is Claude itself, with the skill loaded. The hook only
     asks for it, and hands over what the local rules found. When 3 or more
     paragraphs fail, the hook names the plugin's ste-rewriter subagent, which
     runs on Claude Haiku 5.5 at about 1/20 of the cost of an Opus rewrite.

Without a Jev key, or when the prose is shorter than STE_JEV_MIN_WORDS, the hook
runs the local rules only and reports what they find. A short edit is often a
list fragment, and Jev gives fragments low scores that cause extra rewrites.

Detail check (prose files only, no network): the hook compares the technical
details in the text that the tool replaced (old_string, or the original file for
Write) with the file on disk after the write. It names each env var, flag, path,
S3 permission or inline-code item that is no longer anywhere in the file. A
detail that moved to another part of the file is not reported.

Local rules (a heuristic subset of STE, not the full standard):
  - sentence longer than 20 words (STE limit for procedures; 25 for prose)
  - paragraph longer than 6 sentences
  - passive voice (be-verb + past participle)
  - words STE does not approve, with the approved word to use instead

Environment:
  STE_JEV_KEY            bearer key; unset = local rules only
  STE_JEV_URL            default https://api.typesafe.ai/v1/systemone
                         (a LiteLLM gateway serves it at <gateway>/typesafe/v1/systemone)
  STE_JEV_THRESHOLD      pass mark, default 0.4
  STE_JEV_TIMEOUT        seconds, default 3
  STE_JEV_MIN_WORDS      minimum prose words for a Jev score, default 60
  CF_ACCESS_CLIENT_ID    sent as CF-Access-* headers when both are set, for a
  CF_ACCESS_CLIENT_SECRET   gateway behind Cloudflare Access
  CLAUDE_STE_DISABLE=1   turn the hook off
"""

import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PROSE_EXT = {".md", ".markdown", ".mdx", ".txt", ".rst", ".adoc", ".org"}
COMMENT = re.compile(r"^\s*(?:#|//|--|;+|/?\*+|\"\"\"|''')\s?(.*)$")
MAX_WORDS = 20
MAX_SENTENCES = 6
MAX_FINDINGS = 8
MIN_JEV_WORDS = 6  # a paragraph shorter than this is not worth a network call
MAX_JEV_PARAGRAPHS = 16
DETAIL = re.compile(
    r"`([^`\n]+)`"  # inline code
    r"|\b([A-Z][A-Z0-9]*_[A-Z0-9_]+)\b"  # env var
    r"|(?<![\w-])(--[a-z][a-z0-9-]*)"  # flag
    r"|(~/[\w./-]+)"  # home path
    r"|\b(s3:[A-Za-z*]+)"  # S3 permission
)
MAX_DETAILS = 12
# ponytail: fixed hand-off size; make it an env var if 3 proves wrong in use.
HANDOFF_PARAGRAPHS = 3  # this many failing paragraphs -> hand off to ste-rewriter
REWRITER = "asd-ste100:ste-rewriter"
JEV_URL = "https://api.typesafe.ai/v1/systemone"
JEV_QUESTION = (
    "Score how well the text complies with ASD-STE100 Simplified Technical "
    "English: short sentences (max 20 words procedural, 25 descriptive), active "
    "voice, approved simple words, one instruction per sentence, no -ing verb "
    "forms. Ignore code identifiers and command names. 1 = fully compliant, "
    "0 = not compliant."
)

# ponytail: hand-picked list, not the STE dictionary (~900 approved words).
# Add entries as you see repeat offenders. Keep in step with the skill's table.
UNAPPROVED = {
    "utilize": "use",
    "utilise": "use",
    "leverage": "use",
    "facilitate": "help",
    "commence": "start",
    "initiate": "start",
    "terminate": "stop",
    "approximately": "about",
    "prior to": "before",
    "subsequent to": "after",
    "in order to": "to",
    "ensure": "make sure",
    "perform": "do",
    "obtain": "get",
    "require": "need",
    "sufficient": "enough",
    "numerous": "many",
    "additional": "more",
    "assist": "help",
    "demonstrate": "show",
    "indicate": "show",
    "via": "through",
    "e.g.": "for example",
    "i.e.": "that is",
    "etc.": "(list all items)",
    "should": "must (or state the condition)",
    "could": "can",
    "might": "can",
    "basically": "(delete)",
    "simply": "(delete)",
    "just": "(delete)",
    "actually": "(delete)",
}
WORD_RE = {
    w: re.compile(r"(?<![\w.])" + re.escape(w) + r"(?![\w])", re.I) for w in UNAPPROVED
}
PASSIVE = re.compile(
    r"\b(?:is|are|was|were|be|been|being)\s+(?:\w+ly\s+)?(\w+(?:ed|en))\b", re.I
)


def written_text(tool_input):
    """Return the new text an edit tool wrote."""
    if "content" in tool_input:
        return tool_input["content"]
    if "new_string" in tool_input:
        return tool_input["new_string"]
    return "\n".join(e.get("new_string", "") for e in tool_input.get("edits", []))


def prose_of(path, text):
    """Keep only the human-language part of the text."""
    if os.path.splitext(path)[1].lower() in PROSE_EXT:
        text = re.sub(r"```.*?(```|$)", "", text, flags=re.S)  # code fences
        lines = [l for l in text.splitlines() if not l.lstrip().startswith("|")]
        text = "\n".join(lines)
    else:
        lines = (COMMENT.match(l) for l in text.splitlines())
        text = "\n".join(m.group(1) for m in lines if m)
    text = re.sub(r"`[^`]*`|https?://\S+|\[[^\]]*\]\([^)]*\)", " x ", text)
    return text


def check(prose):
    """Return a list of local-rule findings for the prose."""
    found = []
    for para in re.split(r"\n\s*\n", prose):
        # Headings and list items end a sentence even without a period.
        flat = re.sub(r"\n\s*(?:[#>*+-]+|\d+\.)\s+", ". ", "\n" + para)
        sentences = [
            s.strip() for s in re.split(r"(?<=[.!?])\s+|\n", flat) if s.strip()
        ]
        sentences = [s for s in sentences if re.search(r"[A-Za-z]{2}", s)]
        if len(sentences) > MAX_SENTENCES:
            found.append(
                f"paragraph has {len(sentences)} sentences (max {MAX_SENTENCES}): "
                f'"{sentences[0][:50]}..."'
            )
        for s in sentences:
            n = len(re.findall(r"[\w'-]+", s))
            if n > MAX_WORDS:
                found.append(f'{n}-word sentence (max {MAX_WORDS}): "{s[:70]}..."')
            m = PASSIVE.search(s)
            if m:
                found.append(f'passive voice "{m.group(0)}": name who does the action')
    for w, rx in WORD_RE.items():
        if rx.search(prose):
            found.append(f'"{w}" -> {UNAPPROVED[w]}')
    return found


def jev_score(prose):
    """Return Jev's 0..1 STE score, or None when Jev is off or unreachable."""
    key = os.environ.get("STE_JEV_KEY")
    if not key:
        return None
    headers = {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        # Cloudflare answers 403 "error code: 1010" to the default Python-urllib
        # User-Agent, so a gateway behind it never sees the request.
        "User-Agent": "asd-ste100-hook/1",
    }
    cf_id = os.environ.get("CF_ACCESS_CLIENT_ID")
    cf_secret = os.environ.get("CF_ACCESS_CLIENT_SECRET")
    if cf_id and cf_secret:
        headers["CF-Access-Client-Id"] = cf_id
        headers["CF-Access-Client-Secret"] = cf_secret
    body = {
        "model": "jev-latest",
        "state": {"text": prose[:6000]},
        "questions": {"ste": {"type": "noul", "instructions": JEV_QUESTION}},
    }
    req = urllib.request.Request(
        os.environ.get("STE_JEV_URL", JEV_URL),
        data=json.dumps(body).encode(),
        headers=headers,
    )
    timeout = float(os.environ.get("STE_JEV_TIMEOUT", "3"))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return float(json.load(resp)["answers"]["ste"]["noul"])
    except Exception as e:  # ponytail: any Jev failure degrades to the local rules
        print(f"ste-check: Jev call failed, local rules only: {e}", file=sys.stderr)
        return None


def jev_paragraphs(prose):
    """Return [(score, paragraph)] for the prose, or None when Jev gives nothing."""
    lines = (l for l in prose.splitlines() if not l.lstrip().startswith("#"))
    paras = [p.strip() for p in re.split(r"\n\s*\n", "\n".join(lines))]
    paras = [p for p in paras if len(p.split()) >= MIN_JEV_WORDS]
    paras = paras[:MAX_JEV_PARAGRAPHS]
    min_words = int(os.environ.get("STE_JEV_MIN_WORDS", "60"))
    if sum(len(p.split()) for p in paras) < min_words:
        return None
    if not os.environ.get("STE_JEV_KEY"):
        return None
    with ThreadPoolExecutor(max_workers=8) as pool:
        scores = list(pool.map(jev_score, paras))
    scored = [(s, p) for s, p in zip(scores, paras) if s is not None]
    return scored or None


def details(text):
    """Return the set of technical details in the text."""
    return {next(g for g in m.groups() if g) for m in DETAIL.finditer(text or "")}


def removed_details(path, tool_input, tool_response):
    """Return the details that the write removed from the file, sorted."""
    if os.path.splitext(path)[1].lower() not in PROSE_EXT:
        return []  # in code, removing a flag or a variable is a normal change
    if "old_string" in tool_input:
        old = tool_input["old_string"]
    elif "edits" in tool_input:
        old = "\n".join(e.get("old_string", "") for e in tool_input["edits"])
    else:
        old = tool_response.get("originalFile") or ""
    try:
        with open(path) as f:
            now = f.read()
    except OSError:
        now = written_text(tool_input)
    # A substring test, not a set difference: a detail that moved from inline
    # code into a code block or a table is still in the file.
    return sorted(d for d in details(old) if d not in now)


def removed_message(name, lost):
    """Tell Claude which details it removed."""
    shown = ", ".join(f"`{d}`" for d in lost[:MAX_DETAILS])
    if len(lost) > MAX_DETAILS:
        shown += f" and {len(lost) - MAX_DETAILS} more"
    return (
        f"Detail check on {name}: the edit removed these technical details, and "
        f"they are not anywhere else in the file: {shown}. If you did not intend "
        f"to remove them, put them back. If a sentence becomes too long, move the "
        f"details into a list, a table or a code block."
    )


def report(path, scored, threshold, found):
    """Decide what to tell Claude. Return None when the text passes."""
    name = os.path.basename(path)
    score = sum(s for s, _ in scored) / len(scored) if scored else None
    if score is not None and score >= threshold:
        return None
    if score is None and not found:
        return None
    lines = "\n".join(f"- {f}" for f in found[:MAX_FINDINGS])
    if len(found) > MAX_FINDINGS:
        lines += f"\n- ...and {len(found) - MAX_FINDINGS} more"
    if score is None:
        head = f"ASD-STE100 local check on {name} found:"
    else:
        failing = sorted((s, p) for s, p in scored if s < threshold)
        head = (
            f"ASD-STE100: Jev scored the text you wrote in {name} {score:.2f}, "
            f"the mean of {len(scored)} paragraph(s) (pass mark {threshold:.2f})."
        )
        if len(failing) >= HANDOFF_PARAGRAPHS:
            # A large rewrite is cheaper on Haiku 5.5 than in the main session.
            head += (
                f" {len(failing)} paragraphs are under the pass mark. Hand the "
                f'rewrite to a subagent: use the Agent tool with subagent_type "{REWRITER}" '
                f"(it runs on Claude Haiku 5.5). Give it the path {path} and the "
                f"paragraphs below. When it finishes, check its edits. Under the "
                f"pass mark:"
            )
            shown = failing[:MAX_FINDINGS]
        else:
            head += (
                " Load the asd-ste100 skill and rewrite the lowest paragraphs below "
                "against its rules. Keep the meaning, code and identifiers unchanged. "
                "Lowest:"
            )
            shown = sorted(scored)[:3]
        for s, p in shown:
            head += f'\n- {s:.2f} "{" ".join(p.split())[:80]}..."'
        if found:
            head += "\nLocal checks also found:"
    return f"{head}\n{lines}".rstrip()


def main():
    if os.environ.get("CLAUDE_STE_DISABLE") == "1":
        return
    event = json.load(sys.stdin)
    tool_input = event.get("tool_input", {})
    path = tool_input.get("file_path", "")
    name = os.path.basename(path)
    msgs = []
    prose = prose_of(path, written_text(tool_input))
    if prose.strip():
        threshold = float(os.environ.get("STE_JEV_THRESHOLD", "0.4"))
        msgs.append(report(path, jev_paragraphs(prose), threshold, check(prose)))
    lost = removed_details(path, tool_input, event.get("tool_response") or {})
    if lost:
        msgs.append(removed_message(name, lost))
    msg = "\n\n".join(m for m in msgs if m)
    if msg:
        out = {"hookEventName": "PostToolUse", "additionalContext": msg}
        print(json.dumps({"hookSpecificOutput": out}))


if __name__ == "__main__":
    main()
