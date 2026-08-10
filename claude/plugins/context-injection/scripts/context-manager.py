#!/usr/bin/env python3
"""
Context manager for Claude working context (per-project).

Context is stored per-project based on git root or CWD.
Each project has its own isolated context.

Commands:
    view                          - View current context
    set k8s <context> [namespace] - Set Kubernetes context
    set aws <profile> [region]    - Set AWS profile
    set env KEY=VALUE...          - Set environment variables
    set custom KEY=VALUE...       - Set custom values
    set git [branch] [repo]       - Set git context (auto-detects)
    clear <section>               - Clear a section (k8s|aws|env|git|custom|all)
    list                          - List all project contexts
"""

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

CONTEXTS_DIR = Path.home() / ".claude" / "contexts"


def get_project_root() -> Path:
    """Get the project root (git root or CWD)."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            return Path(result.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def get_project_id(project_root: Path) -> str:
    """Generate a unique ID for the project based on its path."""
    # Use a short hash of the absolute path
    path_str = str(project_root.resolve())
    hash_digest = hashlib.sha256(path_str.encode()).hexdigest()[:12]
    # Also include a readable project name
    project_name = project_root.name.replace(" ", "-").lower()[:20]
    return f"{project_name}-{hash_digest}"


def get_context_file() -> Tuple[Path, str, Path]:
    """Get the context file path for the current project.

    Returns: (context_file_path, project_id, project_root)
    """
    project_root = get_project_root()
    project_id = get_project_id(project_root)
    context_file = CONTEXTS_DIR / f"{project_id}.json"
    return context_file, project_id, project_root


def load_context() -> Dict[str, Any]:
    """Load existing context or return empty structure."""
    context_file, project_id, project_root = get_context_file()
    if context_file.exists():
        try:
            with open(context_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                # Ensure project metadata is present
                data["project_id"] = project_id
                data["project_root"] = str(project_root)
                return data
        except (json.JSONDecodeError, IOError):
            pass
    return {
        "version": 2,
        "project_id": project_id,
        "project_root": str(project_root),
        "updated": "",
        "context": {},
    }


def save_context(data: Dict[str, Any]) -> None:
    """Save context with updated timestamp."""
    context_file, project_id, project_root = get_context_file()
    data["updated"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    data["project_id"] = project_id
    data["project_root"] = str(project_root)
    CONTEXTS_DIR.mkdir(parents=True, exist_ok=True)
    with open(context_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    print(f"✓ Context saved for project: {project_root.name}")
    print(f"  File: {context_file}")


def run_cmd(cmd: str) -> Optional[str]:
    """Run a shell command and return output."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def format_context(data: Dict[str, Any]) -> str:
    """Format context for display."""
    ctx = data.get("context", {})
    lines = []

    # Show project info
    project_root = data.get("project_root", "unknown")
    lines.append(f"  Project: {project_root}")
    lines.append("")

    if not ctx:
        lines.append("  No context configured for this project.")
        return "\n".join(lines)

    k8s = ctx.get("kubernetes", {})
    if k8s:
        k8s_str = k8s.get("context", "default")
        if k8s.get("namespace"):
            k8s_str += f" / {k8s['namespace']}"
        if k8s.get("kubeconfig"):
            k8s_str += f" (kubeconfig: {k8s['kubeconfig']})"
        lines.append(f"  Kubernetes: {k8s_str}")

    aws = ctx.get("aws", {})
    if aws:
        aws_str = aws.get("profile", "default")
        if aws.get("region"):
            aws_str += f" ({aws['region']})"
        lines.append(f"  AWS: {aws_str}")

    git = ctx.get("git", {})
    if git:
        git_str = git.get("branch", "")
        if git.get("repo"):
            git_str = f"{git_str} @ {git['repo']}" if git_str else git["repo"]
        if git_str:
            lines.append(f"  Git: {git_str}")

    env = ctx.get("env", {})
    if env:
        env_str = ", ".join(f"{k}={v}" for k, v in env.items())
        lines.append(f"  Env: {env_str}")

    custom = ctx.get("custom", {})
    if custom:
        for k, v in custom.items():
            lines.append(f"  {k}: {v}")

    updated = data.get("updated", "")
    if updated:
        lines.append(f"\n  Updated: {updated}")

    return "\n".join(lines) if lines else "No context configured."


def cmd_view() -> int:
    """View current context."""
    data = load_context()
    print("## Working Context (Project-Specific)\n")
    print(format_context(data))
    return 0


def cmd_list() -> int:
    """List all project contexts."""
    print("## All Project Contexts\n")

    if not CONTEXTS_DIR.exists():
        print("  No contexts found.")
        return 0

    context_files = list(CONTEXTS_DIR.glob("*.json"))
    if not context_files:
        print("  No contexts found.")
        return 0

    for cf in sorted(context_files):
        try:
            with open(cf, "r", encoding="utf-8") as f:
                data = json.load(f)
            project_root = data.get("project_root", "unknown")
            updated = data.get("updated", "never")
            ctx = data.get("context", {})
            ctx_summary = []
            if ctx.get("kubernetes"):
                ctx_summary.append("k8s")
            if ctx.get("aws"):
                ctx_summary.append("aws")
            if ctx.get("custom"):
                ctx_summary.append(f"{len(ctx['custom'])} custom")
            summary = ", ".join(ctx_summary) if ctx_summary else "empty"
            print(f"  {project_root}")
            print(f"    [{summary}] Updated: {updated}")
            print()
        except Exception as e:
            print(f"  {cf.name}: Error reading ({e})")

    return 0


