---
name: qcom-yocto-update-base-lock
description: >-
  Refresh the upstream layer commit pins in meta-qcom's ci/base.lock.yml to the
  latest commit on each layer's branch and produce a changelog-style commit (one
  "Relevant changes for <layer>:" section per bumped layer), like commit
  ddbe6a6a "ci: base.lock: update layers to latest". Use when asked to "update
  base.lock to latest", "bump the layer hashes/revisions", "update the layers to
  latest", or "refresh ci/base.lock.yml" in the meta-qcom repo. git-only (no
  kas); touches only repos already pinned in the lock; commits on a branch and
  stops before push.
---

# Update ci/base.lock.yml layer pins to latest

## What this does

`ci/base.lock.yml` pins every external layer meta-qcom depends on to an exact
upstream commit. This skill bumps those pins to the latest commit on each
layer's branch and writes a changelog-style commit, reproducing the format of
commit `ddbe6a6a` (`ci: base.lock: update layers to latest`).

The helper script lives in this skill's directory; the commands below write
`<skill-dir>` for it (e.g. `~/.claude/skills/qcom-yocto-update-base-lock` when installed
via `install.sh`).

## Ground rules (do not violate)

- **git-only.** Do not use `kas`. Every repo is known from the lock; resolving
  with `git` is faster and avoids `kas dump --lock` re-deriving the repo set.
- **Only touch existing lock entries.** The lock set is hand-curated:
  `meta-qcom-distro` is intentionally left floating (not pinned) and `meta-dpdk`
  (defined only in `ci/dpdk.yml`) is intentionally pinned. Never add or remove a
  repo - only update `commit:` values of repos already in the lock.
- **Commit, then stop.** Create a branch and commit; do not push or open a PR.

## Procedure

Run everything from the **meta-qcom repo root**.

### 1. Sanity check the starting state

```bash
git status --short        # expect a clean tree
git rev-parse --abbrev-ref HEAD
```

If the tree is dirty, ask the user before continuing.

### 2. Dry run - resolve latest and preview the message

```bash
bash <skill-dir>/scripts/bump-base-lock.sh --dry-run
```

This fetches each pinned layer's branch into a reusable bare-clone cache
(`~/.cache/meta-qcom-base-lock/`), prints `old -> new` per layer with a commit
count, and prints the proposed commit message. It writes **nothing** to the
lock. Review the output:

- The changed layers and their commit counts look plausible.
- Each section's first line equals the new pin (newest commit first).
- Any `WARN:` line (e.g. a layer whose old pin was not found upstream because of
  a force-push) - if present, expect to fix that layer's changelog by hand.

If no layer changed, the script says so and there is nothing to do - report that
and stop.

### 3. Apply the update

```bash
bash <skill-dir>/scripts/bump-base-lock.sh
```

This rewrites `ci/base.lock.yml` in place (swapping old SHAs for new) and writes
the commit message to `~/.cache/meta-qcom-base-lock/commit-message.txt`.

### 4. Review

```bash
git --no-pager diff ci/base.lock.yml
cat ~/.cache/meta-qcom-base-lock/commit-message.txt
```

Confirm only `commit:` lines changed (no repos added/removed) and the message
matches the model format: title `ci: base.lock: update layers to latest`, one
`Relevant changes for <layer>:` block per changed layer (in lock order, each
line `- <short-hash> <subject>`), then a `Signed-off-by:` trailer. Tidy any
omitted/odd changelog by hand if a WARN appeared.

### 5. Branch + commit (stop before push)

```bash
git switch -c "bump-base-lock-$(date +%Y%m%d)"
git add ci/base.lock.yml
git commit -F ~/.cache/meta-qcom-base-lock/commit-message.txt
```

If an AI agent is driving this skill, append an
`Assisted-by: AGENT_NAME:MODEL_VERSION` trailer to the message before
committing, per meta-qcom's CONTRIBUTING.md.

Then **stop**. Report the branch name and the per-layer summary, and remind the
user to push and open the PR themselves (do not push).

## Notes

- URL and branch for each layer are read from `ci/*.yml`
  (`base.yml`, `qcom-distro.yml`, `meta-arm.yml`, `dpdk.yml`; default branch
  `master`, with `meta-ai`/`meta-qcom-distro` on `main`). The script derives
  these dynamically, so new layers or branch changes are picked up automatically
  as long as the repo is present in the lock.
- The bare-clone cache persists between runs, so repeat runs are fast (the
  first run clones all layers and may take a few minutes).
- `warning: filtering not recognized by server, ignoring` is benign: some
  servers (e.g. `git.yoctoproject.org`) don't support partial clone, so those
  layers full-clone instead. It is not an error.
- `Signed-off-by:` is taken from `git config user.name`/`user.email` in the
  repo. Verify it is the identity you want before committing.
