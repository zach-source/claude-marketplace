---
description: Set or view working context (k8s, aws, env vars, custom) - reduces uncertainty
allowed-tools: ["Read", "Bash"]
---

# Working Context Manager

Set or view working context that persists across sessions. Context is automatically injected into prompts via the `inject-context` hook.

**When to use**: Set context when starting work on a specific cluster, environment, or project. This reduces uncertainty and enables more accurate actions.

**Uncertainty reduction**: Well-defined context increases action certainty from ~60% (unknown environment) to >90% (known cluster, namespace, profile).

## Usage

### Natural Language Mode (Recommended)

```
/prompt:context set "<natural language description>"
```

Parse the description and extract context values, then call the appropriate context-manager.py commands.

**Examples:**
```
/prompt:context set "k8s is prod-cluster namespace api; aws profile production in us-west-2"
/prompt:context set "working on crossplane; note: deploying to nexus-dev cluster"
/prompt:context set "k8s cluster nexus-dev; note: XRDs and compositions go here"
```

### Quick Commands

```bash
# View current context
~/.claude/hooks/context-manager.py view

# Set Kubernetes
~/.claude/hooks/context-manager.py set k8s <context> [namespace] [--kubeconfig PATH]

# Set AWS
~/.claude/hooks/context-manager.py set aws <profile> [region]

# Set environment variables
~/.claude/hooks/context-manager.py set env KEY=VALUE [KEY2=VALUE2...]

# Set custom values
~/.claude/hooks/context-manager.py set custom KEY=VALUE [KEY2=VALUE2...]

# Set git (auto-detects if not provided)
~/.claude/hooks/context-manager.py set git [branch] [repo]

# Clear context
~/.claude/hooks/context-manager.py clear <section>  # k8s, aws, env, git, custom, all
```

## Implementation

### 1. No arguments or `view`
Run `~/.claude/hooks/context-manager.py view`

### 2. Natural Language: `set "<description>"`

Parse the natural language description to extract:

| Pattern | Maps To | Example |
|---------|---------|---------|
| `k8s is/cluster is/kubernetes` + name | `set k8s <name>` | "k8s is prod-cluster" |
| `namespace` + name | `set k8s <ctx> <namespace>` | "namespace api" |
| `kubeconfig` + path | `set k8s <ctx> --kubeconfig <path>` | "kubeconfig ~/.kube/dev" |
| `aws profile/aws is` + name | `set aws <profile>` | "aws profile production" |
| `region` + name | `set aws <profile> <region>` | "region us-west-2" |
| `note:/working on/project:` + text | `set custom note=<text>` | "note: deploying crossplane" |
| `team` + name | `set custom team=<name>` | "team platform" |
| `env` + KEY=VALUE | `set env KEY=VALUE` | "env DEBUG=true" |

**Parsing rules:**
- Split on `;` for multiple statements
- Extract key patterns and their values
- Call context-manager.py for each extracted value
- Preserve existing context (merge, don't replace)

**Example parsing:**

Input: `"k8s cluster nexus-dev namespace api; note: working on XRDs"`

Extract:
1. k8s context: `nexus-dev`
2. k8s namespace: `api`
3. custom note: `working on XRDs`

Execute:
```bash
~/.claude/hooks/context-manager.py set k8s nexus-dev api
~/.claude/hooks/context-manager.py set custom "note=working on XRDs"
```

### 3. Quick commands: `k8s`, `aws`, `env`, `custom`, `git`

Run `~/.claude/hooks/context-manager.py set <type> <args>`

## Examples

```bash
# Natural language (parse and update)
/prompt:context set "k8s is prod-cluster in namespace api"
/prompt:context set "aws profile staging; region us-east-1"
/prompt:context set "note: deploying new feature; team platform"
/prompt:context set "k8s nexus-dev; kubeconfig ~/.kube/nexus; note: crossplane cluster"

# Quick commands
/prompt:context k8s prod-cluster api-namespace
/prompt:context aws production us-west-2
/prompt:context custom team=platform note="working on feature X"

# View
/prompt:context
/prompt:context view

# Clear
/prompt:context clear k8s
/prompt:context clear all
```

## Output

After updating, show the new context state:

```
## Context Updated

**Set:**
- Kubernetes: nexus-dev / api
- Note: working on XRDs

**Current Context:**
- Kubernetes: nexus-dev / api
- AWS: production (us-west-2)
- Git: main @ my-repo
- Note: working on XRDs

Updated: just now
```