def cmd_set_k8s(args: list) -> int:
    """Set Kubernetes context."""
    if not args:
        print("Usage: set k8s <context> [namespace] [--kubeconfig PATH]")
        return 1

    data = load_context()
    ctx = data.setdefault("context", {})

    k8s = {"context": args[0]}
    remaining = args[1:]

    # Parse optional namespace and kubeconfig
    i = 0
    while i < len(remaining):
        if remaining[i] == "--kubeconfig" and i + 1 < len(remaining):
            k8s["kubeconfig"] = remaining[i + 1]
            i += 2
        else:
            k8s["namespace"] = remaining[i]
            i += 1

    ctx["kubernetes"] = k8s
    save_context(data)
    print(f"  Kubernetes: {k8s['context']}", end="")
    if k8s.get("namespace"):
        print(f" / {k8s['namespace']}", end="")
    if k8s.get("kubeconfig"):
        print(f" (kubeconfig: {k8s['kubeconfig']})", end="")
    print()
    return 0


def cmd_set_aws(args: list) -> int:
    """Set AWS profile."""
    if not args:
        print("Usage: set aws <profile> [region]")
        return 1

    data = load_context()
    ctx = data.setdefault("context", {})
    ctx["aws"] = {"profile": args[0]}
    if len(args) > 1:
        ctx["aws"]["region"] = args[1]

    save_context(data)
    print(f"  AWS: {ctx['aws']['profile']}", end="")
    if ctx["aws"].get("region"):
        print(f" ({ctx['aws']['region']})", end="")
    print()
    return 0


def cmd_set_env(args: list) -> int:
    """Set environment variables."""
    if not args:
        print("Usage: set env KEY=VALUE [KEY2=VALUE2...]")
        return 1

    data = load_context()
    ctx = data.setdefault("context", {})
    env = ctx.setdefault("env", {})

    for arg in args:
        if "=" in arg:
            key, value = arg.split("=", 1)
            env[key] = value
            print(f"  {key}={value}")
        else:
            print(f"  Warning: Skipping invalid format: {arg}")

    save_context(data)
    return 0


def cmd_set_custom(args: list) -> int:
    """Set custom key-value pairs."""
    if not args:
        print("Usage: set custom KEY=VALUE [KEY2=VALUE2...]")
        return 1

    data = load_context()
    ctx = data.setdefault("context", {})
    custom = ctx.setdefault("custom", {})

    for arg in args:
        if "=" in arg:
            key, value = arg.split("=", 1)
            custom[key] = value
            print(f"  {key}={value}")
        else:
            print(f"  Warning: Skipping invalid format: {arg}")

    save_context(data)
    return 0


def cmd_set_git(args: list) -> int:
    """Set git context (auto-detects if not provided)."""
    data = load_context()
    ctx = data.setdefault("context", {})

    branch = args[0] if args else run_cmd("git rev-parse --abbrev-ref HEAD")
    repo = (
        args[1]
        if len(args) > 1
        else run_cmd("basename $(git remote get-url origin 2>/dev/null) .git")
    )

    if not branch and not repo:
        print("Could not auto-detect git info. Provide branch and repo manually.")
        return 1

    ctx["git"] = {}
    if branch:
        ctx["git"]["branch"] = branch
    if repo:
        ctx["git"]["repo"] = repo

    save_context(data)
    print(f"  Git: {branch or ''}", end="")
    if repo:
        print(f" @ {repo}", end="")
    print()
    return 0


def cmd_clear(args: list) -> int:
    """Clear context sections."""
    if not args:
        print("Usage: clear <section>")
        print("  Sections: k8s, aws, env, git, custom, all")
        return 1

    section = args[0].lower()
    data = load_context()
    ctx = data.get("context", {})

    section_map = {
        "k8s": "kubernetes",
        "kubernetes": "kubernetes",
        "aws": "aws",
        "env": "env",
        "git": "git",
        "custom": "custom",
    }

    if section == "all":
        data["context"] = {}
        save_context(data)
        print("✓ All context cleared for this project")
        return 0

    if section in section_map:
        key = section_map[section]
        if key in ctx:
            del ctx[key]
            save_context(data)
            print(f"✓ Cleared {key} context")
        else:
            print(f"  {key} context was not set")
        return 0

    print(f"Unknown section: {section}")
    print("  Valid sections: k8s, aws, env, git, custom, all")
    return 1


def cmd_json() -> int:
    """Output raw JSON."""
    data = load_context()
    print(json.dumps(data, indent=2))
    return 0


def main() -> int:
    """Main entry point."""
    args = sys.argv[1:]

    if not args or args[0] in ("view", "-v", "--view"):
        return cmd_view()

    if args[0] == "json":
        return cmd_json()

    if args[0] == "list":
        return cmd_list()

    if args[0] == "set" and len(args) > 1:
        subcmd = args[1]
        subargs = args[2:]

        if subcmd == "k8s":
            return cmd_set_k8s(subargs)
        elif subcmd == "aws":
            return cmd_set_aws(subargs)
        elif subcmd == "env":
            return cmd_set_env(subargs)
        elif subcmd == "custom":
            return cmd_set_custom(subargs)
        elif subcmd == "git":
            return cmd_set_git(subargs)
        else:
            print(f"Unknown set command: {subcmd}")
            return 1

    if args[0] == "clear":
        return cmd_clear(args[1:])

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
