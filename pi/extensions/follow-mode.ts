/**
 * NeoVim Follow Mode Extension for Pi
 *
 * Tells NeoVim to open and jump to each file Pi writes or edits, so the editor
 * tracks the agent.
 *
 * Port of the Claude Code `follow-mode-notify.sh` PostToolUse hook. It reuses
 * the script shipped by claude-follow-hook.nvim rather than reimplementing it:
 * the socket path, the line-finding and the nvim remote calls all live there,
 * and that script already accepts `.tool_input.path`, which is exactly Pi's
 * field name. So this feeds it a Claude-shaped payload on stdin on purpose -
 * the script is the contract, not the harness.
 *
 * Config:
 *   PI_FOLLOW_MODE_SCRIPT  override the script path
 *
 * Events:
 *   tool_result - Point NeoVim at the file that just changed
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";

const SCRIPT =
  process.env.PI_FOLLOW_MODE_SCRIPT ??
  join(
    homedir(),
    ".local/share/nvim/lazy/claude-follow-hook.nvim/follow-mode-notify.sh",
  );

/**
 * pi.exec() has no stdin, and the nvim script reads its payload from stdin,
 * so this spawns directly. Fire and forget: the editor jumping is never worth
 * stalling a turn over.
 */
function notifyNvim(payload: unknown, cwd: string): void {
  try {
    const child = spawn(SCRIPT, [], {
      cwd,
      stdio: ["pipe", "ignore", "ignore"],
    });
    child.on("error", () => {}); // Script missing or not executable.
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify(payload));
  } catch {
    // Never let editor integration break a tool result.
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") return;
    if (event.isError) return;

    const path = (event.input as { path?: string }).path;
    if (!path) return;

    // First edit of the batch is the one worth jumping to.
    const edits = (
      event.input as { edits?: Array<{ oldText: string; newText: string }> }
    ).edits?.[0];

    notifyNvim(
      {
        tool_name: event.toolName === "write" ? "Write" : "Edit",
        tool_input: {
          path: isAbsolute(path) ? path : resolve(ctx.cwd, path),
          old_string: edits?.oldText,
          new_string: edits?.newText,
        },
      },
      ctx.cwd,
    );
  });
}
