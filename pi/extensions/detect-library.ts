/**
 * Library Detection Extension for Pi
 *
 * When a prompt names an external library and asks a documentation-shaped
 * question, remind Pi to look the docs up instead of answering from training
 * data.
 *
 * Port of the Claude Code `detect-library-hook.py` UserPromptSubmit hook. That
 * hook hardcodes the context7 MCP tool names; Pi's tool set is whatever the
 * mcp-server.ts extension happened to discover, so this checks
 * `getActiveTools()` first and stays silent when no docs tool is loaded. A
 * reminder to call a tool that does not exist is worse than no reminder.
 *
 * Events:
 *   before_agent_start - Inject a docs-lookup reminder
 */
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const LIBRARY_PATTERNS: RegExp[] = [
  // JavaScript/TypeScript
  /\b(react|vue|angular|svelte|nextjs|next\.js|nuxt|gatsby|express|nestjs)\b/gi,
  /\b(redux|mobx|zustand|jotai|recoil|tanstack|react-query)\b/gi,
  /\b(webpack|vite|esbuild|rollup|parcel|turbopack)\b/gi,
  /\b(jest|vitest|mocha|cypress|playwright|puppeteer)\b/gi,
  /\b(tailwind|styled-components|emotion|chakra|material-ui|mui)\b/gi,
  /\b(axios|swr|apollo|graphql|trpc|prisma)\b/gi,
  // Python
  /\b(django|flask|fastapi|starlette|tornado|pyramid)\b/gi,
  /\b(pandas|numpy|scipy|matplotlib|seaborn|plotly)\b/gi,
  /\b(scikit-learn|sklearn|tensorflow|pytorch|keras|transformers)\b/gi,
  /\b(sqlalchemy|peewee|tortoise|pydantic|marshmallow)\b/gi,
  /\b(pytest|hypothesis|coverage|mypy|ruff)\b/gi,
  /\b(celery|dramatiq|huey|arq)\b/gi,
  /\b(requests|httpx|aiohttp|beautifulsoup|scrapy)\b/gi,
  // Go
  /\b(gin|echo|fiber|chi|gorilla|mux)\b/gi,
  /\b(gorm|sqlx|ent|bun)\b/gi,
  /\b(cobra|viper|zap|logrus)\b/gi,
  // Rust
  /\b(tokio|async-std|actix|axum|rocket|warp)\b/gi,
  /\b(serde|diesel|sea-orm)\b/gi,
  /\b(clap|structopt|tracing)\b/gi,
  // Ruby
  /\b(rails|sinatra|hanami|grape)\b/gi,
  /\b(activerecord|sequel|rom-rb)\b/gi,
  // Java/Kotlin
  /\b(spring|springboot|spring-boot|quarkus|micronaut)\b/gi,
  /\b(hibernate|jpa|mybatis|exposed)\b/gi,
  // Databases
  /\b(postgresql|postgres|mysql|sqlite|mongodb|redis)\b/gi,
  /\b(elasticsearch|opensearch|meilisearch|algolia)\b/gi,
  // Infrastructure
  /\b(docker|kubernetes|k8s|terraform|pulumi|ansible)\b/gi,
  /\b(aws|gcp|azure|cloudflare|vercel|netlify)\b/gi,
];

const DOC_PHRASES =
  /\b(how do i|how to|how does|what is the|show me how|example of|documentation for|docs for|api for|guide for|tutorial|best practice|getting started|quickstart)\b/i;

/** Tool-name fragments that mean "this session can fetch real documentation". */
const DOCS_TOOL_HINTS = ["context7", "get-library-docs", "get_library_docs"];

function detectLibraries(text: string): string[] {
  const found = new Set<string>();
  for (const pattern of LIBRARY_PATTERNS) {
    for (const match of text.matchAll(pattern))
      found.add(match[0].toLowerCase());
  }
  return [...found];
}

function findDocsTool(tools: string[]): string | undefined {
  return tools.find((tool) =>
    DOCS_TOOL_HINTS.some((hint) => tool.toLowerCase().includes(hint)),
  );
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event) => {
    if (!DOC_PHRASES.test(event.prompt)) return;

    const libraries = detectLibraries(event.prompt);
    if (libraries.length === 0) return;

    const docsTool = findDocsTool(pi.getActiveTools());
    if (!docsTool) return; // Nothing to point the model at.

    const named = libraries.slice(0, 3).join(", ");
    return {
      message: {
        customType: "detect-library",
        content: `<reminder>External library detected: ${named}. Use the ${docsTool} tool for current documentation rather than answering from training data.</reminder>`,
        display: false,
      },
    };
  });
}
