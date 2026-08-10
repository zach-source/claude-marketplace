/**
 * Working Context Extension for Pi
 *
 * Injects the per-project working context (kubernetes context/namespace, AWS
 * profile/region, git, env, custom notes) so Pi does not have to guess which
 * cluster or account it is pointed at.
 *
 * Port of the Claude Code `inject-context.py` UserPromptSubmit hook. It reads
 * the same store, `~/.claude/contexts/<project-id>.json`, on purpose: the
 * context is a fact about the machine, not about the harness, and Claude's
 * `/prompt:context` command is the writer. This extension is read-only.
 *
 * Events:
 *   before_agent_start - Inject the working context when it changes
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

const CONTEXTS_DIR = join(homedir(), ".claude", "contexts");
const MAX_AGE_HOURS = 24;

interface ContextFile {
  updated?: string;
  context?: {
    kubernetes?: { context?: string; namespace?: string };
    aws?: { profile?: string; region?: string };
    git?: { branch?: string; repo?: string };
    env?: Record<string, string>;
    custom?: Record<string, string>;
  };
}

/** Same project id scheme as inject-context.py: <name>-<sha256(path)[:12]>. */
function projectId(root: string): string {
  const path = resolve(root);
  const digest = createHash("sha256").update(path).digest("hex").slice(0, 12);
  return `${basename(path).replace(/ /g, "-").toLowerCase().slice(0, 20)}-${digest}`;
}

function ageLabel(updated: string | undefined): string | undefined {
  if (!updated) return undefined;
  const then = Date.parse(updated.replace("Z", "+00:00"));
  if (Number.isNaN(then)) return undefined;

  const hours = (Date.now() - then) / 3_600_000;
  const stale = hours > MAX_AGE_HOURS ? " (STALE)" : "";
  if (hours < 1) return `${Math.floor(hours * 60)}m ago${stale}`;
  if (hours < 24) return `${Math.floor(hours)}h ago${stale}`;
  return `${Math.floor(hours / 24)}d ago${stale}`;
}

function contextLines(data: ContextFile): string[] {
  const ctx = data.context ?? {};
  const lines: string[] = [];

  const k8s = ctx.kubernetes ?? {};
  if (k8s.context || k8s.namespace) {
    const ns = k8s.namespace ? ` / ${k8s.namespace}` : "";
    lines.push(`Kubernetes: ${k8s.context ?? "default"}${ns}`);
  }

  const aws = ctx.aws ?? {};
  if (aws.profile || aws.region) {
    const region = aws.region ? ` (${aws.region})` : "";
    lines.push(`AWS Profile: ${aws.profile ?? "default"}${region}`);
  }

  const git = ctx.git ?? {};
  if (git.branch || git.repo) {
    lines.push(`Git: ${[git.branch, git.repo].filter(Boolean).join(" @ ")}`);
  }

  const pairs = (values: Record<string, string> | undefined) =>
    Object.entries(values ?? {})
      .map(([k, v]) => `${k}=${v}`)
      .join(", ");

  const env = pairs(ctx.env);
  if (env) lines.push(`Env: ${env}`);

  const custom = pairs(ctx.custom);
  if (custom) lines.push(`Custom: ${custom}`);

  return lines;
}

async function gitRoot(pi: ExtensionAPI, cwd: string): Promise<string> {
  try {
    const result = await pi.exec("git", ["rev-parse", "--show-toplevel"], {
      cwd,
      timeout: 5_000,
    });
    return result.code === 0 && result.stdout.trim()
      ? result.stdout.trim()
      : cwd;
  } catch {
    return cwd;
  }
}

export default function (pi: ExtensionAPI) {
  // Compared against the context payload, not the rendered block: the rendered
  // block carries a relative age that changes every turn on its own.
  let lastPayload: string | undefined;

  pi.on("before_agent_start", async (_event, ctx) => {
    const file = join(
      CONTEXTS_DIR,
      `${projectId(await gitRoot(pi, ctx.cwd))}.json`,
    );

    let data: ContextFile;
    let raw: string;
    try {
      raw = readFileSync(file, "utf8");
      data = JSON.parse(raw) as ContextFile;
    } catch {
      return; // No context set for this project.
    }

    const lines = contextLines(data);
    if (lines.length === 0) return;
    if (raw === lastPayload) return;
    lastPayload = raw;

    const age = ageLabel(data.updated);
    const block = [
      "<working-context>",
      ...lines.map((line) => `  ${line}`),
      ...(age ? [`  Updated: ${age}`] : []),
      "</working-context>",
    ].join("\n");

    return {
      message: {
        customType: "working-context",
        content: block,
        display: false,
      },
    };
  });
}
