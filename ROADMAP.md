# Skill catalog roadmap

Suggested skills for this catalog, based on the workflows of the
[qualcomm-linux](https://github.com/qualcomm-linux) projects
([meta-qcom](https://github.com/qualcomm-linux/meta-qcom),
[meta-qcom-distro](https://github.com/qualcomm-linux/meta-qcom-distro),
[meta-qcom-3rdparty](https://github.com/qualcomm-linux/meta-qcom-3rdparty),
[qcom-deb-images](https://github.com/qualcomm-linux/qcom-deb-images) and the
[qcom-next kernel](https://github.com/qualcomm-linux/kernel/tree/qcom-next))
and the [Dragonwing documentation](https://dragonwingdocs.qualcomm.com).

Priorities: **P1** = highest value, grounded in well-understood workflows;
**P2** = valuable, needs a research/generalization pass; **P3** = nice to have.
Contributions for any entry are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## A. Build — Yocto (meta-qcom, meta-qcom-distro, meta-qcom-3rdparty)

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-yocto-build-image` | P1 | available | Build any supported image with `kas-container build ci/<machine>.yml[:ci/<distro>.yml][:ci/<kernel>.yml]`: machine list, distro overlays, kernel overlays, image targets, cache hygiene, `qcomflash` artifacts |
| `qcom-yocto-image-customize` | P2 | planned | Add packages/features to an image the right way: local.conf fragment vs bbappend vs custom image recipe; layer placement policy (meta-qcom vs -distro vs -3rdparty) |
| `qcom-yocto-new-machine` | P2 | available | Bring up a new board in meta-qcom or meta-qcom-3rdparty: machine .conf + SoC include, firmware-boot/CDT recipe, packagegroup, kas yml (modeled on the Arduino / Radxa board additions) |
| `qcom-yocto-build-troubleshoot` | P3 | planned | Triage common bitbake/kas failures: fetch/mirror errors, sstate issues, disk space, license/QA errors |

## B. Flash & deploy

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-flash-qdl` | P1 | available | Generic EDL/QDL flashing: detect `05c6:9008`, unpack the `qcomflash` artifact, run `qdl`, `--serial` for multiple boards, per-board EDL-mode notes |
| `qcom-boot-validate` | P1 | available | Serial-console boot validation: wait for `login:`, log in with the distro's default credentials, verify kernel/os-release/systemd state |
| `qcom-yocto-download-prebuilt` | P3 | available | Download prebuilt Qualcomm Linux (QLI) flashable images from the public CodeLinaro archive, per the Dragonwing flash guide |

## C. Debian/Ubuntu images (qcom-deb-images)

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-deb-build-image` | P2 | planned | Build a Debian image from qcom-deb-images (debos recipes / build scripts) for supported boards |
| `qcom-deb-flash-boot` | P2 | planned | Flash/boot the Debian image on a board following the qcom-deb-images documented flow |

## D. Kernel development (qualcomm-linux/kernel, qcom-next)

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-kernel-qcom-next-build` | P1 | available | Standalone cross-build of qcom-next: `defconfig` + `prune.config` + `qcom.config` fragment merge, Image/dtbs/modules |
| `qcom-kernel-test-on-device` | P2 | planned | Test a modified kernel on hardware via meta-qcom (SRCREV/AUTOREV override, devupstream) or by swapping Image/dtb, ending in a boot validation |
| `qcom-yocto-kernel-srcrev-bump` | P2 | planned | Bump `SRCREV`/tag/`LINUX_VERSION` in meta-qcom's `linux-qcom-next_git.bb` to the latest qcom-next tag with a changelog-style commit |
| `qcom-kernel-config-change` | P3 | planned | Enable/disable a kernel option in the right fragment (`qcom.config` vs `qcom_debug.config` vs recipe fragment) |

## E. On-device / runtime

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-device-info` | P1 | available | Print SoC/board/OS info from a booted target; doubles as the authoring template |
| `qcom-device-diagnostic` | P2 | planned | Read-only health snapshot: remoteproc/firmware state, thermal zones, failed systemd units, dmesg errors, storage/memory |
| `qcom-boot-debug` | P2 | planned | Triage a failed boot from a serial log: firmware stage vs kernel panic vs rootfs mount vs systemd failure |

## F. Maintainer workflows

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-yocto-update-base-lock` | P1 | available | Refresh the layer commit pins in meta-qcom's `ci/base.lock.yml` with a changelog-style commit |
| `qcom-yocto-pre-pr-checks` | P1 | available | Run meta-qcom's CI-parity checks (yocto-patchreview, yocto-check-layer, oe-selftest) before opening/updating a PR |
| `qcom-backport` | P3 | planned | Backport a commit from the development branch to an LTS branch with the `[Backport <branch>]` subject convention |
| `qcom-ci-triage` | P3 | planned | Investigate a failing GitHub Actions run in a qualcomm-linux repo and summarize the root cause |
| `qcom-lava-log` | P2 | available | Fetch and analyze LAVA test job logs, results, and definitions via the LAVA REST API |

## G. Skill catalog management

| Skill | Priority | Status | Scope |
|---|---|---|---|
| `qcom-skills-contribute` | P1 | available | Turn local edits to an installed skill from this catalog into a DCO-signed topic-branch commit and, on request, the upstream pull request |

## Out of scope

- Lab-specific automation (private board farms, site-specific power/EDL
  control) — keep those as thin local wrappers around the generic skills in
  this catalog.
- Vendor-tool workflows not part of the qualcomm-linux upstream projects.
