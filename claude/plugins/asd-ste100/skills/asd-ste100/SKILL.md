---
name: asd-ste100
description: Write and review text in ASD-STE100 Simplified Technical English (STE). Use when you write or edit documentation, READMEs, Markdown, runbooks, procedures, code comments, docstrings, commit messages or PR descriptions, and when the asd-ste100 hook reports a failed score. Triggers on "STE", "ASD-STE100", "Simplified Technical English", "simplify this doc", "plain technical English", or an "ASD-STE100" hook message.
---

# ASD-STE100 Simplified Technical English

STE is a controlled language for technical text. It uses a small set of words, each with one meaning, and short sentences with simple grammar. Readers whose first language is not English can understand it. Translators can translate it quickly.

This skill is a summary of the ASD-STE100 writing rules (Issue 9). It is not the official dictionary. ASD supplies the specification and dictionary free of charge on request at asd-ste100.org.

## Scope

Apply STE to text that people read:

- Documentation, READMEs, runbooks and Markdown
- Code comments and docstrings
- Commit messages, PR descriptions and changelogs

Do not change these items:

- Code, identifiers, command names, flags, file paths and URLs
- Quoted text, error messages and log output
- Proper names and product names

A technical name (for example `kubectl`, "flake input" or "PostToolUse") is a permitted "technical name". Use it as it is.

### Keep every technical detail

STE makes the text simpler. It must not make the text contain less information. When you write or rewrite a document, keep each of these items:

- Environment variables, flags, config keys and their default values
- File paths, URLs, ports and permissions (for example `s3:DeleteObject`)
- Commands, versions, limits and units

If a sentence becomes too long, do not delete a detail. Divide the sentence, or move the details into a list, a table or a code block. A table of variables or flags is better than a long sentence. When you write a new document, give the same details that a document without STE would give.

The asd-ste100 hook compares the details before and after each edit. If it reports a removed detail, put the detail back unless you removed it on purpose.

## The rules

### Words

1. Use approved words only, and use each word with its approved meaning and part of speech. For example, "close" is a verb ("close the valve"). Do not use "close" as an adverb ("close to the edge"). Use "near".
2. Use one word for one meaning. When you select a word for a concept, use the same word every time. Do not use synonyms for variety.
3. Do not use a technical verb when an approved verb is available. Write "use", not "utilize". Write "start", not "initiate".
4. Use an article ("the", "a", "an") or a demonstrative ("this", "these") before a noun when possible.
5. Do not make noun clusters of more than three words. Write "the pressure of the hydraulic pump", not "hydraulic pump pressure reading value".
6. Do not use contractions. Write "do not", not "don't".

### Verbs

7. Use only these verb forms:
   - The infinitive ("to start")
   - The imperative ("Start the pump.")
   - The simple present ("The pump starts.")
   - The simple past ("The pump started.")
   - The past participle as an adjective ("the connected cable")
   - The future with "will" ("The pump will start.")
8. Do not use "-ing" forms as verbs or nouns. Write "Before you start the pump", not "Before starting the pump".
9. Use the active voice. Write "The daemon reads the file", not "The file is read". In descriptive text, use the passive only when you do not know who does the action.
10. Use "must" for a requirement. Use "can" for ability or permission. Do not use "should", "could", "might", "may" or "shall".

### Sentences

11. Write a maximum of 20 words in a procedural sentence. Write a maximum of 25 words in a descriptive sentence.
12. Write one instruction in each sentence. You can write two actions in one sentence only when you do them at the same time ("Hold the key and turn the dial").
13. Put a condition before the instruction: "If the build fails, run `make rollback`."
14. Write a maximum of 6 sentences in a paragraph. Give each paragraph one topic.
15. Start a procedure step with a verb in the imperative. Number the steps.

### Safety and notes

16. Start a warning or a caution with a short, clear command ("Do not ..."). Then give the risk. Put it before the step that it applies to.
17. Use a note only for information that is not an instruction.

## Word substitutions

Use the word on the right. "(delete)" means delete the word. It adds no meaning.

| Do not use | Use |
|---|---|
| utilize, leverage | use |
| facilitate, assist | help |
| commence, initiate | start |
| terminate | stop |
| approximately | about |
| prior to | before |
| subsequent to | after |
| in order to | to |
| ensure | make sure |
| perform | do |
| obtain | get |
| require | need |
| sufficient | enough |
| numerous | many |
| additional | more |
| demonstrate, indicate | show |
| via | through, with |
| e.g. | for example |
| i.e. | that is |
| etc. | (list all items) |
| should | must (or state the condition) |
| could, might, may | can |
| basically, simply, just, actually | (delete) |
| in the event that | if |
| due to the fact that | because |
| at this point in time | now |

## Dictionary lookup

The table above is a short list. For the full ASD-STE100 Issue 9 dictionary (about 2,000 words), use `scripts/ste-lookup.py` in this skill's directory:

```bash
python3 <skill-dir>/scripts/ste-lookup.py utilize close    # status, meanings, alternatives, examples
python3 <skill-dir>/scripts/ste-lookup.py --text draft.md  # rejected words in a file (or - for stdin)
```

- The lookup finds inflected forms ("utilized" finds "utilize"). It also gives similar spellings for words that are not in the dictionary.
- One word can be approved in one part of speech and rejected in another. For example, "use" is approved as a verb and rejected as a noun. Read the part of speech before you change a word.
- `--text` shows only the words that the dictionary rejects in all parts of speech.
- A word that is not in the dictionary can be a technical name or a technical verb (rules 1.5 and 1.12). For example, `kubectl` and "deploy" are technical words in software documents. You can keep them.
- The dictionary rejects some common software verbs, for example "run" and "build". If a verb is the usual technical verb for the action in your field, you can keep it (rule 1.12). If not, use the alternative that the lookup gives.

The plugin does not include the dictionary, because ASD holds its copyright. The script reads it from the `biz-dfch-asdste100vocab` package or from `$STE_VOCAB_PATH`. If the script exits with code 2, the dictionary is not installed. Continue with the table above.

## Review procedure

Use this procedure when the hook reports a failed score, or when a person asks for an STE review.

1. Read the text that you wrote. Ignore code, identifiers and quoted text.
2. Divide each long sentence. Keep each sentence in the limits of rule 11. Keep all the technical details (see "Keep every technical detail"). Move them into a list, a table or a code block if necessary.
3. Change each passive sentence to the active voice. Name the item or person that does the action.
4. Change each word in the substitution table. Delete filler words. If you are not sure about a word, look it up (see "Dictionary lookup").
5. Change "-ing" forms to a clause or an imperative.
6. Give each instruction its own sentence or numbered step. Put conditions first.
7. Read the text again. Make sure that the meaning did not change, and that each variable, flag, path and value is still in the document.
8. Edit the file with the new text. Do not report each change unless a person asks for a report.

## Examples

Before:
> The configuration file is loaded by the daemon when it is started, and it should be validated prior to utilizing any of the workers.

After:
> The daemon reads the configuration file when it starts. It must check the file before it uses the workers.

Before:
> In order to apply changes, simply run `make apply`, which will build and activate the new generation, ensuring that the rollback is available.

After:
> To apply the changes, run `make apply`. This command builds and activates the new generation. You can roll back to the previous generation.

Before (code comment):
> `# Basically we're leveraging the cache here to facilitate faster lookups`

After:
> `# Use the cache to make lookups faster.`
