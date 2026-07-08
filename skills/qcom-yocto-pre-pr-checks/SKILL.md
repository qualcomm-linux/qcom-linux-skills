---
name: qcom-yocto-pre-pr-checks
description: >-
  Run meta-qcom's CI-parity checks locally before opening or updating a
  pull request: yocto-patchreview, yocto-check-layer and oe-selftest via
  the ci/ helper scripts, plus a commit-message review against the
  project's conventions. Use when asked to "run the pre-PR checks", "check
  if my meta-qcom branch is ready for a PR", "run patchreview /
  check-layer / oe-selftest", or "validate my layer changes like CI
  would". Do NOT use for building images (see qcom-yocto-build-image) or for
  hardware validation (see qcom-boot-validate).
---

# Run meta-qcom's CI checks before a PR

Runs the same checks meta-qcom's CI runs, locally and in the same
containerized environment, so a PR does not bounce on mechanical failures.
This encodes the workflow from meta-qcom's `AGENTS.md`.

## Prerequisites

- A meta-qcom checkout with your changes committed on a topic branch
  (based on `master`; the distro layer uses `main`).
- `kas-container` on PATH with a working Docker or Podman runtime.
- Shared cache dirs outside the repo — reuse `DL_DIR`/`SSTATE_DIR`/
  `KAS_WORK_DIR` from the environment if set, otherwise export them first
  (see the `qcom-yocto-build-image` skill, step 1).
- Do not use `sudo`, and do not create or modify user groups as part of
  this workflow.

## The checks

Run from the meta-qcom repo root, in this order:

### 1. yocto-patchreview — commit/patch hygiene (routine)

```bash
ci/kas-container-shell-helper.sh ci/yocto-patchreview.sh
```

Reviews the patches your branch adds (recipe patch metadata such as
`Upstream-Status`, malformed patches, commit issues). Fix everything it
flags; CI treats these as failures.

### 2. yocto-check-layer — layer compatibility (before opening/updating the PR)

```bash
ci/kas-container-shell-helper.sh ci/yocto-check-layer.sh
```

Verifies the layer still passes the Yocto Project compatibility checks
(signature stability, layer isolation, appends behavior). This is the
slowest check — run it once your branch is otherwise ready.

### 3. oe-selftest — layer selftests (routine)

```bash
ci/kas-container-shell-helper.sh ci/oe-selftest.sh
```

Auto-discovers the layer's tests under `lib/oeqa/selftest/cases/`. To run
a subset while iterating:

```bash
kas-container shell ci/base.yml \
  --command "/repo/ci/oe-selftest.sh /repo /work <case>.<TestClass>"
```

### 4. Commit message review

Check every commit on the branch against meta-qcom's `CONTRIBUTING.md`:

- atomic — exactly one logical change per commit, tree functional after
  each one; no fixup commits within the series;
- subject in `recipe-name: summary of the changes` form;
- body explains the problem first, then the imperative actions, in prose;
- `Signed-off-by` present and matching the author identity from
  `git config`; `Assisted-by: AGENT_NAME:MODEL_VERSION` when an AI
  assistant helped.

```bash
git log --format='%h %s%n%b' origin/master..
```

## Reporting

Summarize per check: PASS/FAIL, and for failures quote the failing
check's actual output (patchreview findings, failing selftest names, the
check-layer error) with the log path — do not paraphrase errors away. Fix
findings by amending the commit that introduced them (rebase -i), not by
appending fixup commits, then re-run the affected check.

## Notes

- Routine loop while developing: patchreview + oe-selftest; check-layer
  once before opening/updating the PR.
- The helpers keep CI parity by running inside kas-container; resist
  running the underlying scripts on the bare host even when it seems
  faster.
- meta-qcom-distro carries the same `ci/` helper scripts, so the same
  flow applies there (PRs target `main`).
- These checks do not build or boot an image; for changes with runtime
  impact, follow up with `qcom-yocto-build-image` and `qcom-boot-validate`.
