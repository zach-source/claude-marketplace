---
description: Execute a task from local project or global tasks
allowed-tools: ["Read", "Bash", "Glob", "Grep", "Write", "Edit", "Task", "WebFetch", "WebSearch", "AskUserQuestion"]
---

# Run Task

Execute a task prompt from either the current project's `.claude/tasks/` directory or global tasks at `~/.claude/tasks/`.

## Usage

```
/task:run <task-name>
/task:run <task-name> [arguments...]
```

## Implementation

### 1. Locate Task File

Search for the task file in order (local takes precedence):
1. `.claude/tasks/<task-name>.md` (project-local)
2. `.claude/tasks/<task-name>/prompt.md` (project-local complex)
3. `~/.claude/tasks/<task-name>.md` (global)
4. `~/.claude/tasks/<task-name>/prompt.md` (global complex)

```bash
# Check local tasks first
TASK_FILE=".claude/tasks/$TASK_NAME.md"
if [ ! -f "$TASK_FILE" ]; then
  TASK_FILE=".claude/tasks/$TASK_NAME/prompt.md"
fi
# Fall back to global tasks
if [ ! -f "$TASK_FILE" ]; then
  TASK_FILE="$HOME/.claude/tasks/$TASK_NAME.md"
fi
if [ ! -f "$TASK_FILE" ]; then
  TASK_FILE="$HOME/.claude/tasks/$TASK_NAME/prompt.md"
fi
```

### 2. Read and Parse Task

Read the task file. It should have frontmatter with metadata:

```markdown
---
description: Brief description of what this task does
allowed-tools: ["Read", "Write", "Bash"]  # Optional: restrict tools
context-files:                             # Optional: files to read first
  - src/config.ts
  - package.json
requires:                                  # Optional: prerequisites
  - node_modules exists
  - .env file configured
---

# Task: Build and Deploy

[Task instructions here...]

## Arguments

- `$1` - Environment (dev/staging/prod)
- `$2` - Optional flags

## Steps

1. First step...
2. Second step...
```

### 3. Load Context Files

If `context-files` is specified in frontmatter, read those files first to provide context.

### 4. Check Prerequisites

If `requires` is specified, verify prerequisites are met before proceeding.

### 5. Execute Task

Follow the task instructions. Arguments passed to `/task:run` are available as `$ARGUMENTS`.

### 6. Report Results

After completing the task, summarize what was done.

## Example

```bash
# Run a deploy task
/task:run deploy staging

# Run a test task
/task:run test-unit

# Run with multiple args
/task:run migrate up --dry-run
```

## Task File Structure

Tasks are stored in `.claude/tasks/` with this structure:

```
.claude/
  tasks/
    deploy.md           # Simple task file
    test-unit.md        # Another task
    complex-task/       # Complex task with resources
      prompt.md         # Main task prompt
      checklist.md      # Optional checklist
      resources/        # Supporting files
```

## Error Handling

- **Task not found**: List available tasks with `/task:list`
- **Prerequisites not met**: Report which prerequisites failed
- **Execution error**: Report error and suggest fixes

## Notes

- **Local tasks**: Project-specific, stored in `.claude/tasks/` (can be committed to repo)
- **Global tasks**: Available everywhere, stored in `~/.claude/tasks/`
- Local tasks take precedence if same name exists in both locations
- Use `/task:list` to see all available tasks (local + global)
- Use `/task:new` to create a new local task template
