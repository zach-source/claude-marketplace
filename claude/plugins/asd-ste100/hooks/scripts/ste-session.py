#!/usr/bin/env python3
"""
SessionStart hook: put a short ASD-STE100 brief in the session context.

The asd-ste100 skill loads only when Claude decides to load it, and in tests it
did not load for 2 of 6 new documents. This brief makes the core rules, and the
rule to keep every technical detail, part of every session. It runs on startup,
resume, /clear and compaction. The full rules stay in the skill.

Set CLAUDE_STE_DISABLE=1 to turn it off (it also turns off ste-check.py).
"""

import json
import os

BRIEF = """\
Writing style: ASD-STE100 Simplified Technical English (STE).

Use STE for all text that people read: chat replies, documentation, Markdown, \
code comments, docstrings, commit messages and PR descriptions.

- Write short sentences: 20 words or fewer for instructions, 25 or fewer for \
descriptions.
- Use the active voice. Say who or what does the action.
- Write one instruction in each sentence. Put a condition before the \
instruction ("If the build fails, run `make rollback`.").
- Use simple, approved words: "use", not "utilize" or "leverage"; "start", not \
"initiate"; "make sure", not "ensure"; "about", not "approximately".
- Use "must" for a requirement and "can" for ability. Do not use "should", \
"could" or "might".
- Do not use "-ing" forms as verbs or nouns. Do not use contractions or filler \
words such as "just", "simply" or "basically".
- Start a warning with a command ("Do not ..."), then give the risk.

Keep every technical detail. STE makes the text simpler. It must not make the \
text contain less information. Keep env vars, flags, config keys, default \
values, paths, URLs, ports, permissions, commands, versions and units. If a \
sentence becomes too long, divide it, or move the details into a list, a table \
or a code block. Do not delete them.

Do not change code, identifiers, command names, quoted text or error messages. \
For the full rules and the dictionary lookup, load the asd-ste100 skill.\
"""


def main():
    if os.environ.get("CLAUDE_STE_DISABLE") == "1":
        return
    out = {"hookEventName": "SessionStart", "additionalContext": BRIEF}
    print(json.dumps({"hookSpecificOutput": out}))


if __name__ == "__main__":
    main()
