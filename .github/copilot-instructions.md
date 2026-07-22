# Copilot instructions for qcom-linux-skills

Repository layout, skill conventions, and validation commands are documented
in [AGENTS.md](../AGENTS.md) — follow them for any change in this repository.
The instructions below govern code review behavior only.

## Code review

### Comment discipline

- Review only the lines this pull request adds or modifies. Never comment
  on pre-existing code the PR does not change — even when it looks wrong,
  and even when it is visible as context around a changed line. If a
  change merely touches a line (e.g. re-pins a version) inside code with
  pre-existing issues, those issues are out of scope for this review.
- Only comment when you are highly confident that a concrete defect exists;
  when in doubt, stay silent.
- Every comment must name the defect and propose a specific fix, using a
  suggested-change block whenever possible.
- Keep each comment to one sentence of explanation plus the fix.
- Use direct, imperative wording ("Quote this expansion"), never hedging
  ("you might want to consider...").
- Do not post praise, restate what the change does, or leave observational
  comments.
- Do not suggest adding code comments or docstrings, renaming, or
  speculative refactors.

### Never duplicate CI

CI already enforces the following; do not comment on anything they cover:

- shellcheck on `install.sh` and all skill scripts, and Python compile
  checks (`.github/workflows/catalog-checks.yml`).
- Catalog conventions via `ci/check-catalog.py`: frontmatter key set, skill
  name matching its directory and the `qcom-*` naming groups, description
  limits, SPDX headers, `set -euo pipefail`, executable bits, and the
  cross-references between `skills/`, README.md, ROADMAP.md and
  `.claude-plugin/marketplace.json`.
- Agent Skills spec conformance (`skills-ref validate`) and marketplace
  schema validation (`claude plugin validate`).
- Semgrep, repolinter, dependency review, copyright/license and commit
  email checks (`.github/workflows/qcom-preflight-checks.yml`).

### What to review

Focus exclusively on what the checks above cannot catch:

- Bash logic errors beyond shellcheck's reach: unsafe variable expansions
  in destructive commands (`rm -rf "$VAR/..."`), missing error handling on
  steps whose failure must abort the flow, wrong test conditions.
- Commands, flags, or paths in SKILL.md instructions that are broken,
  internally inconsistent, or contradict the scripts they describe.
- Violations of the non-destructive convention: skills and scripts must
  stop before push and ask before destructive steps.
- Board, SoC, machine, image, or tool names that contradict the rest of
  the catalog or the referenced upstream projects.
- Secrets, tokens, credentials, or lab-internal hostnames and paths that
  must not enter the public catalog.
- Skill descriptions whose trigger phrases are misleading or overlap a
  sibling skill without a disambiguating "do NOT use for" clause.
