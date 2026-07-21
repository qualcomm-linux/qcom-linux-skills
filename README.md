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
| [qcom-yocto-download-prebuilt](skills/qcom-yocto-download-prebuilt/SKILL.md) | users | Download prebuilt Qualcomm Linux (QLI) flashable images from the public CodeLinaro archive |
| [qcom-flash-qdl](skills/qcom-flash-qdl/SKILL.md) | users | Flash a board in EDL mode with the QDL tool |
| [qcom-boot-validate](skills/qcom-boot-validate/SKILL.md) | users, developers | Validate that a board boots to a working login shell over the serial console |
| [qcom-kernel-qcom-next-build](skills/qcom-kernel-qcom-next-build/SKILL.md) | developers | Cross-build the qcom-next kernel standalone (defconfig + qcom.config fragments) |
| [qcom-yocto-pre-pr-checks](skills/qcom-yocto-pre-pr-checks/SKILL.md) | developers | Run meta-qcom's CI-parity checks (patchreview, check-layer, oe-selftest) before a PR |
| [qcom-lava-log](skills/qcom-lava-log/SKILL.md) | developers | Fetch and analyze LAVA test job logs, results, and definitions via the LAVA REST API |
| [qcom-yocto-update-base-lock](skills/qcom-yocto-update-base-lock/SKILL.md) | maintainers | Refresh the layer commit pins in meta-qcom's ci/base.lock.yml with a changelog-style commit |
| [qcom-skills-contribute](skills/qcom-skills-contribute/SKILL.md) | users, developers | Turn local edits to an installed skill from this catalog into a DCO-signed topic-branch commit and, on request, the upstream pull request |

More skills are planned — see [ROADMAP.md](ROADMAP.md).

## Branches

**main**: Primary development branch. Contributors should develop submissions based on this branch, and submit pull requests to this branch.

## Installation Instructions

There are three install routes; pick by whether you may end up improving
the skills or only consuming them.

### Clone + install.sh (recommended — any agent, contribution-ready)

Run the installer to symlink skills into the skill directories of the
agents you use (defaults to Claude Code, Codex and Cursor):

```bash
./install.sh                        # all skills, all default targets
./install.sh --targets claude       # only ~/.claude/skills
./install.sh --skills qcom-flash-qdl,qcom-boot-validate    # just a subset
./install.sh --list                 # list the available skills
./install.sh --copy                 # copy instead of symlink
./install.sh --targets project --project ~/src/meta-qcom   # project-local
```

The symlink default is deliberate: installed skills point back into this
clone, so when you (or your agent) improve a skill the edit lands on a
branchable git work tree, and the
[qcom-skills-contribute](skills/qcom-skills-contribute/SKILL.md) skill can
turn it into an upstream pull request. Prefer symlinks over `--copy` —
copies drift silently from the catalog.

### Claude Code plugin marketplace (consume-only)

```text
/plugin marketplace add qualcomm-linux/qcom-linux-skills
/plugin install qcom-flash-qdl@qcom-linux-skills
```

Each skill is its own plugin, so you install exactly what you need and
pick up updates with `/plugin marketplace update qcom-linux-skills`.
Marketplace installs are read-only copies in Claude Code's plugin cache
(skills appear namespaced under the plugin name); to propose changes,
use the clone route above. Claude Code only.

### npx skills (consume-only, many agents)

```bash
npx skills add qualcomm-linux/qcom-linux-skills --skill qcom-flash-qdl
```

The community [skills CLI](https://github.com/vercel-labs/skills)
installs single skills from this repository's standard layout for many
agents, including Claude Code, Codex and Cursor. Installs are detached
copies tracked by its own lockfile; as with the marketplace route,
propose changes via the clone route above.

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
  (`qcom-flash-qdl`, `qcom-boot-validate`, `qcom-device-info`), and
  `qcom-skills-*` for skills that manage this catalog itself
  (`qcom-skills-contribute`).
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
