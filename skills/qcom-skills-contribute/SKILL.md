---
name: qcom-skills-contribute
description: >-
  Turn local edits to an installed qcom-linux-skills skill into an
  upstream contribution: find the catalog clone behind the installed
  skill, validate the change, create a topic branch with a DCO-signed
  meta-qcom-style commit, and prepare (optionally open) the pull
  request. Use when asked to "upstream my skill changes", "propose this
  skill change back", "send my skill fix as a PR", or "contribute this
  skill improvement to the catalog". Only for changes to skills from
  this catalog; do NOT use for pull requests to meta-qcom or other
  target repositories (prepare those with qcom-yocto-pre-pr-checks).
metadata:
  version: "0.1"
---

# qcom-skills-contribute

Packages local modifications to an installed `qcom-linux-skills` skill
into a DCO-signed commit on a topic branch, following the catalog's
[CONTRIBUTING.md](../../CONTRIBUTING.md) conventions, and stops before
push unless explicitly asked to open the pull request.

This works because the default install is a symlink: an installed skill
under `~/.claude/skills/`, `~/.codex/skills/` or `~/.cursor/skills/`
points back into the git clone, so editing the installed skill *is*
editing a branchable work tree. Copy installs are handled by a fallback
that clones upstream into a temporary directory and transplants the
modified skill.

## When to use

- After improving an installed skill locally (fixing a step, adding a
  board or machine, clarifying instructions) and the change is worth
  sharing upstream.
- To convert an agent-authored skill fix into a well-formed PR without
  hand-running the fork/branch/sign-off mechanics.

## Prerequisites

- `git` with `user.name` and `user.email` configured (used verbatim for
  the `Signed-off-by` trailer — never fabricate an identity).
- `gh` (GitHub CLI), authenticated, only for the optional `--pr` step.
- The modified skill installed via symlink (preferred), via copy, or a
  local clone passed with `--repo-dir`.

## Instructions

1. **Identify** the modified skill and review the diff before doing
   anything else. For a symlink install:

   ```bash
   clone="$(dirname "$(dirname "$(readlink -f ~/.claude/skills/<skill-name>)")")"
   git -C "$clone" status --porcelain -- skills/<skill-name>
   git -C "$clone" diff -- skills/<skill-name>
   ```

   Summarize the change to the user and confirm it is intended for
   upstream (local site-specific tweaks, credentials, or lab paths must
   never be upstreamed).

2. **Write the commit body** to a temporary file: plain-English prose
   wrapped at ~72 columns that first explains the problem (why the
   change is needed), then the imperative actions taken. Do not restate
   the diff.

3. **Run the helper** from this skill's directory (paths are relative
   to the skill):

   ```bash
   scripts/contribute.sh <skill-name> \
     --summary "one-line summary for the subject" \
     --body-file /tmp/commit-body.txt \
     --assisted-by "AGENT_NAME:MODEL_VERSION"
   ```

   The script locates the clone, shows the changes, runs the catalog
   checks (shellcheck, python compile, `install.sh` self-verification),
   creates a `contribute/<skill-name>` topic branch, and makes the
   DCO-signed commit with the trailers in the required order. It stops
   before push.

4. **Verify** the commit it reports: subject `skills/<name>: summary`,
   why-first body, `Assisted-by:` before `Signed-off-by:`, and only the
   intended files staged.

5. **Ask the user** before publishing anything. Only with their
   explicit go-ahead, rerun with `--pr` (add `--yes` when running
   without a tty) to fork, push the branch, and open the pull request
   against `main`.

## Output format

Report to the user:

```text
Skill:   <skill-name>
Clone:   <path to the catalog clone>   (symlink | copy-fallback)
Checks:  PASS | FAIL (<which check failed>)
Commit:  <abbrev-sha> skills/<name>: <summary>  on branch <branch>
PR:      not pushed (stopped before push) | <pull request URL>
```

## Error handling

- **No changes found**: the script fails with "nothing to contribute" —
  confirm the right skill name and that the edit landed in the
  installed location.
- **Checks fail**: fix the reported shellcheck/python/install issues
  and rerun; only use `--skip-checks` when explicitly asked to.
- **Copy install**: the fallback clones upstream and transplants the
  skill; the resulting diff can include upstream drift — re-review the
  diff (step 1) inside the temporary clone before committing.
- **Changes outside the skill**: the script warns and excludes them;
  contribute them separately (one logical change per commit).

## Notes

- Non-destructive by default: nothing is pushed and no PR is opened
  without `--pr`, and `--pr` asks for confirmation.
- One skill, one commit, one PR — matching the catalog's atomic-commit
  convention. For changes spanning several skills, run once per skill.
- The `Signed-off-by` identity always comes from `git config`; the DCO
  sign-off is the user's attestation, which is why step 5 requires
  their explicit approval.
