# subagents

80 specialized subagents. Claude picks them automatically from their descriptions, or you
name one explicitly.

- **Languages** — go, rust, python, typescript, javascript, java, c, c++, php, sql
- **Infra & ops** — kubernetes, terraform (+ provider protocol), cloud architecture, deployment, devops troubleshooting, incident response, network, database admin
- **Review & quality** — code review, architecture review, security audit, type design, comment analysis, silent-failure hunting, PR test analysis, code simplification
- **Data & AI** — data engineering, data science, ML/MLOps, AI engineering, prompt engineering
- **Tooling** — nix, devenv, zellij, neovim/lazyvim, claude config, mcp validation, sqlc, dbos, otel
- **Product & business** — business analysis, content marketing, sales, customer support, legal, UI/UX, quant, risk

Browse `agents/` for the full list — one `.md` per agent, frontmatter carries the trigger
description and model.
