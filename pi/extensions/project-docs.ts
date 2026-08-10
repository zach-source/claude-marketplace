/**
 * Project Docs Extension for Pi
 *
 * Injects STATUS.md / TASKS.md / SESSION_HISTORY.md from the project root into
 * the conversation so Pi starts every turn knowing the project state.
 *
 * Port of the Claude Code `inject_project_docs.py` UserPromptSubmit hook. That
 * hook rewrites the user's prompt and re-injects the full documents on every
 * single submission. Pi's `before_agent_start` returns a separate custom
 * message that persists in the session, so this injects only when the content
 * has actually changed.
 *
 * Events:
 *   before_agent_start - Inject changed project docs
 *
 * Commands:
 *   /project-docs  - Force re-injection on the next turn
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync, statSync } from "node:fs";
import { dirname, join, parse } from "node:path";

const CRITICAL_FILES: Array<[file: string, tag: string]> = [
  ["STATUS.md", "project-status"],
  ["TASKS.md", "immediate-tasks"],
  ["SESSION_HISTORY.md", "session-history"],
];

const MARKERS = [
  ".git",
  "flake.nix",
  "package.json",
  "Cargo.toml",
  "go.mod",
  "README.md",
];

const MAX_FILE_CHARS = 50_000;

function findProjectRoot(start: string): string | undefined {
  let current = start;
  const { root } = parse(current);
  while (current !== root) {
    for (const marker of MARKERS) {
      try {
        statSync(join(current, marker));
        return current;
      } catch {
        // Marker absent, keep walking up.
      }
    }
    current = dirname(current);
  }
  return undefined;
}

function readCapped(path: string): string | undefined {
  try {
    const content = readFileSync(path, "utf8");
    return content.length > MAX_FILE_CHARS
      ? `${content.slice(0, MAX_FILE_CHARS)}\n\n[... TRUNCATED ...]`
      : content;
  } catch {
    return undefined;
  }
}

function collectDocs(
  root: string,
): Array<[tag: string, file: string, body: string]> {
  const docs: Array<[string, string, string]> = [];
  for (const [file, tag] of CRITICAL_FILES) {
    const body = readCapped(join(root, file));
    if (body?.trim()) docs.push([tag, file, body]);
  }
  return docs;
}

function render(docs: Array<[string, string, string]>): string {
  const blocks = docs
    .map(([tag, file, body]) => `<${tag} source="${file}">\n${body}\n</${tag}>`)
    .join("\n\n");
  return [
    '<project-context priority="critical">',
    "<instruction>The following project documentation contains critical context. Read and internalize before proceeding.</instruction>",
    "",
    blocks,
    "</project-context>",
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  // Content of the last injection, so unchanged docs are not re-sent every turn.
  let lastInjected: string | undefined;

  pi.on("before_agent_start", async (_event, ctx) => {
    const root = findProjectRoot(ctx.cwd);
    if (!root) return;

    const docs = collectDocs(root);
    if (docs.length === 0) return;

    const block = render(docs);
    if (block === lastInjected) return;
    lastInjected = block;

    return {
      message: {
        customType: "project-docs",
        content: block,
        display: false,
      },
    };
  });

  pi.registerCommand("project-docs", {
    description:
      "Re-inject STATUS.md / TASKS.md / SESSION_HISTORY.md next turn",
    handler: async (_args, ctx) => {
      lastInjected = undefined;
      ctx.ui.notify(
        "Project docs will be re-injected on the next turn",
        "info",
      );
    },
  });
}
