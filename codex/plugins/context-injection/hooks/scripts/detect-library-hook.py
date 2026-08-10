#!/usr/bin/env python3
"""
Library Detection Hook for UserPromptSubmit

Detects mentions of external libraries/frameworks in user prompts
and injects a reminder to use the context7 skill for documentation.
"""

import json
import re
import sys

# Common library/framework patterns
LIBRARY_PATTERNS = [
    # JavaScript/TypeScript
    r"\b(react|vue|angular|svelte|nextjs|next\.js|nuxt|gatsby|express|nestjs)\b",
    r"\b(redux|mobx|zustand|jotai|recoil|tanstack|react-query)\b",
    r"\b(webpack|vite|esbuild|rollup|parcel|turbopack)\b",
    r"\b(jest|vitest|mocha|cypress|playwright|puppeteer)\b",
    r"\b(tailwind|styled-components|emotion|chakra|material-ui|mui)\b",
    r"\b(axios|fetch|swr|apollo|graphql|trpc|prisma)\b",
    # Python
    r"\b(django|flask|fastapi|starlette|tornado|pyramid)\b",
    r"\b(pandas|numpy|scipy|matplotlib|seaborn|plotly)\b",
    r"\b(scikit-learn|sklearn|tensorflow|pytorch|keras|transformers)\b",
    r"\b(sqlalchemy|peewee|tortoise|pydantic|marshmallow)\b",
    r"\b(pytest|unittest|hypothesis|coverage|mypy|ruff)\b",
    r"\b(celery|dramatiq|rq|huey|arq)\b",
    r"\b(requests|httpx|aiohttp|beautifulsoup|scrapy)\b",
    # Go
    r"\b(gin|echo|fiber|chi|gorilla|mux)\b",
    r"\b(gorm|sqlx|ent|bun)\b",
    r"\b(cobra|viper|zap|logrus)\b",
    # Rust
    r"\b(tokio|async-std|actix|axum|rocket|warp)\b",
    r"\b(serde|diesel|sqlx|sea-orm)\b",
    r"\b(clap|structopt|tracing)\b",
    # Ruby
    r"\b(rails|sinatra|hanami|grape)\b",
    r"\b(activerecord|sequel|rom-rb)\b",
    # Java/Kotlin
    r"\b(spring|springboot|spring-boot|quarkus|micronaut)\b",
    r"\b(hibernate|jpa|mybatis|exposed)\b",
    # Databases
    r"\b(postgresql|postgres|mysql|sqlite|mongodb|redis)\b",
    r"\b(elasticsearch|opensearch|meilisearch|algolia)\b",
    # Infrastructure
    r"\b(docker|kubernetes|k8s|terraform|pulumi|ansible)\b",
    r"\b(aws|gcp|azure|cloudflare|vercel|netlify)\b",
    # General patterns
    r"\bhow\s+(?:do\s+I|to|does)\s+\w+\s+(?:work|use|implement)\b",
    r"\b(?:using|with)\s+(?:the\s+)?(\w+(?:\.\w+)?)\s+(?:library|framework|package|module)\b",
]

# Phrases that indicate documentation needs
DOC_PHRASES = [
    r"how do i",
    r"how to",
    r"how does",
    r"what is the",
    r"show me how",
    r"example of",
    r"documentation for",
    r"docs for",
    r"api for",
    r"guide for",
    r"tutorial",
    r"best practice",
    r"getting started",
    r"quickstart",
]


def detect_libraries(text: str) -> list[str]:
    """Detect library mentions in text."""
    text_lower = text.lower()
    detected = []

    for pattern in LIBRARY_PATTERNS:
        matches = re.findall(pattern, text_lower, re.IGNORECASE)
        detected.extend(matches)

    # Deduplicate while preserving order
    seen = set()
    unique = []
    for lib in detected:
        if lib not in seen:
            seen.add(lib)
            unique.append(lib)

    return unique


def needs_documentation(text: str) -> bool:
    """Check if the prompt likely needs documentation lookup."""
    text_lower = text.lower()

    for phrase in DOC_PHRASES:
        if re.search(phrase, text_lower):
            return True

    return False


def main():
    # Read the hook payload from stdin
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Not JSON, try raw text
        sys.stdin.seek(0)
        payload = {"prompt": sys.stdin.read()}

    # Extract the user prompt
    prompt = payload.get("prompt", payload.get("message", payload.get("content", "")))

    if not prompt:
        sys.exit(0)

    # Detect libraries
    libraries = detect_libraries(prompt)
    wants_docs = needs_documentation(prompt)

    # If libraries detected and seems to want documentation
    if libraries and wants_docs:
        lib_list = ", ".join(libraries[:3])  # Show up to 3
        reminder = f"""<system-reminder>
EXTERNAL LIBRARY DETECTED: {lib_list}

Use the **context7 skill** workflow for up-to-date documentation:

1. Resolve: `mcp__context7__resolve-library-id({{ libraryName: "{libraries[0]}" }})`
2. Get docs: `mcp__context7__get-library-docs({{ context7CompatibleLibraryID: "<id>", topic: "<specific topic>", tokens: 5000 }})`
3. Focus on top 5 most relevant chunks

This ensures accurate, current documentation instead of training data.
</system-reminder>"""
        print(reminder)
    elif libraries:
        # Libraries mentioned but not clearly asking for docs
        lib_list = ", ".join(libraries[:3])
        hint = f"""<system-reminder>
Libraries detected: {lib_list}. If documentation is needed, use context7 skill.
</system-reminder>"""
        print(hint)

    sys.exit(0)


if __name__ == "__main__":
    main()
