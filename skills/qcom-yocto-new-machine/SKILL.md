---
name: qcom-yocto-new-machine
description: >-
  Bring up a new machine (board) in a Yocto BSP layer for a Qualcomm
  platform: conf/machine/<machine>.conf modeled on an existing board, the
  matching ci/<machine>.yml, a new conf/machine/include/qcom-<soc>.inc when
  the SoC has none yet, and — for third-party boards in meta-qcom-3rdparty —
  the firmware-boot/packagegroup/u-boot recipes a new board needs, modeled
  on the uno-q and radxa-dragon-q6a additions. Use when asked to "add a new
  machine/board to meta-qcom", "bring up <board> in meta-qcom-3rdparty",
  "create a machine conf for <SoC>", or "add CI yml for a new board". Do NOT
  use for building images (see qcom-yocto-build-image), flashing/validating
  hardware (see qcom-flash-qdl, qcom-boot-validate), or running pre-PR
  checks on an already-written change (see qcom-yocto-pre-pr-checks).
---

# Bring up a new machine in a Qualcomm Yocto BSP layer

Adds a new board to a Qualcomm BSP layer by reusing the structure of an
existing, similar machine rather than writing one from scratch. Machine
confs in these layers are short and mostly reference a shared per-SoC
include; the work is picking the right template and filling in
board-specific facts, not inventing new patterns.

## 1. Pick the target layer

- **meta-qcom** — Qualcomm reference boards (official evaluation/dev kits).
  New machine here is usually a new board on an *already-supported* SoC:
  add `conf/machine/<machine>.conf` requiring the existing
  `conf/machine/include/qcom-<soc>.inc`. A genuinely new SoC additionally
  needs that include created (step 4).
- **meta-qcom-3rdparty** — third-party maintained boards (e.g. Arduino UNO
  Q, Radxa Dragon Q6A). Depends on `meta-qcom` (`meta-qcom.git`, matching
  branch) for the SoC includes and core recipes; only add here what is
  genuinely board-specific: machine conf, CI yml, and — if the board ships
  its own bootloader/firmware/packagegroup — those recipes too (steps 5-6).

Confirm with the user which layer applies; do not guess between an official
reference board and a third-party community board.

## 2. Establish the target

Ask (or infer from the request) if not already known:

- **Machine name** — kebab-case, matches the board naming already in
  `conf/machine/*.conf` (e.g. `<board>-idp`, `<board>-evk`, `<board>-mtp`,
  `-ride`, `-core-kit`, `-ride-sx`, or a third-party product name like
  `uno-q`, `radxa-dragon-q6a`). This becomes `MACHINE` and the filename.
- **SoC** the board is based on (e.g. qcs6490, qcs8300, sdx75, qcm2290).
- **Closest existing board** to copy from. If unsure, pick a machine on the
  same SoC family — see step 3.
- **Bootloader/firmware ownership** (3rdparty only): does the vendor ship
  its own bootloader/firmware blobs (like UNO Q's Arduino-signed bootloader
  zip), or does the board use the SPI-NOR/EDK2 image flashed independently
  by the vendor (like Radxa Dragon Q6A, which sets the boot firmware
  variables empty with a comment explaining why)? This decides whether you
  need a `firmware-boot` recipe at all.

## 3. Find the template to copy from

```sh
ls conf/machine/*.conf
grep -rl "SOC_FAMILY" conf/machine/include/*.inc   # meta-qcom only
```

- If a `conf/machine/include/qcom-<soc>.inc` already exists for this SoC
  (in meta-qcom, or reachable via meta-qcom from a 3rdparty layer), find
  another machine `.conf` that `require`s it — that's your template.
  Example: `qcs6490-rb3gen2-core-kit.conf` requires
  `include/qcom-qcs6490.inc`; UNO Q's `uno-q.conf` requires
  `conf/machine/include/qcom-qcm2290.inc` from meta-qcom even though the
  board itself lives in meta-qcom-3rdparty.
- If no include exists for this SoC yet, this is a **new SoC**, not just a
  new board — go to step 4 first, then come back here. New-SoC work belongs
  in meta-qcom, not in a 3rdparty layer.
- Read the chosen template `.conf` end to end before writing anything new.

## 4. Write `conf/machine/<machine>.conf`

