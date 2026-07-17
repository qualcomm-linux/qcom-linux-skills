---
name: qcom-deb-flash-boot
description: >-
  Flash a Qualcomm Linux Debian image from qcom-deb-images onto a board over
  EDL/QDL (UFS, eMMC, or the whole-disk rawprogram-ufs.xml path), write a
  disk-sdcard.img to an SD card, or boot a disk image locally under QEMU with
  scripts/run-qemu.py, then log in as debian/debian. Use when asked to "flash
  the Debian image", "flash qcom-deb-images to the RB3 Gen2 / RB1", "boot the
  Debian image in QEMU", "run the trixie image", or "write the SD card image".
  Do NOT use for Yocto/QLI qcomflash bundles (see qcom-flash-qdl), for
  building the Debian image (see qcom-deb-build-image), or for serial boot
  validation of a physical board (see qcom-boot-validate).
---

# Flash & boot a Qualcomm Linux Debian image

Deploys the artifacts from a `qcom-deb-images` build (see
`qcom-deb-build-image`): flashing a `flash_<board>_<storage>/` directory onto a
board over EDL with QDL, writing `disk-sdcard.img` to an SD card, or booting a
`disk-*.img` under QEMU. Follows the qcom-deb-images README.

## Which path?

| You have / want | Use |
|---|---|
| A board in hand + a `flash_<board>_<storage>/` dir | **Flash over EDL** (§ below) |
| A UFS board, boot firmware already good | **Whole-disk `rawprogram-ufs.xml`** flash |
| An SD-card-capable board + `disk-sdcard.img` | **Write to SD card** |
| No board / a quick smoke test on the host | **Boot under QEMU** |

## Prerequisites (EDL flashing)

- **qdl ≥ 2.1** from [linux-msm/qdl](https://github.com/linux-msm/qdl)
  (earlier versions have relevant bugs), on PATH.
- A udev rule for VID:PID `05c6:9008` so qdl runs without root; otherwise run
  qdl via sudo (prefer the rule).
- `ModemManager` not running (it grabs the EDL device):
  `systemctl is-active ModemManager` — stop it if active.
- The `flash_<board>_<storage>/` directory from `qcom-deb-build-image`,
  containing `prog_firehose_ddr.elf`, `rawprogram[0-9].xml`, `patch[0-9].xml`.

## Enter EDL mode

EDL (Emergency Download) is a lower-level mode than fastboot; the host pushes
a firehose programmer over USB-C. To enter it:

1. Remove power from the board.
2. Remove any cable from the USB-C port.
3. On some boards, set the DIP switches for EDL.
4. Hold the `F_DL` button while applying power.
5. Connect the USB-C cable from host to board.

Confirm the host enumerates the device before flashing:

```bash
lsusb -d 05c6:9008
```

No output ⇒ the board is not in EDL — recheck the button/switch sequence and
cable; do not proceed. (qdl can also be started first and the board then
brought up directly into EDL.)

### Driving EDL / reset from a controller

If the board is wired to a **Bughopper** or **Alpaca** (TAC) debug
controller, you can enter EDL or reset it without touching buttons, using
[pytac](https://github.com/qualcomm/pytac) (Python Test Automation
Controller): `bootToEDL` and `reset` cover the sequence above, and it also
does power control (`powerOn`/`powerOff`, `usbDevicePower`). Bughopper V1/V2
work out of the box; FTDI/PSOC setups need the matching `.tcnf` +
`devicelist.json`. Keep the site-specific wiring/config in your pytac setup,
not in this skill — this skill only assumes the board reaches EDL.

## Flash over EDL

Run from inside the board's flash directory. Match the storage type to the
directory suffix.

**UFS boards** (e.g. `qcs6490-rb3gen2-vision-kit`, `qcs615-ride`,
`qcs8300-ride`, `qcs9100-ride-r3`):

```bash
cd flash_qcs6490-rb3gen2-vision-kit_ufs
qdl --storage ufs prog_firehose_ddr.elf rawprogram[0-9].xml patch[0-9].xml
```

**eMMC boards** (e.g. `qrb2210-rb1`) — note `--allow-missing`:

```bash
cd flash_qrb2210-rb1_emmc
qdl --allow-missing --storage emmc prog_firehose_ddr.elf rawprogram[0-9].xml patch[0-9].xml
```

A healthy run opens with the firehose handshake (`HELLO version: ...`) then
per-partition program/patch progress. Report qdl's exit status and last
output lines.

### Whole-disk UFS flash (no firmware update)

If the boot firmware on a UFS board is already good, flash just the OS disk to
the first UFS LUN using the repo's top-level `rawprogram-ufs.xml` (this needs a
`prog_firehose_ddr.elf` for the **target platform**, e.g. from that SoC's boot
binaries package — it is not one this repo builds):

```bash
qdl --storage ufs prog_firehose_ddr.elf rawprogram-ufs.xml
```

## Write to an SD card

`disk-sdcard.img` (512-byte sectors) can be written directly to a card. Most
Qualcomm boards still boot firmware from internal storage (eMMC/UFS) and then
EFI-boot from the SD card when internal storage has no bootable OS.

Identify the card device carefully, then write it. **Destructive** — confirm
the target with the user first:

```bash
lsblk                     # find the card, e.g. /dev/sdX or /dev/mmcblk0
sudo dd if=disk-sdcard.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Double-check `of=` is the SD card and not a host disk before running.

## Boot under QEMU (no hardware)

`scripts/run-qemu.py` boots a disk image on the host via an aarch64 UEFI
firmware. It auto-detects `disk-ufs.img` / `disk-sdcard.img` in the current
dir, sets the SCSI sector size (4096 UFS / 512 SD), and uses a throwaway
qcow2 copy-on-write overlay so the base image is untouched.

Deps: Debian/Ubuntu `sudo apt install qemu-efi-aarch64 qemu-system-arm qemu-utils`;
macOS `brew install qemu`.

```bash
scripts/run-qemu.py                       # auto-detect image in cwd
scripts/run-qemu.py --storage ufs         # or: --storage sdcard
scripts/run-qemu.py --image /path/to/disk-ufs.img
scripts/run-qemu.py --headless            # serial console on stdio, no GUI
scripts/run-qemu.py --no-cow              # persist changes to the base image
scripts/run-qemu.py --qemu-args "-smp 4 -m 4096"
```

Use `--headless` when driving it from a terminal/agent (GUI display is the
default otherwise).

## Log in

Once booted (on hardware or in QEMU), log in as user **`debian`** with
password **`debian`**; the image then prompts you to set a new password.

> These are Debian credentials — different from the Yocto/QLI images
> (`root` / `oelinux123`). Use the right pair for the image you flashed.

## Hand off

After flashing a physical board, power-cycle it out of EDL to boot the new
image, then validate the boot over serial with `qcom-boot-validate`
(pass `--username debian --password debian`).

## Notes / gotchas

- A failed/interrupted `qdl` just leaves the board in EDL — re-run the same
  command; no re-arming needed.
- qdl stuck at "waiting for EDL device" usually means ModemManager stole it,
  the udev rule is missing, or the board fell out of EDL (power-cycle back in
  and retry).
- Never flash one board's `flash_*` dir onto a different board — the
  `rawprogram*.xml` encodes that board's partition layout. EDL remains
  available for recovery, but you can clobber storage contents.
- Don't cross Debian and Yocto artifacts: a `flash_<board>_<storage>/` dir is
  not a Yocto `qcomflash` bundle (that's `qcom-flash-qdl`), and the login
  credentials differ.
