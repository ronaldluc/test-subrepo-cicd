#!/usr/bin/env bash
# Fails if any directory contains CLAUDE.md without a sibling AGENTS.md → CLAUDE.md symlink.
set -euo pipefail

missing=0
while IFS= read -r -d '' claude; do
  dir="$(dirname "$claude")"
  agents="$dir/AGENTS.md"
  if [ ! -L "$agents" ]; then
    echo "missing AGENTS.md symlink in $dir" >&2
    missing=1
    continue
  fi
  target="$(readlink "$agents")"
  if [ "$target" != "CLAUDE.md" ]; then
    echo "AGENTS.md in $dir points to '$target', expected 'CLAUDE.md'" >&2
    missing=1
  fi
done < <(find . -name CLAUDE.md -not -path "./.git/*" -print0)

exit "$missing"
