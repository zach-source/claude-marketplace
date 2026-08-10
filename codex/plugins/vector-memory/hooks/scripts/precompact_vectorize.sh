#!/usr/bin/env bash
# PreCompact: vectorize the transcript into qdrant before it is compacted away.
exec claude-vector precompact --json
