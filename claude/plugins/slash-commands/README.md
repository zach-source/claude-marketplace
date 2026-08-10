# slash-commands

18 slash commands.

| Command | What it does |
|---------|--------------|
| `/commit` | Create a git commit |
| `/commit-push-pr` | Commit, push, open a PR |
| `/code-review` | Review a pull request |
| `/review-pr` | Deeper PR review using specialized agents |
| `/clean_gone` | Delete local branches whose remote is gone, plus their worktrees |
| `/feature-dev` | Guided feature development |
| `/create-plugin` | End-to-end plugin creation |
| `/new-sdk-app` | Scaffold a Claude Agent SDK app |
| `/hookify` | Turn unwanted behaviours into hooks |
| `/configure`, `/list` | Enable/disable and list hookify rules |
| `/task:install`, `/task:new`, `/task:list`, `/task:run` | Project task framework |
| `/prompt:context`, `/prompt:reset-context` | Set/clear working context (backed by **context-injection**) |
| `/example-command` | Frontmatter reference |

`/prompt:context` needs the **context-injection** plugin for its state store.
