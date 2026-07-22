---
name: qcom-deb-build-image
description: >-
  Build a Qualcomm Linux Debian image (trixie by default, forky also
  supported) from qcom-deb-images using its debos recipes and Makefile
  targets: rootfs.tar, disk-ufs.img / disk-sdcard.img, and the flashable
  flash_<board>_<storage> asset directories, with optional local kernel /
  U-Boot debs and desktop/overlay options. Covers most QLI PoR boards (RB1,
  RB3 Gen 2, the ride and EVK kits) and the Arduino Qualcomm boards (UNO Q,
  VENTUNO Q). Use when asked to "build a Debian image for the RB3 Gen2 / RB1
  / UNO Q", "build qcom-deb-images", "make a trixie image for a Qualcomm
  board", "build the debos image", or "build disk-ufs.img". Do NOT use for
  Yocto/QLI images (see qcom-yocto-build-image), for flashing or
  QEMU-booting the result (see qcom-deb-flash-boot), or for the standalone
  kernel cross-build (see qcom-kernel-qcom-next-build).
---

# Build a Qualcomm Linux Debian image with debos

Builds the Debian (trixie) images from
[qcom-deb-images](https://github.com/qualcomm-linux/qcom-deb-images) the way
the project's CI does: [debos](https://github.com/go-debos/debos) recipes
driven by the repo's `Makefile`, which sets the memory/scratchsize that the
recipes need. Prefer the Makefile targets over calling `debos` by hand — the
raw defaults are too small for these recipes.

## Prerequisites

- A qcom-deb-images checkout
  (`git clone https://github.com/qualcomm-linux/qcom-deb-images`).
- **debos ≥ 1.1.5** (needs the sector-size support). If `debos` is not on
  PATH, the Makefile auto-falls back to running the
  `ghcr.io/go-debos/debos:latest` container via Docker (`USE_CONTAINER=auto`);
  force it either way with `USE_CONTAINER=yes|no`.
- Image build-deps on the host (native builds):
  ```bash
  apt -y install debian-archive-keyring make mmdebstrap mtools python3-pexpect \
      python3-pytest qemu-efi-aarch64 qemu-system-arm xmlstarlet python3-defusedxml
  ```
- A fast debos backend. The Makefile picks `--fakemachine-backend kvm` when
  `/dev/kvm` exists, else `qemu`. Building arm64 under QEMU emulation on an
  x86 host is **slow** — expect a long first build.
- Tens of GB of free disk plus network access to the Debian archive and to
  Qualcomm/CodeLinaro boot-binary downloads (fetched during `make flash`).

## Build stages

The build is three ordered Makefile targets. Run them from the checkout root.

### 1. Root filesystem + DTB tarballs — `make rootfs.tar`

Produces `rootfs.tar` and `dtbs.tar.gz` from
`debos-recipes/qualcomm-linux-debian-rootfs.yaml`.

```bash
make rootfs.tar
```

Common rootfs options, passed via `EXTRA_DEBOS_OPTS="-t key:value"`:

| Option | Effect |
|---|---|
| `xfcedesktop:true` / `gnomedesktop:true` | install a desktop; default is console-only |
| `overlays:<a,b>` | rootfs overlays from `debos-recipes/overlays/`; default is `qsc-deb-releases` (adds the delta apt repo + `fastrpc-test`); `none` disables all |
| `kernelpackages:<pkgs>` | apt kernel packages; default is Debian's `linux-image-arm64`; set `none` when supplying a local kernel deb |
| `suite:<suite>` | Debian suite; default `trixie` (e.g. `forky` for the next release, or `sid`/`unstable`) |
| `snapshot:<YYYYMMDD>` | build against a snapshot.debian.org archive for reproducibility |

To fold in a **locally built kernel** (see step 0 below), drop the `.deb`s in
`debos-recipes/local-debs/` and disable the apt kernel:

```bash
EXTRA_DEBOS_OPTS="-t localdebs:local-debs/ -t kernelpackages:none" make rootfs.tar
```

### 2. Disk images — `make disk-ufs.img` / `make disk-sdcard.img`

Builds a partitioned disk image from `rootfs.tar` via
`debos-recipes/qualcomm-linux-debian-image.yaml`.

```bash
# default: UFS image, 4096-byte sectors
make disk-ufs.img

# SD card / eMMC boards: 512-byte sectors
make disk-sdcard.img
```

Image options (`EXTRA_DEBOS_OPTS`): `imagetype:ufs|sdcard` (the Makefile sets
`sdcard` for you on the sdcard target), `imagesize:<size>` (default `6GiB`),
`dtb:qcom/<board>.dtb` to have systemd override the firmware-provided device
tree (e.g. `qcom/qcs6490-rb3gen2.dtb`).

`make all` builds both `disk-ufs.img` and `disk-sdcard.img`.

### 3. Flashable assets — `make flash`

Downloads the per-board boot binaries + CDT, combines them with `dtbs.tar.gz`
and the disk images, and writes one `flash_<board>_<storage>/` directory per
supported board (from `debos-recipes/qualcomm-linux-debian-flash.yaml`).

```bash
make flash

# only some boards (comma-separated; see the board list below):
EXTRA_DEBOS_OPTS="-t target_boards:qcs615-ride,qcs6490-rb3gen2-vision-kit" make flash

# include a locally built RB1 U-Boot (see step 0):
EXTRA_DEBOS_OPTS="-t u_boot_rb1:u-boot/rb1-boot.img" make flash
```

Boards whose `.dtb` is absent from `dtbs.tar.gz` are silently skipped, so
confirm the directory for the board you want actually appears.

## Optional pre-steps

### 0a. Local kernel deb — `scripts/build-linux-deb.py`

```bash
apt -y install git crossbuild-essential-arm64 make flex bison bc libdw-dev \
    libelf-dev libssl-dev libssl-dev:arm64 dpkg-dev debhelper-compat kmod python3 rsync coreutils
# on a non-arm64 host, enable the foreign arch for libssl-dev:arm64 first:
#   dpkg --add-architecture arm64 && apt update

scripts/build-linux-deb.py kernel-configs/*.config              # mainline
scripts/build-linux-deb.py --linux-next kernel-configs/*.config # linux-next
scripts/build-linux-deb.py --qcom-next kernel-configs/*.config  # qcom-next
```

`--qcom-next` tracks the [qualcomm-linux/kernel](https://github.com/qualcomm-linux/kernel)
`qcom-next` branch (latest `qcom-next-*` tag) — often the most useful kernel
for these boards, as it carries the Qualcomm platform patches ahead of
mainline. `--repo`/`--ref` override the source for any other tree.

Then feed the resulting `.deb`s into step 1 via `localdebs:` + `kernelpackages:none`.

### 0b. U-Boot for RB1 — `scripts/build-u-boot-rb1.sh`

The RB1 (`qrb2210-rb1`) is the board that needs U-Boot built from this repo
and passed into `make flash`. (Other U-Boot-based boards such as the Arduino
UNO Q get their U-Boot from the downloaded boot binaries, so they need no
separate build step here.) Build it, then pass `u_boot_rb1:u-boot/rb1-boot.img`
to `make flash`.

```bash
apt -y install git crossbuild-essential-arm64 make bison flex bc libssl-dev \
    gnutls-dev xxd coreutils gzip mkbootimg
scripts/build-u-boot-rb1.sh
```

## Supported boards (target_boards names)

`target_boards` accepts the board names from the flash recipe; the storage
suffix on the output directory follows the board's `ptool` platform:

| Board name | SoC / product | Storage → flash dir |
|---|---|---|
| `qcs615-ride` | QCS615 | ufs → `flash_qcs615-ride_ufs` |
| `qcs6490-rb3gen2-vision-kit` | QCS6490 (RB3 Gen 2) | ufs → `flash_qcs6490-rb3gen2-vision-kit_ufs` |
| `qcs8300-ride` | QCS8300 | ufs → `flash_qcs8300-ride_ufs` |
| `qcs9100-ride-r3` | QCS9100 | ufs → `flash_qcs9100-ride-r3_ufs` |
| `glymur-crd` | Glymur CRD | nvme / spinor |
| `monaco-evk` | QCS8275 (IQ-8275-EVK) | emmc, ufs |
| `lemans-evk` | QCS9100 (IQ-9075-EVK) | ufs |
| `qrb2210-rb1` | QRB2210 (RB1) | emmc → `flash_qrb2210-rb1_emmc` (needs U-Boot, step 0b) |
| `qrb2210-arduino-imola` | QRB2210 (Arduino UNO Q) | emmc |
| `monaco-arduino-monza` | QCS8275 (Arduino VENTUNO Q) | emmc |

This covers most QLI PoR boards and all the Arduino Qualcomm boards. Board
names, SoCs and storage change over time — always read
`debos-recipes/qualcomm-linux-debian-flash.yaml` for the authoritative,
current list rather than assuming from this table.

## Locate the artifacts

All outputs land in the checkout root:

- `rootfs.tar`, `dtbs.tar.gz` — from step 1.
- `disk-ufs.img` (4096-byte sectors) / `disk-sdcard.img` (512-byte sectors) —
  from step 2.
- `flash_<board>_<storage>/` — from step 3, each holding
  `prog_firehose_ddr.elf`, `rawprogram[0-9].xml`, `patch[0-9].xml` and the
  partition images. This is what `qcom-deb-flash-boot` consumes.

Report the disk image(s) and the `flash_*` directories that were produced,
with timestamps, so a fresh build is distinguishable from a stale one.

## Hand off

- To flash a board or boot the image under QEMU, use the
  `qcom-deb-flash-boot` skill.
- To validate a flashed board reaches a login shell over serial, use
  `qcom-boot-validate` (log in as `debian` / `debian`, not the Yocto
  `root` credentials).

## Notes / gotchas

- Report debos/bitbake-style failures verbatim (failing recipe + action)
  rather than retrying blindly; a plain retry is only worth it for transient
  archive/download errors.
- `make flash` reaches out to Qualcomm Software Center / CodeLinaro for boot
  binaries; a 404 or auth wall there is an upstream-URL problem, not a recipe
  bug — re-check the URLs in the flash recipe.
- `make clean` removes the disk images and tarballs; `make clean-debos`
  removes the `.debos-*` scratch dirs. Neither touches the `flash_*` dirs.
- The Makefile honours `http_proxy` (from the environment or apt config) to
  speed up repeated archive fetches.
- These are mainline-centric Debian trixie images; they are **not** the
  Yocto/QLI images — do not cross bundles or credentials with
  `qcom-yocto-*`.
