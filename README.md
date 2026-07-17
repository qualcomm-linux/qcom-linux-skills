# qcom-linux-skills

Catalog of Agent Skill files for [Qualcomm Linux](https://github.com/qualcomm-linux),
usable with any agent that understands the `SKILL.md` format (Claude Code,
Codex, Cursor, ...). The skills cover the common user and developer workflows
around the qualcomm-linux projects — building images with
[meta-qcom](https://github.com/qualcomm-linux/meta-qcom) /
[meta-qcom-distro](https://github.com/qualcomm-linux/meta-qcom-distro),
flashing and validating boards, and working on the
[qcom-next kernel](https://github.com/qualcomm-linux/kernel/tree/qcom-next).

See the [Qualcomm Dragonwing documentation](https://dragonwingdocs.qualcomm.com)
for the product documentation these workflows are based on.

## Available skills

| Skill | Audience | What it does |
|---|---|---|
| [qcom-device-info](skills/qcom-device-info/SKILL.md) | users | Print SoC/board/OS info from a booted Qualcomm Linux target (example skill / authoring template) |
| [qcom-yocto-build-image](skills/qcom-yocto-build-image/SKILL.md) | users, developers | Build Qualcomm Linux images from meta-qcom with kas-container |
| [qcom-deb-build-image](skills/qcom-deb-build-image/SKILL.md) | users, developers | Build a Qualcomm Linux Debian (trixie) image from qcom-deb-images with debos |
| [qcom-deb-flash-boot](skills/qcom-deb-flash-boot/SKILL.md) | users | Flash a Qualcomm Linux Debian image over EDL/QDL, write an SD card, or boot it under QEMU |
| [qcom-yocto-download-prebuilt](skills/qcom-yocto-download-prebuilt/SKILL.md) | users | Download prebuilt Qualcomm Linux (QLI) flashable images from the public CodeLinaro archive |
| [qcom-flash-qdl](skills/qcom-flash-qdl/SKILL.md) | users | Flash a board in EDL mode with the QDL tool |
| [qcom-boot-validate](skills/qcom-boot-validate/SKILL.md) | users, developers | Validate that a board boots to a working login shell over the serial console |
| [qcom-kernel-qcom-next-build](skills/qcom-kernel-qcom-next-build/SKILL.md) | developers | Cross-build the qcom-next kernel standalone (defconfig + qcom.config fragments) |
| [qcom-yocto-pre-pr-checks](skills/qcom-yocto-pre-pr-checks/SKILL.md) | developers | Run meta-qcom's CI-parity checks (patchreview, check-layer, oe-selftest) before a PR |
| [qcom-yocto-update-base-lock](skills/qcom-yocto-update-base-lock/SKILL.md) | maintainers | Refresh the layer commit pins in meta-qcom's ci/base.lock.yml with a changelog-style commit |

More skills are planned — see [ROADMAP.md](ROADMAP.md).

## Branches

**main**: Primary development branch. Contributors should develop submissions based on this branch, and submit pull requests to this branch.

## Installation Instructions

Run the installer to symlink every skill into the skill directories of the
agents you use (defaults to Claude Code, Codex and Cursor):

```bash
./install.sh                        # all default targets
./install.sh --targets claude      # only ~/.claude/skills
./install.sh --copy                # copy instead of symlink
./install.sh --targets project --project ~/src/meta-qcom   # project-local
```

Alternatively, copy the directories under `skills/` into your favorite agent
skills directory by hand.

## Usage

Use your favorite agent to call one of the named skills from this project, or
just describe the task — the skill descriptions carry the trigger phrases
agents use for discovery (e.g. "build an image for the RB3 Gen2", "flash the
board over EDL", "update base.lock to latest").

## Skill layout and conventions

One directory per skill under `skills/`, where the directory name equals the
skill name:

```text
skills/<skill-name>/
├── SKILL.md          # the skill: YAML frontmatter + markdown instructions
├── scripts/          # optional helper scripts the skill invokes
└── references/       # optional deep-dive docs the skill points to
```

Conventions (see [skills/qcom-device-info](skills/qcom-device-info/SKILL.md)
for a minimal example):

- Skill names state the project/distro they drive so workflows are not
  confused across distros: `qcom-yocto-*` for meta-qcom (Yocto) workflows,
  `qcom-deb-*` (planned) for qcom-deb-images, and kernel skills name the
  tree/branch they build (e.g. `qcom-kernel-qcom-next-build`). Plain
  `qcom-*` names are reserved for distro-agnostic board and device skills
  (`qcom-flash-qdl`, `qcom-boot-validate`, `qcom-device-info`).
- Frontmatter has two keys: `name` (matches the directory) and a folded
  `description` that states what the skill does, quotes the trigger phrases
  users would say, and names what the skill must NOT be used for.
- Script paths inside a SKILL.md are relative to the skill's directory.
- Helper scripts carry an SPDX BSD-3-Clause header, a shebang, and
  `set -euo pipefail` (bash) or equivalent strictness (python).
- Skills are non-destructive by default: they stop before push, ask before
  destructive steps, and clearly report PASS/FAIL outcomes.

## Development

See [CONTRIBUTING.md file](CONTRIBUTING.md).

## Getting in Contact

* [Report an Issue on GitHub](../../issues)
* [Open a Discussion on GitHub](../../discussions)

## License

*qcom-linux-skills* is licensed under the [BSD-3-clause License](https://spdx.org/licenses/BSD-3-Clause.html). See [LICENSE.txt](LICENSE.txt) for the full license text.
