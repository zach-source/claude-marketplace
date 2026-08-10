#!/usr/bin/env bash
# PreCompact: vectorize the transcript into qdrant before it is compacted away.
#
# stdout discarded, deliberately. This is a side-effect hook - it has nothing to
# say to the harness - but it used to `exec` the CLI, piping whatever that printed
# straight into the PreCompact result, which is parsed as JSON. Today that's a
# harmless status dict ({"status":"success","vectorized":N,...}), but `continue:
# false` from PreCompact halts compaction outright, so a third-party CLI's stdout
# was one unlucky key away from being able to stop a compact.
claude-vector precompact --json >/dev/null 2>&1
exit 0
