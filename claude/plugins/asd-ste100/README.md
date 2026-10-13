# asd-ste100

Keeps documentation, Markdown and code comments in ASD-STE100 Simplified Technical English (STE).

## Skill

`skills/asd-ste100/SKILL.md` contains a summary of the STE writing rules, a word-substitution table, a review procedure and examples. Claude loads it when it writes documentation, or when the hook asks for a review.

`skills/asd-ste100/scripts/ste-lookup.py` looks up words in the full Issue 9 dictionary. It finds base forms ("utilized" finds "utilize") and similar spellings (difflib). With `--text`, it lists the rejected words in a draft. It uses the standard library only.

The plugin does not include the dictionary. ASD holds its copyright, and the machine-readable version ([`biz-dfch-asdste100vocab`](https://pypi.org/project/biz-dfch-asdste100vocab/)) is AGPL-3.0. Install that package, or set `STE_VOCAB_PATH` to its `asdste100_issue9_base.jsonl` file (or to the directory that contains it). Without the dictionary, the script exits with code 2 and the skill uses its short table.

## Session brief

A SessionStart hook (`ste-session.py`) puts a short STE brief into the context of each session: at startup, at resume, after `/clear` and after compaction. The brief has the core rules and the rule to keep every technical detail. It applies to chat replies, documents, comments and commit messages. It adds about 230 words of context. Claude does not always load the skill, so this brief makes sure that the rules are always available.

## Rewriter subagent

`agents/ste-rewriter.md` rewrites a document, or named paragraphs in it, into STE. It runs on Claude Haiku 5.5 (`claude-haiku-5-5`). When 3 or more paragraphs fail the Jev check, the hook tells the main session to hand the rewrite to this subagent and then check its edits. When fewer paragraphs fail, the main session fixes them itself, so it does not pay the start-up cost of a subagent.

In a test, Haiku 5.5 rewrote 2 documents twice each. It kept every technical detail, every rewrite passed Jev (0.41–0.47), and each rewrite cost $0.017–0.028. The same rewrites on Opus 5.5 cost $0.39–0.51. Haiku 5.5 took more turns, 42–103 s against 23–50 s.

## Hook

| Event | Script | What it does |
|-------|--------|--------------|
| PostToolUse (`Write\|Edit\|MultiEdit`) | `ste-check.py` | Scores the prose that Claude wrote. When the text fails, it adds context that tells Claude to review the text with the skill. It never blocks a write. |

The hook checks all of the text in prose files (`.md`, `.txt`, `.rst`, `.adoc`, `.org`). In other files, it checks only comment lines. It ignores code fences, inline code, URLs, links and tables.

The check has two passes:

1. **Jev score.** [Jev](https://typesafe.ai/blog/introducing-system-one-models-and-jev) (TypeSafe AI) gives each paragraph a score from 0 to 1. The hook sends up to 16 paragraphs in parallel, and the check takes 0.3–0.5 s. If the mean score is at or above the pass mark, the check stops. If it is below, the hook shows the three paragraphs with the lowest scores.
2. **Full review.** Claude does the full review with the skill loaded. The hook gives Claude the Jev score and the findings of the local rules.

If no Jev key is set, if Jev does not reply, or if the prose has fewer than 60 words, the hook uses only the local rules. A short edit is often a list fragment, and Jev gives fragments low scores that cause extra rewrites.

The hook also does a **detail check** on prose files. It compares the text that the tool replaced with the file after the write. If an env var, a flag, a path, an S3 permission or an inline-code item is no longer anywhere in the file, the hook names it. A detail that moved to another part of the file is not reported. This check does not use the network. These rules find long sentences, long paragraphs, the passive voice and words that STE does not approve.

### Configuration

| Env var | Default | Meaning |
|---------|---------|---------|
| `STE_JEV_KEY` | unset | Bearer key. If it is unset, the hook uses the local rules only. |
| `STE_JEV_URL` | `https://api.typesafe.ai/v1/systemone` | For a LiteLLM gateway, use `<gateway>/typesafe/v1/systemone`. |
| `STE_JEV_THRESHOLD` | `0.4` | The pass mark |
| `STE_JEV_TIMEOUT` | `3` | Time limit in seconds |
| `STE_JEV_MIN_WORDS` | `60` | The minimum number of prose words for a Jev score |
| `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` | unset | When both are set, the hook sends them as `CF-Access-*` headers, for a gateway behind Cloudflare Access. |
| `CLAUDE_STE_DISABLE` | unset | `1` turns off the hook and the session brief. |

The pass mark of 0.4 comes from a test with 4 documents. The mean paragraph score was 0.31–0.32 for documents that Claude wrote without the plugin, and 0.50–0.54 for documents that it wrote with the plugin. Do not score a full document as one text: Jev gives about 0.2 to a full document, even when most of its paragraphs pass.

## Test

`python3 test-ste-check.py` tests the local rules and the decisions. A stub HTTP server stands in for Jev. The tests check the pass, fail and unreachable cases, and the request headers and body.
