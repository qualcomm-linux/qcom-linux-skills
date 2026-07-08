---
name: qcom-kernel-qcom-next-build
description: >-
  Cross-build the qualcomm-linux kernel (qcom-next branch) standalone on an
  x86 host: arm64 defconfig with the prune.config + qcom.config fragment
  merge used by meta-qcom's linux-qcom-next recipe, producing Image, DTBs
  and modules. Use when asked to "build the qcom-next kernel", "compile the
  Qualcomm kernel", "build a kernel with my patch for a qcom board", or
  "enable a kernel config for qcom". Do NOT use for building complete
  images (see qcom-yocto-build-image) or for bumping the kernel SRCREV in
  meta-qcom recipes.
---

# Build the qcom-next kernel standalone

Builds the [qualcomm-linux kernel](https://github.com/qualcomm-linux/kernel)
`qcom-next` branch from the command line, using the exact configuration
recipe meta-qcom's `linux-qcom-next` uses — so a standalone developer build
matches what the Yocto image ships.

## Prerequisites

- An aarch64 cross toolchain, e.g. `gcc-aarch64-linux-gnu` (or clang with
  `LLVM=1`).
- Usual kernel build deps: `flex`, `bison`, `libssl-dev`, `libelf-dev`,
  `bc`.

## 1. Get the source

```bash
git clone -b qcom-next https://github.com/qualcomm-linux/kernel.git
cd kernel
```

Notes on the tree:

- `qcom-next` is an integration branch, regularly rebuilt on top of
  mainline `-rc` tags from merged topic branches (see the `qcom-next/`
  bookkeeping directory with `merge.log`). Do not base long-lived work
  directly on it without expecting rebases; check with the maintainers'
  workflow for where to send patches.
- meta-qcom pins a tagged snapshot (`qcom-next-<ver>-<date>` tags) via
  `SRCREV` in `linux-qcom-next_git.bb` — build that tag instead of the
  branch tip when reproducing an image kernel exactly.

## 2. Configure — defconfig + qcom fragments

Mirror the fragment merge from meta-qcom's recipe: `defconfig`, minus the
generic bloat that `prune.config` removes, plus the Qualcomm enablement in
`qcom.config`:

```bash
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make defconfig
./scripts/kconfig/merge_config.sh -m -O . .config \
    arch/arm64/configs/prune.config \
    arch/arm64/configs/qcom.config
make olddefconfig
```

Optional additions, matching the recipe's variants:

- **Debug build**: append `kernel/configs/debug.config` and
  `arch/arm64/configs/qcom_debug.config` to the merge list.
- **PREEMPT_RT**: append `arch/arm64/configs/rt.config`.
- **Own changes**: put them in a small fragment file and append it to the
  merge list rather than hand-editing `.config`; that keeps the change
  reviewable and re-appliable.

After merging, verify nothing you asked for was dropped:
`grep CONFIG_<OPTION> .config` (merge_config warns on conflicts — treat
those warnings as errors).

## 3. Build

```bash
make -j"$(nproc)" Image dtbs modules
```

Artifacts:

- Kernel: `arch/arm64/boot/Image`
- Device trees: `arch/arm64/boot/dts/qcom/<board>.dtb` (e.g.
  `qcs6490-rb3gen2.dtb`, `qcs9100-ride-r3.dtb`)
- Modules: `make INSTALL_MOD_PATH=<staging dir> modules_install`

## 4. Getting it onto a board

Two supported routes:

- **Through meta-qcom** (recommended — produces a flashable image): build
  with `ci/linux-qcom-next.yml` and point the recipe at your tree/SRCREV,
  or use the `linux-qcom-next-upstream` devupstream variant which builds
  the tip of `qcom-next`. Then flash with `qcom-flash-qdl` and check with
  `qcom-boot-validate`.
- **Manual swap** of `Image`/DTB into an existing boot flow — board- and
  boot-flow-specific; confirm the target's boot chain (ABL/U-Boot/UEFI)
  before attempting.

## Notes

- 32-bit ARM machines (`qcom-armv7a`) use `qcom_defconfig` directly, with
  no fragment merge.
- `make dtbs W=1` and `make dt_binding_check` are worth running when the
  change touches device trees or bindings — qcom-next follows upstream
  kernel review standards.
- Kernel patches ultimately flow through the upstream linux-arm-msm
  process; qcom-next is an integration tree, not a fork to target with
  GitHub PRs — check the repo's contribution documentation first.
