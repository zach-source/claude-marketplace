#!/usr/bin/env python3
"""Validate the Codex plugin tree against the documented plugin format.

Checks every codex/plugins/*/.codex-plugin/plugin.json and the marketplace at
.agents/plugins/marketplace.json. Exits non-zero with one line per problem.

Spec: https://developers.openai.com/plugins/build/plugins
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEBAB = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
POINTERS = ("skills", "mcpServers", "apps", "hooks")
INSTALLATION = {"AVAILABLE", "INSTALLED_BY_DEFAULT", "NOT_AVAILABLE"}

errors = []


def bad(where, msg):
    errors.append(f"{where}: {msg}")


def load(path):
    """Parse JSON, recording a syntax error instead of raising."""
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        bad(path.relative_to(ROOT), f"invalid JSON - {e}")
        return None


def check_path(where, field, value, plugin_root):
    """Component pointers must start with ./, stay inside the root, and exist."""
    if not value.startswith("./"):
        bad(where, f"{field} path {value!r} must start with './'")
        return
    target = (plugin_root / value).resolve()
    if not target.is_relative_to(plugin_root.resolve()):
        bad(where, f"{field} path {value!r} escapes the plugin root")
    elif not target.exists():
        bad(where, f"{field} points at missing {value}")


def check_skill(where, skill_dir):
    md = skill_dir / "SKILL.md"
    if not md.exists():
        bad(where, f"skill {skill_dir.name}/ has no SKILL.md")
        return
    text = md.read_text()
    if not text.startswith("---\n"):
        bad(where, f"{skill_dir.name}/SKILL.md has no YAML frontmatter")
        return
    fm = text.split("---\n", 2)[1]
    for key in ("name", "description"):
        if not re.search(rf"^{key}:", fm, re.M):
            bad(where, f"{skill_dir.name}/SKILL.md frontmatter missing '{key}'")


def check_plugin(manifest_path):
    where = manifest_path.relative_to(ROOT)
    plugin_root = manifest_path.parent.parent
    data = load(manifest_path)
    if data is None:
        return None
    if not isinstance(data, dict):
        bad(where, "manifest must be a JSON object")
        return None

    for field in ("name", "version", "description"):
        if not isinstance(data.get(field), str) or not data[field]:
            bad(where, f"missing required string field '{field}'")
    name = data.get("name")
    if isinstance(name, str) and not KEBAB.match(name):
        bad(where, f"name {name!r} is not kebab-case")
    if name and name != plugin_root.name:
        bad(where, f"name {name!r} does not match directory {plugin_root.name!r}")

    # .codex-plugin/ holds nothing but plugin.json
    strays = [p.name for p in manifest_path.parent.iterdir() if p.name != "plugin.json"]
    if strays:
        bad(where, f".codex-plugin/ must contain only plugin.json, found {strays}")

    if "author" in data and not isinstance(data["author"], (str, dict)):
        bad(where, "author must be a string or an object")
    if "keywords" in data and not (
        isinstance(data["keywords"], list)
        and all(isinstance(k, str) for k in data["keywords"])
    ):
        bad(where, "keywords must be an array of strings")

    for field in POINTERS:
        value = data.get(field)
        if value is None:
            continue
        if field == "hooks" and isinstance(value, (dict, list)):
            # hooks may be inline objects or an array of paths/objects
            entries = value if isinstance(value, list) else []
            for entry in entries:
                if isinstance(entry, str):
                    check_path(where, field, entry, plugin_root)
            continue
        if not isinstance(value, str):
            bad(where, f"{field} must be a path string")
            continue
        check_path(where, field, value, plugin_root)

    skills = data.get("skills")
    if isinstance(skills, str):
        skills_dir = plugin_root / skills
        if skills_dir.is_dir():
            found = [d for d in sorted(skills_dir.iterdir()) if d.is_dir()]
            if not found:
                bad(where, f"skills dir {skills} contains no skill folders")
            for skill_dir in found:
                check_skill(where, skill_dir)

    hooks = data.get("hooks")
    if isinstance(hooks, str):
        hooks_file = plugin_root / hooks
        if hooks_file.is_file():
            hook_data = load(hooks_file)
            if isinstance(hook_data, dict) and "hooks" not in hook_data:
                bad(
                    hooks_file.relative_to(ROOT),
                    "must wrap events in a top-level 'hooks' object",
                )

    mcp = data.get("mcpServers")
    if isinstance(mcp, str) and (plugin_root / mcp).is_file():
        load(plugin_root / mcp)

    return data


def check_marketplace(plugins):
    path = ROOT / ".agents" / "plugins" / "marketplace.json"
    where = path.relative_to(ROOT)
    if not path.exists():
        bad(where, "marketplace file is missing")
        return
    data = load(path)
    if data is None:
        return
    if not isinstance(data.get("name"), str):
        bad(where, "marketplace needs a string 'name'")
    entries = data.get("plugins")
    if not isinstance(entries, list) or not entries:
        bad(where, "marketplace needs a non-empty 'plugins' array")
        return

    listed = set()
    for entry in entries:
        name = entry.get("name", "<unnamed>")
        tag = f"{where}[{name}]"
        listed.add(name)
        policy = entry.get("policy")
        if not isinstance(policy, dict):
            bad(tag, "missing required 'policy' object")
        else:
            if policy.get("installation") not in INSTALLATION:
                bad(tag, f"policy.installation must be one of {sorted(INSTALLATION)}")
            if not isinstance(policy.get("authentication"), str):
                bad(tag, "missing required 'policy.authentication'")
        if not isinstance(entry.get("category"), str):
            bad(tag, "missing required 'category'")

        source = entry.get("source")
        rel = source if isinstance(source, str) else (source or {}).get("path")
        if not isinstance(rel, str):
            bad(tag, "local entry needs a 'source' path")
            continue
        if not rel.startswith("./"):
            bad(tag, f"source path {rel!r} must start with './'")
            continue
        target = (ROOT / rel).resolve()
        if not target.is_relative_to(ROOT):
            bad(tag, f"source path {rel!r} escapes the marketplace root")
        elif not (target / ".codex-plugin" / "plugin.json").exists():
            bad(tag, f"source path {rel!r} has no .codex-plugin/plugin.json")

    for name in sorted(plugins - listed):
        bad(where, f"plugin {name!r} exists on disk but is not listed")
    for name in sorted(listed - plugins):
        bad(where, f"plugin {name!r} is listed but has no manifest on disk")


def main():
    manifests = sorted((ROOT / "codex" / "plugins").glob("*/.codex-plugin/plugin.json"))
    if not manifests:
        print("no plugin manifests found under codex/plugins/", file=sys.stderr)
        return 1
    names = set()
    for manifest in manifests:
        data = check_plugin(manifest)
        if data and isinstance(data.get("name"), str):
            names.add(data["name"])
    check_marketplace(names)

    for line in errors:
        print(f"FAIL {line}", file=sys.stderr)
    print(f"checked {len(manifests)} plugin manifest(s): {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
