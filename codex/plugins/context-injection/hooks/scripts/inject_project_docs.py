#!/usr/bin/env python3
"""
Inject critical project documentation into Claude's context automatically.

This hook runs on UserPromptSubmit and checks for the presence of critical
project documentation files (STATUS.md, TASKS.md, SESSION_HISTORY.md).
If found, it reads them and injects them into the context with high-priority
XML tags to ensure Claude pays attention to them.

Based on Anthropic's best practices:
- Uses XML tags for structure (Claude was trained with XML)
- Places critical content at the beginning (primacy effect)
- Uses clear, structured formatting
- Enforces chain-of-thought reasoning
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Configuration
CRITICAL_FILES = [
    ("STATUS.md", "project-status", "Current Project State"),
    ("TASKS.md", "immediate-tasks", "Tasks to Execute"),
    ("SESSION_HISTORY.md", "session-history", "Previous Work Context"),
]

MAX_FILE_SIZE = 50000  # Maximum characters per file to prevent token overflow
ENABLE_DEBUG = os.getenv("CLAUDE_HOOKS_DEBUG", "0") == "1"


def debug_log(message: str) -> None:
    """Log debug messages to stderr."""
    if ENABLE_DEBUG:
        print(f"[DEBUG] inject_project_docs: {message}", file=sys.stderr)


def find_project_root(start_path: Path) -> Optional[Path]:
    """
    Find the project root by looking for git repository or known markers.

    Args:
        start_path: Starting directory to search from

    Returns:
        Path to project root or None if not found
    """
    current = start_path.resolve()

    # Look for common project markers
    markers = [".git", "flake.nix", "package.json", "Cargo.toml", "go.mod", "README.md"]

    while current != current.parent:
        for marker in markers:
            if (current / marker).exists():
                debug_log(f"Found project root at: {current}")
                return current
        current = current.parent

    # If we didn't find a marker, check if we're in a known project directory
    if start_path.name in ["nix-dotfiles", "dotfiles"]:
        debug_log(f"Using current directory as project root: {start_path}")
        return start_path

    return None


def read_file_safely(file_path: Path, max_size: int = MAX_FILE_SIZE) -> Optional[str]:
    """
    Safely read a file with size limits and error handling.

    Args:
        file_path: Path to the file
        max_size: Maximum size in characters

    Returns:
        File content or None if error
    """
    try:
        if not file_path.exists():
            return None

        # Check file size first
        file_size = file_path.stat().st_size
        if file_size > max_size * 2:  # Rough byte estimate
            debug_log(f"File {file_path} is too large ({file_size} bytes), truncating")

        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read(max_size)

        # Add truncation indicator if needed
        if len(content) == max_size:
            content += "\n\n[... FILE TRUNCATED FOR TOKEN LIMITS ...]"

        return content
    except Exception as e:
        debug_log(f"Error reading {file_path}: {e}")
        return None


def format_document_injection(docs: List[Tuple[str, str, str]]) -> str:
    """
    Format the injected documents with XML tags and structure.

    Args:
        docs: List of (filename, tag, content) tuples

    Returns:
        Formatted injection string
    """
    if not docs:
        return ""

    injection = '\n<project-context priority="critical">\n'
    injection += "<instruction>The following project documentation contains critical context. Read and internalize before proceeding.</instruction>\n\n"

    for filename, tag, content in docs:
        injection += f'<{tag} source="{filename}">\n'
        injection += content
        injection += f"\n</{tag}>\n\n"

    injection += "</project-context>\n\n"

    # Add a chain-of-thought reminder
    injection += """<thinking>
I have just read the critical project documentation:
- STATUS.md provides the current project state
- TASKS.md shows what needs to be done
- SESSION_HISTORY.md gives context from previous work

I will now proceed with the user's request while keeping this context in mind.
</thinking>

"""

    return injection


def main():
    """Main hook execution.

    A hook is not a filter: the payload is not piped through it. Whatever this
    writes to stdout is the hook's *result*, and on UserPromptSubmit it becomes
    context the model reads. Echoing the payload back therefore dumped session_id,
    cwd and every other envelope field into the conversation on every prompt, with
    the documents reaching the model only incidentally, inside a "prompt" key
    nothing reads back. Emit additionalContext, or nothing at all.
    """
    try:
        # Read the input from stdin
        input_data = sys.stdin.read()

        # Parse the JSON payload
        try:
            payload = json.loads(input_data)
        except json.JSONDecodeError:
            debug_log("Failed to parse JSON input")
            return 0

        # Extract the working directory
        cwd = payload.get("cwd", os.getcwd())

        # Find the project root
        project_root = find_project_root(Path(cwd))
        if not project_root:
            debug_log("No project root found, skipping injection")
            return 0

        # Check for and read critical files
        documents_to_inject = []

        for filename, tag, description in CRITICAL_FILES:
            file_path = project_root / filename
            content = read_file_safely(file_path)

            if content:
                debug_log(f"Found {filename} with {len(content)} characters")
                documents_to_inject.append((filename, tag, content))
            else:
                debug_log(f"{filename} not found or empty")

        # Nothing found is not a failure - say nothing rather than burn context.
        if not documents_to_inject:
            debug_log("No project documents found, staying quiet")
            return 0

        injection = format_document_injection(documents_to_inject)
        debug_log(f"Injected {len(documents_to_inject)} documents into context")
        debug_log(f"Total injection size: {len(injection)} characters")

        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "UserPromptSubmit",
                        "additionalContext": injection,
                    }
                }
            )
        )
        return 0

    except Exception as e:
        debug_log(f"Unexpected error: {e}")
        # Failing to inject context is never worth disrupting the prompt.
        return 1


if __name__ == "__main__":
    sys.exit(main())
