---
description: Create a new local project task template
allowed-tools: ["Bash", "Write", "AskUserQuestion"]
---

# Create New Task

Create a new task template in the project's `.claude/tasks/` directory.

## Usage

```
/task:new <task-name>
/task:new <task-name> --complex   # Create directory-based task
```

## Implementation

### 1. Parse Arguments

Get task name from `$ARGUMENTS`. Validate it's a valid filename (alphanumeric, hyphens, underscores).

### 2. Create Tasks Directory

```bash
mkdir -p .claude/tasks
```

### 3. Check for Existing Task

```bash
if [ -f ".claude/tasks/$TASK_NAME.md" ] || [ -d ".claude/tasks/$TASK_NAME" ]; then
  echo "Task '$TASK_NAME' already exists"
  exit 1
fi
```

### 4. Ask for Task Details (Optional)

Use AskUserQuestion to gather:

```json
{
  "questions": [
    {
      "question": "What type of task is this?",
      "header": "Type",
      "multiSelect": false,
      "options": [
        { "label": "Build/Deploy", "description": "Build or deployment automation" },
        { "label": "Testing", "description": "Test execution or validation" },
        { "label": "Database", "description": "Migrations or data operations" },
        { "label": "Code Generation", "description": "Generate code or configs" },
        { "label": "Custom", "description": "Other task type" }
      ]
    }
  ]
}
```

### 5. Create Task File

Write the task template to `.claude/tasks/<name>.md`:

```markdown
---
description: [Brief description of the task]
allowed-tools: ["Read", "Write", "Bash", "Glob", "Grep"]
context-files: []
requires: []
---

# Task: <Task Name>

[Describe what this task accomplishes]

## Arguments

- `$1` - [First argument description]
- `$2` - [Optional second argument]

## Prerequisites

- [List any requirements before running]

## Steps

1. **Step One**
   [Detailed instructions for first step]

2. **Step Two**
   [Detailed instructions for second step]

3. **Verify Results**
   [How to confirm task completed successfully]

## Examples

```bash
# Basic usage
/task:run <name>

# With arguments
/task:run <name> arg1 arg2
```

## Notes

- [Any additional notes or warnings]
```

### 6. For Complex Tasks (--complex flag)

Create a directory structure:

```
.claude/tasks/<name>/
  prompt.md       # Main task prompt
  checklist.md    # Validation checklist
  README.md       # Documentation
```

### 7. Confirm Creation

```markdown
## Task Created

Created `.claude/tasks/<name>.md`

Edit the task file to customize:
- Description and purpose
- Required arguments
- Step-by-step instructions
- Prerequisites

Run the task: `/task:run <name>`
List all tasks: `/task:list`
```

## Task Templates by Type

### Build/Deploy Template
```markdown
---
description: Deploy to [environment]
allowed-tools: ["Bash", "Read"]
requires:
  - Valid credentials configured
  - Clean git working directory
---

# Deploy Task

Deploy the application to the specified environment.

## Arguments
- `$1` - Environment (dev/staging/prod)

## Steps
1. Verify environment argument
2. Run pre-deploy checks
3. Build application
4. Deploy to environment
5. Run smoke tests
6. Report status
```

### Testing Template
```markdown
---
description: Run [test type] tests
allowed-tools: ["Bash", "Read"]
context-files:
  - package.json
  - jest.config.js
---

# Test Task

Run the test suite with coverage reporting.

## Steps
1. Check test dependencies
2. Run test command
3. Report coverage
4. Highlight failures
```

### Database Template
```markdown
---
description: Run database migrations
allowed-tools: ["Bash", "Read"]
requires:
  - Database connection available
  - Migration files exist
---

# Migration Task

Execute database migrations.

## Arguments
- `$1` - Direction (up/down)
- `$2` - Optional: number of migrations

## Steps
1. Verify database connection
2. Show pending migrations
3. Execute migrations
4. Verify schema state
```
