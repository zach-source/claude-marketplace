#!/usr/bin/env python3
"""
Inject working context into Claude prompts automatically (per-project).

This hook runs on UserPromptSubmit and checks for the presence of a
working context file for the current project. Context is stored per-project
based on git root or CWD, so each project has its own isolated context.

Context includes:
- Kubernetes context/namespace
- AWS profile/region
- Environment variables
- Git branch/repo
- Custom key-value pairs
"""

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# Configuration
CONTEXTS_DIR = Path.home() / ".claude" / "contexts"
MAX_AGE_HOURS = 24  # Warn if context is older than this
ENABLE_DEBUG = os.getenv("CLAUDE_HOOKS_DEBUG", "0") == "1"


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
    path_str = str(project_root.resolve())
    hash_digest = hashlib.sha256(path_str.encode()).hexdigest()[:12]
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


def debug_log(message: str) -> None:
    """Log debug messages to stderr."""
    if ENABLE_DEBUG:
        print(f"[DEBUG] inject-context: {message}", file=sys.stderr)


def load_context() -> Optional[Dict[str, Any]]:
    """Load the working context from the project-specific file."""
    try:
        context_file, project_id, project_root = get_context_file()

        if not context_file.exists():
            debug_log(f"Context file does not exist for project: {project_root.name}")
            return None

        with open(context_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        debug_log(
            f"Loaded context for {project_root.name}: {json.dumps(data, indent=2)}"
        )
        return data
    except json.JSONDecodeError as e:
        debug_log(f"Invalid JSON in context file: {e}")
        return None
    except Exception as e:
        debug_log(f"Error reading context file: {e}")
        return None


def get_context_age(data: Dict[str, Any]) -> Optional[str]:
    """Calculate how old the context is."""
    try:
        updated = data.get("updated")
        if not updated:
            return None

        updated_dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = now - updated_dt

        hours = delta.total_seconds() / 3600
        if hours < 1:
            minutes = int(delta.total_seconds() / 60)
            return f"{minutes}m ago"
        elif hours < 24:
            return f"{int(hours)}h ago"
        else:
            days = int(hours / 24)
            return f"{days}d ago"
    except Exception as e:
        debug_log(f"Error calculating context age: {e}")
        return None


def is_context_stale(data: Dict[str, Any]) -> bool:
    """Check if context is older than MAX_AGE_HOURS."""
    try:
        updated = data.get("updated")
        if not updated:
            return True

        updated_dt = datetime.fromisoformat(updated.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        delta = now - updated_dt

        return delta.total_seconds() / 3600 > MAX_AGE_HOURS
    except Exception:
        return True


def format_context_block(data: Dict[str, Any]) -> str:
    """Format the context into a readable block."""
    context = data.get("context", {})
    if not context:
        return ""

    lines = []

    # Kubernetes
    k8s = context.get("kubernetes", {})
    if k8s.get("context") or k8s.get("namespace"):
        k8s_str = k8s.get("context", "default")
        if k8s.get("namespace"):
            k8s_str += f" / {k8s['namespace']}"
        lines.append(f"Kubernetes: {k8s_str}")

    # AWS
    aws = context.get("aws", {})
    if aws.get("profile") or aws.get("region"):
        aws_str = aws.get("profile", "default")
        if aws.get("region"):
            aws_str += f" ({aws['region']})"
        lines.append(f"AWS Profile: {aws_str}")

    # Git
    git = context.get("git", {})
    if git.get("branch") or git.get("repo"):
        git_str = git.get("branch", "")
        if git.get("repo"):
            git_str = f"{git_str} @ {git['repo']}" if git_str else git["repo"]
        if git_str:
            lines.append(f"Git: {git_str}")

    # Environment variables
    env = context.get("env", {})
    if env:
        env_str = ", ".join(f"{k}={v}" for k, v in env.items())
        lines.append(f"Env: {env_str}")

    # Custom values
    custom = context.get("custom", {})
    if custom:
        custom_str = ", ".join(f"{k}={v}" for k, v in custom.items())
        lines.append(f"Custom: {custom_str}")

    if not lines:
        return ""

    # Build the context block
    age = get_context_age(data)
    stale_warning = ""
    if is_context_stale(data):
        stale_warning = " (STALE - consider updating with /context)"

    block = "<working-context>\n"
    for line in lines:
        block += f"  {line}\n"
    if age:
        block += f"  Updated: {age}{stale_warning}\n"
    block += "</working-context>"

    return block


def main():
    """Main hook execution."""
    try:
        # Read the input from stdin
        input_data = sys.stdin.read()

        # Parse the JSON payload
        try:
            payload = json.loads(input_data)
        except json.JSONDecodeError:
            debug_log("Failed to parse JSON input")
            # Pass through unchanged
            print(json.dumps({"continue": True}))
            return 0

        # Get the prompt
        prompt = payload.get("prompt", "")

        # Check if context is already present in prompt
        if "<working-context>" in prompt:
            debug_log("Context already present in prompt, skipping injection")
            print(json.dumps({"continue": True}))
            return 0

        # Load the working context
        context_data = load_context()
        if not context_data:
            debug_log("No context data to inject")
            print(json.dumps({"continue": True}))
            return 0

        # Format the context block
        context_block = format_context_block(context_data)
        if not context_block:
            debug_log("Context data is empty")
            print(json.dumps({"continue": True}))
            return 0

        # Return the context as a message to be added
        debug_log(f"Injecting context:\n{context_block}")

        # Use the 'message' field to inject context
        result = {"continue": True, "message": f"\n{context_block}\n"}

        print(json.dumps(result))
        return 0

    except Exception as e:
        debug_log(f"Unexpected error: {e}")
        # On error, continue without injection
        print(json.dumps({"continue": True}))
        return 0


if __name__ == "__main__":
    sys.exit(main())
