---
name: 1password
description: "1Password CLI (op) usage in this dotfiles setup: desktop-app integration (biometric unlock) locally, optional service-account token (OP_SERVICE_ACCOUNT_TOKEN) for headless/non-interactive use. Key gotcha: op auth-status probes are meaningless under desktop integration (a read may still succeed); status only works with a service-account token. Use when reading secrets with op, writing passwordCommand entries, debugging 'is 1Password signed in?', or when an op read/run fails. Triggers on: op read, op run, op whoami, op signin, 1password, passwordCommand, secret fetch, mcp-secret-cache, biometric unlock, service account."
---

# 1Password CLI (`op`) in this setup

Secrets here are fetched at runtime with the **1Password CLI (`op`)**. Secrets never
land in git or the Nix store; nix `passwordCommand` entries and `mcp-secret-cache.sh`
call `op read` / `op run` when a value is needed. There are **two auth modes**:

- **Desktop-app integration (default, local Mac):** the 1Password app's "Integrate
  with 1Password CLI" setting authorizes each `op` invocation on demand, usually via
  a biometric (Touch ID) prompt. No persistent CLI session.
- **Service-account token (headless / opt-in):** when `OP_SERVICE_ACCOUNT_TOKEN` is
  exported, `op` runs **fully non-interactively** (no app, no biometric), scoped to
  the token's granted vaults. Only this mode has a meaningful, working auth status.

## ⚠️ Do NOT gate on `op` auth status (desktop mode)

**With the desktop-app integration, auth/session status does NOT work and must NOT
be used as an indicator of whether `op` will work — a `read` call may still
succeed even when every status probe says "not signed in."** This includes:

- `op whoami`
- `op account get` / `op account list`
- `op signin` / `op signin --list`
- any other "am I signed in?" pre-flight probe

With desktop-app integration these can report **not signed in**, error, or hang —
even when `op read` / `op run` will succeed moments later (the app authorizes the
*actual* command on demand, not the status probe). Conversely a "signed in" result
doesn't guarantee the next read works. **Auth status ≠ whether op works.**

Do not add a status check as a guard, and don't conclude 1Password is broken because
`op whoami` failed. Test with a real read, not a status command.

> Exception — **service-account mode**: if `OP_SERVICE_ACCOUNT_TOKEN` is set, `op
> whoami` *does* report the service-account identity reliably and reads are
> non-interactive. The "status is meaningless" rule is specific to the desktop
> integration.

## Correct pattern: just do the operation (with a timeout)

Attempt the real read/run and handle *its* failure. Give it a timeout so the
biometric prompt has time to appear but a genuinely-stuck call can't block forever:

```bash
# Read a single field
op read "op://Private/<item>/<field>"

# Run a command with secrets injected as env vars
op run -- some-command --flag "$SOME_SECRET"

# Time-boxed (mirrors mcp-secret-cache.sh — allow ~20s for the biometric prompt),
# non-fatal so a blocked/denied read doesn't wedge the caller:
TOKEN="$(timeout 20 op read "op://Private/<item>/credential" 2>/dev/null || true)"
[ -n "$TOKEN" ] || echo "op read failed — prompt the user to unlock 1Password, then retry"
```

If a read fails, the fix is almost always **unlock the 1Password desktop app**
(bring it to foreground / Touch ID) and retry the real command — not to run a
status check.

## Where this shows up in the repo

- **nix `passwordCommand`** (e.g. git.nix, service configs): `op read op://…` at
  activation/runtime. A blocked read should be non-fatal and never clobber a good
  existing value.
- **`mcp-secret-cache.sh`** (`claude-scripts/`): wraps MCP servers, fetching their
  tokens via `op` with a ~20s timeout to allow the biometric prompt — it does *not*
  pre-check auth status, exactly for the reason above.
- **SSH**: git/GitHub auth goes through the **1Password SSH agent** (biometric,
  desktop-app-backed), a separate mechanism from `op read` — don't conflate the two
  when debugging. It can't be driven by a service-account token. Connection
  multiplexing (`ControlPersist`, ssh.nix) means one unlock covers a burst of git
  ops. Headless agents use a dedicated key loaded into ssh-agent memory via a
  service-account `op read`, or git over HTTPS + the `gh` token — never a key on disk.
