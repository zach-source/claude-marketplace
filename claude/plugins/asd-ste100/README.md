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

If the prose has fewer than 60 words, the hook uses only the local rules. A short edit is often a list fragment, and Jev gives fragments low scores that cause extra rewrites.

### Jev routes and the fallback judge

The hook tries these in order, and it uses the first one that gives scores:

1. **Primary Jev route**: `STE_JEV_URL` with `STE_JEV_KEY`, usually a LiteLLM gateway. The `CF-Access-*` headers go only to this route.
2. **TypeSafe direct**: `STE_JEV_DIRECT_URL` (default `https://api.typesafe.ai/v1/systemone`) with `STE_JEV_DIRECT_KEY`. In a test it answered in 0.16–0.22 s.
3. **Claude Haiku 5.5 judge**: only in a Jev outage, which means a Jev key is set but no route answers. It also scores only documents, not code comments.
4. **Local rules.**

Each Jev route has a circuit breaker. After a route fails, the hook skips it for 5 minutes, so a dead route does not add a timeout to each write.

A session with no Jev key gets only the local rules. The judge does not run there, because it is slow: in 14 days of real sessions, 25% of all writes had enough prose to score. The judge for every one of them would add about 40 minutes of waiting each day. The judge runs as an isolated `claude -p`, with no settings, tools, MCP servers or skills, and with `CLAUDE_STE_DISABLE=1`, so it cannot start this hook again. It uses the session's normal Claude login.

The judge is slower and noisier than Jev, so it has its own pass mark:

| Judge | Time | Docs written without the plugin | Docs written with the plugin |
|---|---|---|---|
| Jev | 0.3–0.5 s | 0.29–0.38 | 0.50–0.56 |
| Haiku 5.5 | 7–15 s | 0.74–0.98 (mean 0.88) | 0.96–0.99, plus one 0.53 |

The 0.53 came from a reply with no reasoning, only 67 output tokens. The hook discards a judge reply with fewer than 100 output tokens, a reply that is not a JSON array of numbers from 0 to 1, and a reply with the wrong number of scores. If the judge fails, the hook uses only the local rules. A judge call costs about $0.002.

The hook also does a **detail check** on prose files. It compares the text that the tool replaced with the file after the write. If an env var, a flag, a path, an S3 permission or an inline-code item is no longer anywhere in the file, the hook names it. A detail that moved to another part of the file is not reported. This check does not use the network. These rules find long sentences, long paragraphs, the passive voice and words that STE does not approve.

### Configuration

| Env var | Default | Meaning |
|---------|---------|---------|
| `STE_JEV_KEY` | unset | Bearer key for the primary route |
| `STE_JEV_DIRECT_KEY` | unset | TypeSafe API key for the direct route |
| `STE_JEV_DIRECT_URL` | `https://api.typesafe.ai/v1/systemone` | The direct route |
| `STE_JEV_URL` | `https://api.typesafe.ai/v1/systemone` | For a LiteLLM gateway, use `<gateway>/typesafe/v1/systemone`. |
| `STE_JEV_THRESHOLD` | `0.4` | The pass mark |
| `STE_JEV_TIMEOUT` | `3` | Time limit in seconds |
| `STE_JEV_MIN_WORDS` | `60` | The minimum number of prose words for a Jev or judge score |
| `STE_JUDGE` | unset | `0` turns off the Haiku 5.5 fallback judge. |
| `STE_JUDGE_CLI` | `claude` on `PATH` | The Claude Code binary for the judge |
| `STE_JUDGE_THRESHOLD` | `0.95` | The pass mark for the judge's mean paragraph score |
| `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` | unset | When both are set, the hook sends them as `CF-Access-*` headers, for a gateway behind Cloudflare Access. |
| `CLAUDE_STE_DISABLE` | unset | `1` turns off the hook and the session brief. |

The pass mark of 0.4 comes from a test with 4 documents. The mean paragraph score was 0.31–0.32 for documents that Claude wrote without the plugin, and 0.50–0.54 for documents that it wrote with the plugin. Do not score a full document as one text: Jev gives about 0.2 to a full document, even when most of its paragraphs pass.

## Test

`python3 test-ste-check.py` tests the local rules and the decisions. A stub HTTP server stands in for Jev. The tests check the pass, fail and unreachable cases, and the request headers and body.
