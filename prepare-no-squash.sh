#!/usr/bin/env bash
# Prepare a PR branch for squash-sign-action's per-commit (non-squash) mode.
#
# Like prepare.sh, but the embedded sign.yml does two extra things:
#   1. Disables every other repo workflow currently in the "active" state
#      before the signing run, so the per-commit createCommitOnBranch loop
#      does not trigger N rounds of CI re-runs.
#   2. Re-enables the same set after signing, regardless of success/failure.
#
# Cross-PR caveat: while sign.yml is running (~tens of seconds), other open
# PRs in the repo also see no CI. Skip this script in repos where that matters.
#
# Refuses to run if there are uncommitted tracked changes.

set -euo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

# Always operate from the repo root so .github/workflows lands in the right place.
# Captured into a var first so a failed rev-parse trips set -e instead of falling
# through to a no-op `cd ""`.
toplevel=$(git rev-parse --show-toplevel)
cd "$toplevel"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree has uncommitted tracked changes. Commit or stash first." >&2
  exit 1
fi

if [ -d .github/workflows ] && [ -n "$(ls -A .github/workflows)" ]; then
  git rm -rf .github/workflows >/dev/null
fi

mkdir -p .github/workflows
cat > .github/workflows/sign.yml <<'YAML'
name: Squash and sign (per-commit)

on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - '.github/workflows/sign.yml'

permissions:
  contents: write
  actions: write

jobs:
  sign:
    if: github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - name: Disable other workflows for this signing run
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          # Only currently-active *user-defined* workflows other than this one.
          # System workflows like pages-build-deployment and dependabot-updates have
          # paths outside .github/workflows/ and can't be disabled (the API returns 422).
          gh workflow list --all --repo "${{ github.repository }}" --json id,state,path \
            | jq -r '.[]
                | select(
                    .state == "active"
                    and (.path | startswith(".github/workflows/"))
                    and .path != ".github/workflows/sign.yml"
                  )
                | .id' \
            > /tmp/squash-sign-disabled-ids
          while read -r id; do
            [ -z "$id" ] && continue
            echo "Disabling $id"
            gh api -X PUT "/repos/${{ github.repository }}/actions/workflows/$id/disable"
          done < /tmp/squash-sign-disabled-ids

      - uses: cfal/squash-sign-action@main
        with:
          squash: 'false'
          reset-workflows: 'true'

      - name: Re-enable workflows
        if: always()
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          if [ ! -f /tmp/squash-sign-disabled-ids ]; then
            exit 0
          fi
          while read -r id; do
            [ -z "$id" ] && continue
            gh api -X PUT "/repos/${{ github.repository }}/actions/workflows/$id/enable" || true
          done < /tmp/squash-sign-disabled-ids
YAML

git add .github/workflows/sign.yml
git commit -m "trigger squash-sign-action (per-commit)"

echo "Done. Push this branch; squash-sign-action will sign each commit individually."