Follow the exact structure used by every existing machine conf. Reference
points: `qcs615-ride.conf` / `rb3gen2-core-kit.conf` / `glymur-crd.conf` in
meta-qcom for reference-board style; `uno-q.conf` / `radxa-dragon-q6a.conf`
in meta-qcom-3rdparty for third-party style.

```
#@TYPE: Machine
#@NAME: <human-readable board name>
#@DESCRIPTION: Machine configuration for <human-readable board name>, with <SoC>

require conf/machine/include/qcom-<soc>.inc
MACHINEOVERRIDES =. "<vendor>:"        # 3rdparty boards with their own overrides, e.g. "arduino:"

MACHINE_FEATURES += "<features specific to this board>"

KERNEL_DEVICETREE ?= " \
                      qcom/<dtb-name>.dtb \
                      "

MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS += " \
    packagegroup-<board>-firmware \
    packagegroup-<board>-hexagon-dsp-binaries \
"

QCOM_CDT_FILE = "<cdt name>"                        # reference boards
QCOM_BOOT_FILES_SUBDIR = "<subdir under boot firmware>"
QCOM_PARTITION_FILES_SUBDIR ?= "partitions/<board>/<ufs|nvme|spinor|emmc>"

QCOM_BOOT_FIRMWARE = "firmware-qcom-boot-<soc-or-board>"
QCOM_CDT_FIRMWARE = "firmware-qcom-cdt-<soc-or-board>"      # reference boards

UBOOT_CONFIG = "<board defconfig fragment>"                  # if u-boot-qcom/u-boot-<vendor> is the bootloader
```

Rules learned from the existing confs:

- `MACHINE_FEATURES` uses `+=` when the SoC include already sets a base set
  (`qcom-qcs6490.inc` sets `alsa bluetooth usbgadget usbhost wifi`); use `=`
  only when the board must replace the base set entirely (rare — see
  `kaanapali-mtp.conf`).
- If the vendor's bootloader/firmware is flashed independently and not
  built by this layer, blank the `QCOM_BOOT_FIRMWARE` / `QCOM_CDT_*` /
  `QCOM_PARTITION_*` variables with a comment explaining why (see
  `radxa-dragon-q6a.conf`, which uses Radxa's own SPI-NOR EDK2 image and
  sets no `PREFERRED_PROVIDER_virtual/bootloader`).
