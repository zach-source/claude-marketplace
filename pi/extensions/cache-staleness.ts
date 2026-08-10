/**
 * Cache Staleness Extension for Pi
 *
 * When a session has sat idle long enough that the provider's prompt cache has
 * almost certainly lapsed, compact before spending a full-price request on a
 * large context, then resend the prompt.
 *
 * Port of the Claude Code `session-staleness.py` UserPromptSubmit hook. Most of
 * that script exists because a Claude hook cannot trigger compaction: it has to
 * refuse the prompt, and inside herdr it types `/compact` into the pane and
 * replays the prompt by hand. Pi exposes `ctx.compact()` with completion
 * callbacks and `pi.sendUserMessage()`, so the whole workaround collapses into
 * compact-then-resend.
 *
 * OFF BY DEFAULT. The upstream hook's 1h TTL was verified from Claude Code
 * transcripts (`ephemeral_1h_input_tokens`). Pi is multi-provider and this has
 * not been measured against any of them, so opt in once you know the cache TTL
 * of the model you actually run.
 *
 * Config:
 *   PI_STALE_AUTOCOMPACT     "1" to enable; off otherwise
 *   PI_CACHE_TTL_SECONDS     idle seconds before the cache is presumed cold; default 3600
 *   PI_STALE_MIN_TOKENS      skip below this context size; default 200000
 *
 * Events:
 *   turn_end - Track when the session last did work
 *   input    - Compact and resend when the cache has lapsed
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const ENABLED = process.env.PI_STALE_AUTOCOMPACT === "1";
const TTL_MS = Number(process.env.PI_CACHE_TTL_SECONDS ?? 3600) * 1000;
const MIN_TOKENS = Number(process.env.PI_STALE_MIN_TOKENS ?? 200_000);

// Don't compact twice in a row. If the resent prompt is still over MIN_TOKENS
// because compaction did not free enough, the pair would otherwise loop.
const COOLDOWN_MS = 300_000;

export default function (pi: ExtensionAPI) {
  let lastTurnAt = Date.now();
  let lastCompactAt = 0;

  pi.on("turn_end", async () => {
    lastTurnAt = Date.now();
  });

  pi.on("input", async (event, ctx) => {
    if (!ENABLED) return;
    // Our own resend arrives as source "extension"; letting it through here
    // would compact forever.
    if (event.source === "extension") return;
    if (!ctx.isIdle()) return;

    const now = Date.now();
    if (now - lastTurnAt < TTL_MS) return;
    if (now - lastCompactAt < COOLDOWN_MS) return;

    const usage = ctx.getContextUsage();
    if (!usage?.tokens || usage.tokens < MIN_TOKENS) return;

    const idleMinutes = Math.floor((now - lastTurnAt) / 60_000);
    const resend = () => pi.sendUserMessage(event.text);

    try {
      ctx.compact({
        // Resend either way. A failed compaction is a reason to pay full price,
        // not a reason to drop the user's prompt on the floor.
        onComplete: resend,
        onError: resend,
      });
    } catch {
      return; // Compaction was refused - let the prompt through untouched.
    }

    lastCompactAt = now;
    ctx.ui.notify(
      `Idle ${idleMinutes}m with ${usage.tokens} tokens of context: compacting before resend`,
      "info",
    );
    return { action: "handled" as const };
  });
}
