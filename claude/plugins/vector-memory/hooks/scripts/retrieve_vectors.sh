#!/usr/bin/env bash
# PreToolUse: pull relevant prior-session context back out of qdrant.
exec claude-vector retrieve --json
