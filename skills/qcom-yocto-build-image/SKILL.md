---
name: qcom-yocto-build-image
description: >-
  Build a Qualcomm Linux (Yocto) image from meta-qcom with kas-container,
  composing ci/<machine>.yml with optional distro and kernel overlays, and
  locate the flashable qcomflash artifact it produces. Use when asked to
  "build an image for the RB3 Gen2 / ride-sx / IQ EVK", "build
  qcom-console-image", "build meta-qcom", "do a qcom-distro / sota build",
  or "build with the qcom-next kernel". Do NOT use for Debian images
  (qcom-deb-images), for flashing (see qcom-flash-qdl), or for running
  pre-PR checks (see qcom-yocto-pre-pr-checks).
---

# Build a Qualcomm Linux image with kas-container

Builds meta-qcom images exactly the way the project's CI does, following
meta-qcom's `AGENTS.md`: `kas-container` for host isolation, shared caches
outside the repo, and a build defined purely by composing `ci/*.yml` files.

## Prerequisites

- A meta-qcom checkout (`git clone https://github.com/qualcomm-linux/meta-qcom`).
- `kas-container` on PATH (from [kas](https://github.com/siemens/kas)), with a
  working Docker or Podman runtime (verify with `docker run --rm hello-world`).
- Tens of GB free disk space; a first build downloads sources and builds the
  full toolchain (hours). Re-builds with a warm sstate cache are much faster.

## 1. Set up the environment

If `KAS_WORK_DIR`, `DL_DIR`, and `SSTATE_DIR` are already set, use them — do
not override. Only set defaults when absent, and keep all three **outside**
the repo so caches are shared and the checkout is not polluted:

```bash
cd <meta-qcom checkout>
export KAS_WORK_DIR="${KAS_WORK_DIR:-$HOME/build/qcom}"
export DL_DIR="${DL_DIR:-$HOME/build/cache/downloads}"
export SSTATE_DIR="${SSTATE_DIR:-$HOME/build/cache/sstate-cache}"
mkdir -p "$KAS_WORK_DIR" "$DL_DIR" "$SSTATE_DIR"
```

## 2. Compose the kas configuration

The build is `ci/<machine>.yml[:ci/<distro>.yml][:ci/<kernel or feature>.yml]`,
colon-separated. Always list `ci/*.yml` in the checkout for the authoritative
set; the common ones are:

**Machine configs** (one per supported board — pick exactly one first):
`rb3gen2-core-kit` (and `-open-fw`), `qcs6490-rb3gen2-core-kit`,
`rb1-core-kit`, `qrb2210-rb1-core-kit`, `qcm6490-idp`, `qcs615-ride`,
`qcs8300-ride-sx`, `qcs9100-ride-sx`, `sdx75-idp`, `sm8750-mtp`,
`kaanapali-mtp`, `glymur-crd`, `shikra-evk`, `iq-615-evk`, `iq-8275-evk`,
`iq-9075-evk` (and `-open-fw`), `iq-x5121-evk`, `iq-x7181-evk`, plus the
generic `qcom-armv8a` / `qcom-armv7a`.

**Distro overlays** (optional; without one the build is `nodistro`):

| Overlay | Effect |
|---|---|
| `ci/qcom-distro.yml` | Qualcomm reference distro (from meta-qcom-distro) |
| `ci/qcom-distro-sota.yml` | qcom-distro + OTA/Uptane (aktualizr) |
| `ci/qcom-distro-selinux.yml` | qcom-distro + SELinux |
| `ci/qcom-distro-kvm.yml`, `ci/qcom-distro-catchall.yml`, ... | feature variants |

**Kernel / feature overlays** (optional):

| Overlay | Effect |
|---|---|
| `ci/linux-qcom-next.yml` | kernel = linux-qcom-next (qcom-next branch) |
| `ci/linux-qcom-next-rt.yml` | qcom-next PREEMPT_RT variant |
| `ci/linux-qcom-6.18.yml` / `ci/linux-qcom-rt-6.18.yml` | 6.18 stable kernel |
| `ci/kernel-fit-image.yml`, `ci/u-boot-qcom.yml` | FIT image / U-Boot boot flow |
| `ci/debug.yml`, `ci/performance.yml` | debug / performance tuning |

## 3. Pick the image target and build

- **nodistro** (machine yml only): the default target is `core-image-base` —
  just build:

  ```bash
  kas-container build ci/rb3gen2-core-kit.yml
  ```

- **qcom-distro variants**: the product images come from meta-qcom-distro
  (`qcom-console-image`, `qcom-minimal-image`, `qcom-multimedia-image`,
  `qcom-networking-image`, ...). `qcom-console-image` is not in the yml's
  default target list, so invoke bitbake explicitly:

  ```bash
  kas-container shell ci/qcs9100-ride-sx.yml:ci/qcom-distro.yml \
    -c "bitbake qcom-console-image"
  ```

Report build failures verbatim (the failing task and its log path) rather
than retrying blindly; a plain retry is only worth it for transient fetch
errors.

## 4. Locate the artifacts

Deploy dir: `$KAS_WORK_DIR/build/tmp/deploy/images/<machine>/`.

The flashable artifact is the `qcomflash` bundle (enabled by `ci/base.yml`),
e.g. `core-image-base-rb3gen2-core-kit.rootfs.qcomflash.tar.gz` — it contains
`prog_firehose_ddr.elf` plus `rawprogram*.xml` / `patch*.xml` and is what
`qcom-flash-qdl` consumes. Report the full artifact path and its timestamp so
the user can tell a fresh build from a stale one.

## Notes

- `ci/base.lock.yml` pins all upstream layers, so builds are reproducible;
  use the `qcom-yocto-update-base-lock` skill to refresh the pins.
- `BUILD_ID` from the environment is stamped into `/etc/os-release` on the
  image — set it (e.g. to a date or CI run id) if you need to identify the
  build on the booted board later (`qcom-device-info` prints it).
- For one-off commands inside an existing build, use
  `kas-container shell --skip repos_checkout <cfg> -c "<command>"`.
- meta-qcom's primary branch is `master`; the LTS branch (Qualcomm Linux
  2.x) is `wrynose` — make sure the checkout matches what the user wants to
  build.
