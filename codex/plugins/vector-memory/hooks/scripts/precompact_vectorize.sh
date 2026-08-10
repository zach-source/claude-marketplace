#!/usr/bin/env bash
# PreCompact: vectorize the transcript into qdrant before it is compacted away.
#
# This is a side-effect hook - there is nothing useful to tell the model. Its
# output must not reach stdout: claude-vector prints its result there, and
# PreCompact stdout is parsed as the hook's JSON result, where an unrecognised
# object is at best ignored and at worst a parse error. `continue:false` from a
# PreCompact hook would halt compaction outright.
claude-vector precompact --json >/dev/null 2>&1 || true
exit 0
