#!/usr/bin/env bash
# Reproduces the spike-folder-collision experiment from README §E.
# Outputs: each scenario's git pull behaviour.
# Usage: bash _research/git-folder-collision.sh
set -euo pipefail

ROOT=${TMPDIR:-/tmp}/git-spike-test
rm -rf "$ROOT" && mkdir -p "$ROOT"

cd "$ROOT"
git init -q --bare remote
git init -q seed && cd seed
git config user.email seed@test.local && git config user.name Seed
git checkout -b main >/dev/null 2>&1
mkdir -p spikes/alice-spike
echo "alice spike v1" > spikes/alice-spike/notes.md
echo "shared init" > shared.md
git add -A && git commit -q -m "init"
git remote add origin "$ROOT/remote"
git push -q -u origin main
cd "$ROOT"
git -C remote symbolic-ref HEAD refs/heads/main

run_scenario() {
  local label="$1"
  echo "=== $label ==="
  rm -rf alice bob
  git clone -q remote alice && (cd alice && git config user.email alice@test.local && git config user.name Alice)
  git clone -q remote bob   && (cd bob   && git config user.email bob@test.local   && git config user.name Bob)
  (cd bob && git rm -rq spikes/alice-spike && git commit -q -m "bob: delete alice-spike" && git push -q origin main)
  cd alice
}

# A — modified tracked + untracked
run_scenario "A: modified tracked + untracked"
echo "alice WIP 1" > spikes/alice-spike/wip1.txt
echo "edit" >> spikes/alice-spike/notes.md
git pull 2>&1 | sed 's/^/  /'; echo "--- status: $(git status --short | tr '\n' ' ')"; cd "$ROOT"

# B — untracked only
run_scenario "B: untracked only"
echo "alice WIP 1" > spikes/alice-spike/wip1.txt
git pull 2>&1 | sed 's/^/  /'; echo "--- after: $(ls spikes/alice-spike/ 2>&1)"; cd "$ROOT"

# C — staged uncommitted
run_scenario "C: staged uncommitted new file"
echo "alice WIP 1" > spikes/alice-spike/wip1.txt
git add spikes/alice-spike/wip1.txt
git pull 2>&1 | sed 's/^/  /'; echo "--- status: $(git status --short | tr '\n' ' ')"; cd "$ROOT"

# D — git clean -fd is the only danger
run_scenario "D: git clean -fd obliterates untracked"
echo "alice WIP 1" > spikes/alice-spike/wip1.txt
git pull -q 2>&1
git clean -fd 2>&1 | sed 's/^/  /'
echo "--- after clean: $(find spikes -type f 2>&1 || echo '(no spikes/)')"
