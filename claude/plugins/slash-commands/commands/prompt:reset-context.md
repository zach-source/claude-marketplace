---
description: Clear working context (all or specific sections)
allowed-tools: ["Bash"]
---

# Reset Working Context

Clear all or specific sections of the working context.

## Usage

```bash
# Clear everything
~/.claude/hooks/context-manager.py clear all

# Clear specific section
~/.claude/hooks/context-manager.py clear k8s
~/.claude/hooks/context-manager.py clear aws
~/.claude/hooks/context-manager.py clear env
~/.claude/hooks/context-manager.py clear git
~/.claude/hooks/context-manager.py clear custom
```

## Implementation

When user runs `/prompt:reset-context`:

1. **No arguments**: Run `~/.claude/hooks/context-manager.py clear all`

2. **`<section>`**: Run `~/.claude/hooks/context-manager.py clear <section>`

Valid sections: `k8s`, `aws`, `env`, `git`, `custom`, `all`

## Examples

```bash
# Clear all context
/prompt:reset-context
/prompt:reset-context all

# Clear specific sections
/prompt:reset-context k8s
/prompt:reset-context aws
/prompt:reset-context env
/prompt:reset-context custom
```
