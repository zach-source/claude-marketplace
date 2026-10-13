#!/usr/bin/env python3
"""
Look up words in the ASD-STE100 Issue 9 dictionary.

  ste-lookup.py WORD [WORD ...]   show each word's status, meanings, approved
                                  alternatives and examples
  ste-lookup.py --text FILE|-     list the words in a text that the dictionary
                                  rejects in every part of speech

A word that is not in the dictionary is matched by its base form ("utilized" ->
"utilize"), then by fuzzy spelling (difflib).

The dictionary is NOT shipped with this plugin: ASD holds its copyright. The
script reads the asdste100_issue9_base.jsonl file from the AGPL-3.0 package
biz-dfch-asdste100vocab (https://pypi.org/project/biz-dfch-asdste100vocab/).
It looks for that file, in this order:
  1. $STE_VOCAB_PATH (the .jsonl file, or a directory that contains it)
  2. the installed biz.dfch.asdste100vocab Python package
"""

import difflib
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

DATA_FILE = "asdste100_issue9_base.jsonl"
HELP_MISSING = f"""ste-lookup: the STE dictionary ({DATA_FILE}) is not available.
Install it with one of these, or set STE_VOCAB_PATH to the file:
  pip install biz-dfch-asdste100vocab
  uv pip install biz-dfch-asdste100vocab"""


def vocab_file():
    """Return the dictionary path, or None when it is not available."""
    env = os.environ.get("STE_VOCAB_PATH")
    if env:
        p = Path(env)
        p = p / DATA_FILE if p.is_dir() else p
        return p if p.is_file() else None
    try:
        import biz.dfch.asdste100vocab as pkg  # noqa: PLC0415

        p = Path(pkg.__file__).parent / "data" / DATA_FILE
        return p if p.is_file() else None
    except ImportError:
        return None


def load(path):
    """Return {lowercase name: [entries]}."""
    words = defaultdict(list)
    with open(path) as f:
        for line in f:
            if line.strip():
                entry = json.loads(line)
                words[entry["name"].lower()].append(entry)
    return words


def base_forms(word):
    """Return candidate dictionary forms of an inflected word."""
    w = word.lower()
    forms = [w]
    for suffix, repl in (
        ("ies", "y"),
        ("ied", "y"),
        ("ing", ""),
        ("ing", "e"),
        ("ed", ""),
        ("ed", "e"),
        ("es", ""),
        ("s", ""),
        ("ly", ""),
    ):
        if w.endswith(suffix) and len(w) - len(suffix) >= 2:
            forms.append(w[: -len(suffix)] + repl)
    if re.search(r"(.)\1(ing|ed)$", w):  # stopped -> stop
        forms.append(re.sub(r"(.)\1(ing|ed)$", r"\1", w))
    return forms


def find(words, word):
    """Return (matched name, how) for a word, or (None, close names)."""
    for i, form in enumerate(base_forms(word)):
        if form in words:
            return form, "exact" if i == 0 else f"base form of '{word}'"
    return None, difflib.get_close_matches(word.lower(), words, n=5, cutoff=0.75)


def examples(entry):
    """Return (STE example, non-STE example), either can be ''."""
    ste = entry.get("ste_example") or []
    non = entry.get("nonste_example") or []
    for m in entry.get("meanings") or []:
        ste = ste or m.get("ste_example") or []
        non = non or m.get("nonste_example") or []
    return (ste[0] if ste else ""), (non[0] if non else "")


def describe(entry):
    """Return the lines that describe one dictionary entry."""
    lines = [f"  {entry['name']} ({entry['type_']}) {entry['status'].upper()}"]
    for m in entry.get("meanings") or []:
        if m.get("value"):
            lines.append(f"    meaning: {m['value']}")
    for alt in entry.get("alternatives") or []:
        ste, non = examples(alt)
        lines.append(f"    use instead: {alt['name']} ({alt['type_']})")
        if ste:
            lines.append(f"      STE:     {ste}")
        if non:
            lines.append(f"      not STE: {non}")
    ste, non = examples(entry)
    if ste:
        lines.append(f"    STE:     {ste}")
    if non:
        lines.append(f"    not STE: {non}")
    note = entry.get("note")
    if isinstance(note, dict) and note.get("value"):
        lines.append(f"    note: {note['value']}")
    return lines


def lookup(words, word):
    """Return a report for one word."""
    name, how = find(words, word)
    if name is None:
        if how:
            return f"{word}: not in the dictionary. Similar: {', '.join(how)}"
        return f"{word}: not in the dictionary, and no similar word. A technical name or verb can be acceptable (rules 1.5, 1.12)."
    head = f"{word}:" if how == "exact" else f"{word}: ({how})"
    return "\n".join([head] + [l for e in words[name] for l in describe(e)])


def scan(words, text):
    """Return one line per word in the text that is rejected in every use."""
    out, seen = [], set()
    for token in re.findall(r"[A-Za-z][A-Za-z'-]*", text):
        name, how = find(words, token)
        if name is None or name in seen:
            continue
        entries = words[name]
        seen.add(name)
        if all(e["status"] == "rejected" for e in entries):
            alts = {a["name"] for e in entries for a in e.get("alternatives") or []}
            if {name, token.lower()} & {a.lower() for a in alts}:
                # "key (adj) -> KEY (n)", "warn (v) -> WARNING (TN)": the word
                # is approved in another part of speech or as a technical noun.
                continue
            out.append(f"{token} -> {', '.join(sorted(alts)) or '(rewrite)'}")
    return out


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    path = vocab_file()
    if path is None:
        print(HELP_MISSING, file=sys.stderr)
        return 2
    words = load(path)
    if argv[0] == "--text":
        src = argv[1] if len(argv) > 1 else "-"
        text = sys.stdin.read() if src == "-" else Path(src).read_text()
        found = scan(words, text)
        print("\n".join(found) if found else "No rejected words found.")
        return 0
    print("\n\n".join(lookup(words, w) for w in argv))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
