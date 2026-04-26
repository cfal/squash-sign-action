# squash-sign-action

Force-replaces a pull-request branch with a Verified commit derived from the PR's diff vs base. A hacky shortcut to signed commits — no GPG, no local signing setup, no GitHub App.

You drop a transient workflow file onto your PR branch and push. The action squashes the PR diff onto base, removes the workflow file from the result, and pushes the squash via [`cfal/push-signed-commits`](https://github.com/cfal/push-signed-commits) using GitHub's `createCommitOnBranch` GraphQL mutation. When invoked with the workflow's `GITHUB_TOKEN`, GitHub attributes the commit to `github-actions[bot]` and marks it Verified.

The result is one Verified commit on top of base — or, if the diff exceeds GitHub's 45MB GraphQL payload limit, several Verified commits split at ~40MB chunks.

## Quick start

Drop this at `.github/workflows/sign.yml` on your PR branch:

```yaml
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
```

Push. The PR ends up as `base + signed commit(s)`, with `sign.yml` gone from the branch. To re-sign later, add the file back in a new push.

## Inputs

| Input | Description | Default |
|---|---|---|
| `github-token` | Token to push with. Default produces commits attributed to `github-actions[bot]` and marked Verified. | `${{ github.token }}` |
| `workflow-path` | Path of the self-destructing workflow file to drop from the squash. | Auto-detected from `github.workflow_ref`. |
| `commit-title` | Title for the squashed commit. | `${{ github.event.pull_request.title }}` |

## Requirements

- Same-repo PRs only. `GITHUB_TOKEN` cannot push to forks.
- The workflow file must not exist on the base branch (it's meant to be transient).
- Repo settings must allow `GITHUB_TOKEN` to have `contents: write` (Settings → Actions → General → Workflow permissions).

## Trade-offs

- **PR review continuity is broken on every run.** Inline review comments anchor to commit OIDs; force-replacing the branch detaches them.
- **Authorship is collapsed.** All output commits are authored by `github-actions[bot]`. Original committers are preserved as `Co-authored-by:` trailers.
- **Failure window.** If the signed-push step fails, the PR branch sits at base until you re-push from your laptop.
- **Large diffs split.** Past ~40MB the squash is chunked into multiple Verified commits.

## How the signing works

`createCommitOnBranch`, when called with a GitHub App installation token, marks the resulting commit as Verified. The default `GITHUB_TOKEN` is itself an installation token (for the GitHub Actions app), so no custom App setup is needed.
