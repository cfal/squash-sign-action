#!/usr/bin/env bash
# Prepare a PR branch for squash-sign-action.
#
# Removes all existing workflow files and writes a transient sign.yml that
# uses reset-workflows: 'true', so the deleted workflows come back in the
# squashed signed commit. The point: during the brief window between this
# initial push and the action's force-push, no workflows fire except sign.yml.
#
# Run from the root of your working copy on the branch you intend to push.
# Refuses to run if there are uncommitted tracked changes.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree has uncommitted tracked changes. Commit or stash first." >&2
  exit 1
fi

if [ -d .github/workflows ] && [ -n "$(ls -A .github/workflows)" ]; then
  git rm -rf .github/workflows >/dev/null
fi

mkdir -p .github/workflows
cat > .github/workflows/sign.yml <<'YAML'
name: Squash and sign

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - '.github/workflows/sign.yml'

permissions:
  contents: write

jobs:
  sign:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - uses: cfal/squash-sign-action@main
        with:
          reset-workflows: 'true'
YAML

git add .github/workflows/sign.yml
git commit -m "trigger squash-sign-action"

echo "Done. Push this branch; squash-sign-action will sign and restore workflows."