- If the vendor ships prebuilt bootloader binaries this layer packages
  itself (UNO Q's Arduino zip), point `PREFERRED_PROVIDER_virtual/kernel`
  and `PREFERRED_PROVIDER_virtual/bootloader` at the board's own recipes
  (`linux-arduino`, `u-boot-arduino`) instead of the shared meta-qcom ones,
  and write the recipes in step 6.
- Only add the `QCOM_RT_CPU` / `QCOM_IRQAFF` / `QCOM_RCU_NOCBS` /
  `QCOM_RCU_EXPEDITED` / `QCOM_CPUIDLE_OFF` isolation block if the board
  supports an RT kernel and needs isolated CPUs — copy values from a
  same-SoC sibling if one exists.
- If this is a firmware/config variant of an existing board rather than new
  hardware (e.g. `-open-fw`), `require conf/machine/<base>.conf` instead of
  the SoC include, and add only the deltas — see
  `rb3gen2-core-kit-open-fw.conf`.
- If the new machine is a rename/alias of an existing one, mark the old one
  deprecated instead: `#DEPRECATED, use <new> instead` +
  `require conf/machine/<new>.conf` (see `qrb2210-rb1-core-kit.conf`).

Never invent DTB names, CDT file names, or firmware package/URL details —
ask the user for these; they come from the board's kernel/firmware
delivery, not from convention.

## 5. New SoC only: scaffold `conf/machine/include/qcom-<soc>.inc` (meta-qcom)

Only needed when step 3 found no existing include for this SoC — and only
in meta-qcom, never in a 3rdparty layer. Model on
`conf/machine/include/qcom-qcs6490.inc` or `qcom-qcs615.inc`:

```
# Configurations and variables for <SOC> SoC family.

SOC_FAMILY = "<soc-family>"
require conf/machine/include/qcom-base.inc
require conf/machine/include/qcom-common.inc

DEFAULTTUNE = "<armv8-2a-crypto | matching arch tune>"
require conf/machine/include/arm/arch-<matching-armv8-x>.inc

MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS += " \
    packagegroup-qcom-boot-essential \
    packagegroup-machine-essential-qcom-<soc>-soc \
"

MACHINE_EXTRA_RRECOMMENDS += " \
    packagegroup-qcom-boot-additional \
"
```

Confirm the DEFAULTTUNE/arch include by checking what a same-generation SoC
uses in `conf/machine/include/arm/` rather than guessing.

## 6. Third-party boards only: add the board's own recipes

meta-qcom-3rdparty's `AGENTS.md` rule is **no recipe forks** — never copy a
recipe out of meta-qcom to modify it; use a `.bbappend` instead. Only write
new recipes for what is genuinely unique to this board:

- **`recipes-bsp/packagegroups/packagegroup-<board>.bb`** — model on
  `packagegroup-uno-q.bb`: `inherit packagegroup`, a `-firmware` and
  `-hexagon-dsp-binaries` package split, `RRECOMMENDS`/`RDEPENDS` gated by
  `bb.utils.contains(_any)('DISTRO_FEATURES', ...)` for optional features
  (wifi, bluetooth, opengl/vulkan/opencl).
- **`recipes-bsp/firmware-boot/firmware-qcom-boot-<board>_<version>.bb`** —
  only if the vendor ships a prebuilt bootloader/firmware bundle this layer
  fetches and packages (model on
  `firmware-qcom-boot-qrb2210-arduino-imola_251020.bb`): `SRC_URI` to the
  vendor's download with a `sha256sum`, `BOOTBINARIES`,
  `QCOM_BOOT_IMG_SUBDIR`, `COMPATIBLE_MACHINE = "(<machine>)"`, and
  `include recipes-bsp/firmware-boot/firmware-qcom-boot-common.inc`. Skip
  this entirely for boards like Radxa Dragon Q6A where firmware is flashed
  independently.
- **`recipes-bsp/u-boot/u-boot-<vendor>_git.bb`** — only if the board needs
  a vendor-forked bootloader source tree distinct from `u-boot-qcom`.

Do not create per-vendor branches or top-level folder segregation — every
board's recipes live under the layer's normal `recipes-*` tree per
`AGENTS.md`.

## 7. Add the matching CI yaml

Every machine conf has a same-named `ci/<machine>.yml` used by kas.

meta-qcom:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/siemens/kas/master/kas/schema-kas.json

header:
  version: 14
  includes:
  - ci/base.yml

machine: <machine>
```

meta-qcom-3rdparty additionally pins the meta-qcom dependency
(`ci/meta-qcom.yml` — a `repos:` entry pointing at
`https://github.com/qualcomm-linux/meta-qcom`, matching branch); base it on
`ci/uno-q.yml` or `ci/radxa-dragon-q6a.yml`, which include `ci/base.yml`
(itself pulling in `ci/meta-qcom.yml`) the same way.

## 8. Validate

Per each layer's `AGENTS.md`, before considering this done:

```sh
export KAS_YAMLS="ci/<machine>.yml:ci/qcom-distro.yml"
"${KAS_CONTAINER:-kas-container}" build "${KAS_YAMLS}"
ci/kas-container-shell-helper.sh ci/yocto-patchreview.sh
```

Run `ci/kas-container-shell-helper.sh ci/yocto-check-layer.sh` before
opening or updating a pull request. Do not skip straight to a PR without at
least a successful `bitbake` parse/build of the new machine.

## 9. Commit

Follow the layer's `CONTRIBUTING.md`/`AGENTS.md`: subject
`conf/machine: add <machine>` (or `recipes-bsp/<recipe>: add <machine>` for
a recipe-only commit — keep each logical change atomic and in its own
commit), plain-English body explaining what board this is and why, and a
`Signed-off-by` trailer built from `git config user.name`/`user.email` —
never fabricate identity. Add `Assisted-by: AGENT_NAME:MODEL_VERSION` if an
AI assistant helped write the change.

## Notes

- meta-qcom's primary branch is `master`; meta-qcom-3rdparty's is `main`
  (both also carry LTS branches — check the target repo before branching).
- Reference-board additions (meta-qcom) and third-party additions
  (meta-qcom-3rdparty) share the machine-conf mental model but diverge on
  recipe ownership — meta-qcom centralizes SoC-level recipes, 3rdparty
  layers add only board-unique ones and depend on meta-qcom for the rest.
- For subsequent work on the new machine, follow up with
  `qcom-yocto-build-image` (build), `qcom-flash-qdl`/`qcom-boot-validate`
  (flash and validate on hardware), and `qcom-yocto-pre-pr-checks` before
  opening the PR.
