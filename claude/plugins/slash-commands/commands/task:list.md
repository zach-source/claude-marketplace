---
description: List available tasks (local and global)
allowed-tools: ["Bash", "Read", "Glob"]
---

# List Tasks

List all available task prompts from both the current project's `.claude/tasks/` directory and global tasks at `~/.claude/tasks/`.

## Implementation

### 1. Find Local Tasks

```bash
if [ -d ".claude/tasks" ]; then
  find .claude/tasks -maxdepth 2 \( -name "*.md" -o -name "prompt.md" \) 2>/dev/null
fi
```

### 2. Find Global Tasks

```bash
if [ -d "$HOME/.claude/tasks" ]; then
  find "$HOME/.claude/tasks" -maxdepth 2 \( -name "*.md" -o -name "prompt.md" \) 2>/dev/null
fi
```

### 3. Extract Task Info

For each task file found, read the frontmatter to get:
- `description`: What the task does
- `requires`: Prerequisites (if any)

### 4. Display Task List

Format output with sections for local and global:

```markdown
## Available Tasks

### Local Tasks (this project)

| Task | Description |
|------|-------------|
| deploy | Deploy to environment |
| test-unit | Run unit tests |

### Global Tasks

| Task | Description |
|------|-------------|
| github-pr | Create GitHub PR with template |
| gitlab-mr | Create GitLab MR with template |
| git-worktree | Create git worktree |
| jj-workspace | Create jj workspace |

Run a task: `/task:run <name> [args]`
Create a task: `/task:new <name>`
```

## Output Format

```markdown
## Local Tasks (.claude/tasks/)

### deploy
Deploy application to specified environment
**Usage**: `/task:run deploy <env>`

### test-unit
Run unit test suite with coverage
**Usage**: `/task:run test-unit`

---

## Global Tasks (~/.claude/tasks/)

### github-pr
Create GitHub PR with structured description
**Usage**: `/task:run github-pr [base-branch]`

### gitlab-mr
Create GitLab MR with structured description
**Usage**: `/task:run gitlab-mr [target-branch]`

---
**Commands:**
- `/task:run <name>` - Execute a task
- `/task:new <name>` - Create new local task
```

## No Local Tasks Found

If `.claude/tasks/` doesn't exist or is empty but global tasks exist:

```markdown
## Local Tasks

No local tasks defined. Use `/task:new <name>` to create one.

## Global Tasks (~/.claude/tasks/)

[List global tasks here]

---
**Tip**: Local tasks can override global tasks of the same name.
```
