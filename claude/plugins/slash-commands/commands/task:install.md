---
description: Initialize task framework in current project directory
allowed-tools: ["Bash", "Write", "Read"]
---

# Install Task Framework

Initialize the `.claude/tasks/` directory structure in the current project with example tasks and documentation.

## Usage

```
/task:install [--examples]
```

Options:
- `--examples`: Include example task templates (default: true)

## Implementation

### 1. Check Current Directory

Verify we're in a project directory (has .git or package.json or similar):

```bash
if [ ! -d ".git" ] && [ ! -f "package.json" ] && [ ! -f "Makefile" ] && [ ! -f "flake.nix" ]; then
  echo "Warning: This doesn't appear to be a project root directory."
  # Ask user if they want to continue
fi
```

### 2. Create Directory Structure

```bash
mkdir -p .claude/tasks
```

### 3. Create README

Write `.claude/tasks/README.md`:

```markdown
# Project Tasks

This directory contains local task definitions for this project.

## Usage

- `/task:list` - List available tasks
- `/task:run <name> [args]` - Execute a task
- `/task:new <name>` - Create a new task

## Task Structure

Each task is a markdown file with YAML frontmatter:

\`\`\`markdown
---
description: Brief description of the task
allowed-tools: ["Bash", "Read", "Write"]
context-files:
  - package.json
  - README.md
requires:
  - Node.js installed
  - Valid credentials configured
---

# Task: Name

[What this task accomplishes]

## Arguments

- `$1` - First argument description
- `$2` - Optional second argument

## Steps

1. **Step One**
   [Instructions]

2. **Step Two**
   [Instructions]

## Verification

[How to verify the task succeeded]
\`\`\`

## Tips

- Keep tasks focused on a single workflow
- Include verification steps
- Document all arguments clearly
- Use `context-files` to ensure context is loaded
- Add `requires` for prerequisites
```

### 4. Create Example Tasks (if --examples)

#### Example: build.md

```markdown
---
description: Build the project
allowed-tools: ["Bash", "Read"]
context-files:
  - package.json
---

# Task: Build

Build the project for production.

## Steps

1. **Check Dependencies**
   ```bash
   # For Node.js projects
   if [ -f "package.json" ]; then
     npm ci || npm install
   fi
   ```

2. **Run Build**
   ```bash
   # Detect build system and run
   if [ -f "package.json" ]; then
     npm run build
   elif [ -f "Makefile" ]; then
     make build
   elif [ -f "Cargo.toml" ]; then
     cargo build --release
   fi
   ```

3. **Verify Build**
   Check that build artifacts were created.

## Notes

- Customize this task for your specific build process
```

#### Example: test.md

```markdown
---
description: Run project tests
allowed-tools: ["Bash", "Read"]
---

# Task: Test

Run the project's test suite.

## Arguments

- `$1` - Optional: specific test file or pattern

## Steps

1. **Run Tests**
   ```bash
   # Detect test framework and run
   if [ -f "package.json" ]; then
     npm test -- $1
   elif [ -f "Makefile" ]; then
     make test
   elif [ -f "Cargo.toml" ]; then
     cargo test $1
   elif [ -f "pytest.ini" ] || [ -f "setup.py" ]; then
     pytest $1
   fi
   ```

2. **Report Results**
   Show test summary and any failures.
```

#### Example: deploy.md

```markdown
---
description: Deploy to specified environment
allowed-tools: ["Bash", "Read"]
requires:
  - Valid credentials configured
  - Clean git working directory
---

# Task: Deploy

Deploy the application to the specified environment.

## Arguments

- `$1` - Environment: `dev`, `staging`, or `prod` (required)

## Prerequisites

- All tests passing
- Clean git working directory
- Valid deployment credentials

## Steps

1. **Validate Arguments**
   Ensure environment argument is provided and valid.

2. **Check Git Status**
   ```bash
   git status --porcelain
   ```
   Fail if there are uncommitted changes.

3. **Run Pre-deploy Checks**
   - Run tests
   - Check for required env vars

4. **Deploy**
   Execute deployment based on environment.

5. **Verify Deployment**
   Run smoke tests against deployed environment.

## Notes

- Never deploy to prod without staging first
- Always verify with smoke tests
```

### 5. Update .gitignore (Optional)

Check if `.gitignore` exists and whether to add `.claude/tasks/`:

For private tasks (not shared with team):
```
.claude/tasks/
```

For shared tasks (committed to repo):
```
# Keep .claude/tasks/ in git for team-shared tasks
```

### 6. Confirm Installation

Output:

```markdown
## Task Framework Installed ✅

Created `.claude/tasks/` directory with:
- README.md - Documentation
- build.md - Build task template
- test.md - Test task template
- deploy.md - Deploy task template

### Next Steps

1. **Customize tasks** for your project:
   ```
   # Edit the example tasks
   code .claude/tasks/
   ```

2. **Create new tasks**:
   ```
   /task:new my-task-name
   ```

3. **Run a task**:
   ```
   /task:run build
   /task:run test
   /task:run deploy staging
   ```

4. **Decide on git tracking**:
   - **Shared tasks**: Commit `.claude/tasks/` for team use
   - **Private tasks**: Add to `.gitignore`

### Commands

| Command | Description |
|---------|-------------|
| `/task:list` | List all available tasks |
| `/task:run <name>` | Execute a task |
| `/task:new <name>` | Create a new task |
| `/task:install` | Re-run this installer |
```

## Without Examples

If `--examples` is not specified or `--no-examples`:
- Only create `.claude/tasks/README.md`
- Skip example task files
- Still show instructions for creating tasks
