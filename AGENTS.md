# Agent Guide for qcom-linux-skills

This file guides automation agents to make changes here the way reviewers
and CI expect:

- model new or changed skills on the documented
  [skill layout and conventions](README.md#skill-layout-and-conventions),
- validate changes with `shellcheck`, PEP 8, and `./install.sh` before
  opening/updating a PR,
- follow the commit and pull-request conventions below.

## Project Overview

qcom-linux-skills is a catalog of Agent Skill (`SKILL.md`) files for
[Qualcomm Linux](https://github.com/qualcomm-linux), usable with any agent
that understands the format (Claude Code, Codex, Cursor, ...). The skills
drive workflows in external repositories — building images with
[meta-qcom](https://github.com/qualcomm-linux/meta-qcom) and
[meta-qcom-distro](https://github.com/qualcomm-linux/meta-qcom-distro),
flashing and validating boards, and working on the
[qcom-next kernel](https://github.com/qualcomm-linux/kernel/tree/qcom-next).
This repository itself has no build system or test harness: it is markdown,
a few helper scripts, and the `install.sh` installer, licensed BSD-3-Clause.

## 1) Repository layout

One directory per skill under `skills/`, where the directory name equals the
skill `name`:

```text
skills/<skill-name>/
├── SKILL.md          # the skill: YAML frontmatter + markdown instructions
├── scripts/          # optional helper scripts the skill invokes
└── references/       # optional deep-dive docs the skill points to
```

Other files an agent should know about:

- `install.sh` — symlinks or copies skills into agent skill directories
  (`--targets claude,codex,cursor,project`, `--skills` for a subset,
  `--list` to enumerate); idempotent and self-verifying.
- `.claude-plugin/marketplace.json` — Claude Code plugin marketplace
  manifest exposing each skill as an individually installable plugin.
- `README.md` — the "Available skills" table and the authoritative
  [skill layout and conventions](README.md#skill-layout-and-conventions).
- `ROADMAP.md` — planned skills with their intended names and scope.
- `CONTRIBUTING.md` — contribution workflow, style, commit conventions.

## 2) Skill authoring conventions

Model new skills on the minimal example
[skills/qcom-device-info/SKILL.md](skills/qcom-device-info/SKILL.md) and the
README conventions. In summary:

- Frontmatter has exactly two keys: `name` (matches the directory) and a
  folded `description` that states what the skill does, quotes the trigger
  phrases users would say, and names what the skill must NOT be used for
  (cross-referencing the sibling skill that covers that case).
- Skill names state the project/distro they drive: `qcom-yocto-*` for
  meta-qcom (Yocto) workflows, `qcom-deb-*` (planned) for qcom-deb-images,
  kernel skills name the tree/branch they build
  (e.g. `qcom-kernel-qcom-next-build`), plain `qcom-*` is reserved for
  distro-agnostic board and device skills, and `qcom-skills-*` for skills
  that manage this catalog itself.
- Script paths inside a SKILL.md are relative to the skill's directory.
- Helper scripts carry the Qualcomm copyright and SPDX BSD-3-Clause header,
  a shebang, and `set -euo pipefail` (bash, `shellcheck`-clean) or
  [PEP 8](https://peps.python.org/pep-0008/) style (python).
- Skills are non-destructive by default: they stop before push, ask before
  destructive steps, and clearly report PASS/FAIL outcomes.

When adding a skill, also add it to the "Available skills" table in
[README.md](README.md), add its plugin entry to
`.claude-plugin/marketplace.json`, and reconcile [ROADMAP.md](ROADMAP.md):
mark the matching entry available, or add it under the fitting group.

## 3) Validate before opening/updating a PR

There is no committed test harness; these checks are cheap enough to run
over the whole catalog:

```sh
shellcheck install.sh skills/*/scripts/*.sh
python3 -m py_compile skills/*/scripts/*.py
./install.sh --targets project --project "$(mktemp -d)"
./install.sh --targets project --project "$(mktemp -d)" --skills <one-skill>
claude plugin validate .   # or: python3 -m json.tool .claude-plugin/marketplace.json
```

`install.sh` verifies that every selected skill's `SKILL.md` is visible
after the install and prints `[err]` lines on failure.

Beyond that, test the skill itself: run its scripts, and exercise the
documented procedure end-to-end where hardware or a checkout of the target
repository allows.

Pull request CI (`.github/workflows/qcom-preflight-checks.yml`) runs the
Qualcomm preflight checks: Semgrep scan, dependency review, repolinter,
copyright/license check, and commit-email check.

## 4) Pull request / contribution workflow

Follow the contribution workflow documented in
[CONTRIBUTING.md](CONTRIBUTING.md):

1. Target branch: **main**.
2. Fork `qualcomm-linux/qcom-linux-skills`, create a topic branch off
   `main`, implement changes.
3. Rebase on latest upstream `main` (`git pull --rebase upstream main`).
4. Open a GitHub pull request.
5. Use PR discussion for review iteration.

## 5) Commit message best practices (project style)

Follow the commit message requirements documented in
[CONTRIBUTING.md](CONTRIBUTING.md#commit-messages) (the same conventions as
meta-qcom): an atomic change per commit, a `component: summary of the
changes` subject where the component is the skill or file being touched
(e.g. `skills/qcom-flash-qdl: document EDL cable setup`), a plain-English
body that explains the problem before the imperative actions, and the
mandatory `Signed-off-by` trailer. When an AI coding assistant helped,
acknowledge it with an `Assisted-by: AGENT_NAME:MODEL_VERSION` trailer,
placed before the `Signed-off-by` line.

When committing programmatically, take the `Signed-off-by` identity from the
local git configuration and append the trailers explicitly, in this order:

```text
Assisted-by: AGENT_NAME:MODEL_VERSION
Signed-off-by: $(git config user.name) <$(git config user.email)>
```

Never fabricate a name or email; always read them from `git config`.

Fixups within the same patch series are not allowed; changes should be
corrected in the patch where they are introduced.
