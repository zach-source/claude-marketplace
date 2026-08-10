/**
 * Smart Lint Extension for Pi
 *
 * Runs the project formatter/linter on every file Pi writes or edits and
 * splices the result into the tool result the model reads.
 *
 * Port of the Claude Code `smart-lint.sh` PostToolUse hook. That hook can only
 * write to stderr and exit 2; Pi's `tool_result` handler can rewrite the tool
 * result itself, so the failure lands in context instead of hoping the harness
 * surfaces it.
 *
 * Events:
 *   tool_result   - Lint the file after write/edit
 *   session_start - Status bar indicator
 *
 * Commands:
 *   /smart-lint  - Toggle linting on/off
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isAbsolute, resolve } from "node:path";

interface Linter {
  cmd: string;
  args: string[];
  /** Tool reports offenders on stdout and still exits 0 (gofmt -l). */
  listsOffenders?: boolean;
}

// Resolved from PATH, not pinned to store paths: an extension has to survive
// on whatever machine Pi is running on. Missing tools are skipped silently.
const LINTERS: Record<string, Linter[]> = {
  go: [{ cmd: "gofmt", args: ["-l"], listsOffenders: true }],
  py: [
    { cmd: "black", args: ["--check", "--quiet"] },
    { cmd: "flake8", args: [] },
  ],
  js: [{ cmd: "prettier", args: ["--check"] }],
  jsx: [{ cmd: "prettier", args: ["--check"] }],
  ts: [{ cmd: "prettier", args: ["--check"] }],
  tsx: [{ cmd: "prettier", args: ["--check"] }],
  rs: [{ cmd: "rustfmt", args: ["--check"] }],
  nix: [{ cmd: "nixfmt", args: ["--check"] }],
};

async function runLinters(
  pi: ExtensionAPI,
  file: string,
  cwd: string,
): Promise<string[]> {
  const extension = file.split(".").pop() ?? "";
  const linters = LINTERS[extension];
  if (!linters) return [];

  const failures: string[] = [];
  for (const { cmd, args, listsOffenders } of linters) {
    try {
      const result = await pi.exec(cmd, [...args, file], {
        cwd,
        timeout: 10_000,
      });
      const failed = listsOffenders
        ? !!result.stdout?.trim()
        : result.code !== 0;
      if (failed) {
        const detail = (result.stdout || result.stderr || "").trim();
        failures.push(`${cmd}: ${detail || "reported issues"}`);
      }
    } catch {
      // Linter not installed on this machine - not a code problem.
    }
  }
  return failures;
}

export default function (pi: ExtensionAPI) {
  let enabled = true;

  pi.on("tool_result", async (event, ctx) => {
    if (!enabled) return;
    if (event.toolName !== "write" && event.toolName !== "edit") return;
    if (event.isError) return; // The write itself failed; nothing to lint.

    // Pi's write/edit tools take `path`, not Claude's `file_path`.
    const path = (event.input as { path?: string }).path;
    if (!path) return;
    const file = isAbsolute(path) ? path : resolve(ctx.cwd, path);

    const failures = await runLinters(pi, file, ctx.cwd);
    if (failures.length === 0) return;

    const report = [
      `Code quality check failed for ${file}:`,
      ...failures.map((f) => `  - ${f}`),
    ].join("\n");

    ctx.ui.notify(`Lint issues in ${file}`, "warning");

    // Append rather than replace, and leave isError alone: the write itself
    // succeeded, so flagging the tool call as failed would be a lie.
    return {
      content: [...event.content, { type: "text" as const, text: report }],
    };
  });

  pi.registerCommand("smart-lint", {
    description: "Toggle formatter/linter checks after write and edit",
    handler: async (_args, ctx) => {
      enabled = !enabled;
      ctx.ui.notify(`Smart lint: ${enabled ? "enabled" : "disabled"}`, "info");
      ctx.ui.setStatus("smart-lint", enabled ? "" : "lint: off");
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("smart-lint", enabled ? "" : "lint: off");
  });
}
