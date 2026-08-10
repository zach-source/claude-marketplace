---
name: granted
description: "AWS role assumption with Granted CLI. Use when running AWS commands, assuming AWS profiles, switching accounts, or authenticating to AWS. Triggers on: assume, granted, AWS profile, AWS role, AWS SSO, switch AWS account, AWS console, AWS authentication, aws cli."
---

# Granted: AWS Profile-Based Access for AI Agents

All AWS profiles use `credential_process = granted credential-process --profile <name>` in `~/.aws/config`. This means **every `aws` CLI command should use `--profile`** to automatically authenticate via Granted without interactive `assume`.

## Primary Pattern: `--profile` Flag

```bash
# ALWAYS use --profile for AWS commands
aws --profile <profile-name> s3 ls
aws --profile <profile-name> sts get-caller-identity
aws --profile <profile-name> ec2 describe-instances --region us-east-2
```

The `credential_process` in each profile automatically calls `granted credential-process` to obtain temporary credentials. No manual `assume` or environment variable setup needed.

## Discover Available Profiles

```bash
# List all configured profiles
grep -E '^\[profile ' ~/.aws/config | sed 's/\[profile //;s/\]//' | sort
```

## Quick Reference

| Task | Command |
|------|---------|
| List profiles | `grep -E '^\[profile ' ~/.aws/config \| sed 's/\[profile //;s/\]//' \| sort` |
| Verify identity | `aws --profile <name> sts get-caller-identity` |
| Run any command | `aws --profile <name> <service> <command>` |
| Open AWS console | `assume -c <profile>` |
| Interactive assume | `assume <profile>` (sets env vars for current shell) |

## Profile Naming Convention

Profiles follow `<account-name>/<role-name>` format:

```
audit/AdministratorAccess
blocks-dev/AdministratorAccess
blocks-staging/AdministratorAccess
management/AdministratorAccess
management/Billing
networking-prod/AdministratorAccess
platform-prod/AdministratorAccess
shared-services/AdministratorAccess
workloads-prod/AdministratorAccess
```

## When to Use What

| Scenario | Approach |
|----------|----------|
| **AI agent running AWS commands** | `aws --profile <name> ...` |
| **Scripts / automation** | `aws --profile <name> ...` |
| **Human interactive session** | `assume <profile>` then `aws ...` |
| **Open AWS console in browser** | `assume -c <profile>` |
| **Multiple accounts in one script** | Use different `--profile` per command |

## Multi-Account Operations

```bash
# No need to switch contexts - just use different profiles per command
aws --profile blocks-dev/AdministratorAccess s3 ls
aws --profile workloads-prod/AdministratorAccess ec2 describe-instances
aws --profile management/Billing ce get-cost-and-usage --time-period Start=2025-01-01,End=2025-02-01 --granularity MONTHLY --metrics BlendedCost
```

## SSO Re-Authentication

If `credential_process` fails with an auth error, the SSO token may have expired:

```bash
# Clear and re-authenticate (requires browser)
granted sso-tokens clear
assume <profile>  # Triggers browser SSO login

# Then resume using --profile
aws --profile <profile> sts get-caller-identity
```

## Verify Access

Always verify before performing operations:

```bash
aws --profile <name> sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AROAXXXXXXXXXX:session-name",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/RoleName/session-name"
}
```

## Configuration

Profiles are managed in `~/dotfiles/nix/home/ztaylor/features/cli/aws.nix` and merged into `~/.aws/config` via `aws-config-merge`. Each profile includes:

```ini
[profile account/Role]
granted_sso_start_url      = https://d-9a67794288.awsapps.com/start
granted_sso_region         = us-east-2
granted_sso_account_id     = 123456789012
granted_sso_role_name      = Role
credential_process         = granted credential-process --profile account/Role
```

The `credential_process` line is what makes `aws --profile` work without manual `assume`.
