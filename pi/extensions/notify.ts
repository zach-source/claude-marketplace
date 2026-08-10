/**
 * Desktop Notification Extension for Pi
 *
 * Fires a desktop notification when the agent finishes working, so a long run
 * in a background pane does not need watching.
 *
 * Port of the Claude Code `notify-hook.sh` Stop hook, including the Zellij
 * integration: clicking the notification focuses the pane that raised it.
 *
 * Only the Stop half ports. Claude's Notification event (the agent is blocked
 * waiting for permission or input) has no counterpart in Pi's event set - Pi
 * asks through `ctx.ui`, which is in-band, so there is nothing to notify about.
 *
 * Config:
 *   PI_NOTIFY_ENABLED  "0" to disable
 *
 * Events:
 *   agent_end - Notify that the run finished
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { basename } from "node:path";

async function notify(
  pi: ExtensionAPI,
  title: string,
  body: string,
  group: string,
): Promise<void> {
  const zellijPane = process.env.ZELLIJ
    ? process.env.ZELLIJ_PANE_ID
    : undefined;

  const attempts: Array<[cmd: string, args: string[]]> = [
    [
      "terminal-notifier",
      [
        "-message",
        body,
        "-title",
        title,
        "-group",
        group,
        ...(zellijPane
          ? ["-execute", `zellij action focus-pane --pane-id ${zellijPane}`]
          : []),
      ],
    ],
    [
      "osascript",
      ["-e", `display notification "${body}" with title "${title}"`],
    ],
    ["notify-send", [title, body]],
  ];

  for (const [cmd, args] of attempts) {
    try {
      const result = await pi.exec(cmd, args, { timeout: 5_000 });
      if (result.code === 0) return;
    } catch {
      // Notifier not installed - try the next one.
    }
  }
}

export default function (pi: ExtensionAPI) {
  let enabled = process.env.PI_NOTIFY_ENABLED !== "0";

  pi.on("agent_end", async (_event, ctx) => {
    if (!enabled) return;
    const project = basename(ctx.cwd);
    await notify(pi, `Pi: ${project}`, "Task completed", `${ctx.cwd}:pi`);
  });

  pi.registerCommand("notify", {
    description: "Toggle desktop notifications when the agent finishes",
    handler: async (_args, ctx) => {
      enabled = !enabled;
      ctx.ui.notify(`Notifications: ${enabled ? "on" : "off"}`, "info");
    },
  });
}
