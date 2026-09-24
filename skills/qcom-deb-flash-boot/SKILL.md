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
metadata:
  version: "0.2"
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
a firehose programmer over USB-C. How a board enters it is board-specific, so
do not guess a switch or button. On the RB3 Gen 2:

1. Remove power from the board.
2. Remove any cable from the USB-C port.
3. Hold the `F_DL` button while applying power.
4. Connect the USB-C cable from host to board.

For any other board (the EVKs use DIP switches, and the Arduino UNO Q /
VENTUNO Q have their own procedure), follow the per-board steps in the
`qcom-flash-qdl` skill's `references/entering-edl.md`, or the "flash images"
section of the board's Quick Start Guide (<https://docs.qualcomm.com>;
Dragonwing boards: <https://dragonwingdocs.qualcomm.com>), rather than this
sequence.

Confirm the host enumerates the device before flashing:

```bash
lsusb -d 05c6:9008
```

No output ⇒ the board is not in EDL — recheck the button/switch sequence and
cable; do not proceed. (qdl can also be started first and the board then
brought up directly into EDL.)

**More than one line of output ⇒ more than one board is in EDL.** An
unqualified `qdl` picks whichever device it finds first, so it can flash — and
overwrite — the wrong board. Get the serials and pin the target down with
`--serial=`:

```bash
lsusb -v -d 05c6:9008 | grep iSerial
```

```bash
qdl --serial=<SERIAL> --storage ufs prog_firehose_ddr.elf rawprogram[0-9].xml patch[0-9].xml
```

Add `--serial=<SERIAL>` to every `qdl` command below whenever multiple EDL
devices are present. If you cannot establish which serial is the intended board
from context you already have, **stop and ask the user** — present the list of
detected serials and wait for them to name the target. Do not pick a serial
arbitrarily, do not fall back to an unqualified `qdl`, and do not flash until
the user has identified the board. (Physically disconnecting the other boards
is an equally good resolution, but that is the user's action, not the agent's.)

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

**Destructive — confirm with the user before running any `qdl` command below.**
Flashing rewrites the board's partition table and overwrites its storage,
including any existing OS and data. Before proceeding, state which board (and
which `--serial=`, if several are in EDL) and which `flash_*` directory you are
about to use, and get explicit confirmation.

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
the first UFS LUN using the repo's top-level `rawprogram-ufs.xml`. This needs a
`prog_firehose_ddr.elf` for the **target platform**, e.g. from that SoC's boot
binaries package — it is not one this repo builds.

Run this from the **checkout root**, not from a `flash_*` directory — both
`rawprogram-ufs.xml` and the `disk-ufs.img` it references live at the top level,
and the preceding sections leave you inside `flash_<board>_<storage>/`:

```bash
cd /path/to/qcom-deb-images     # back to the checkout root
qdl --storage ufs prog_firehose_ddr.elf rawprogram-ufs.xml
```

Same destructive-write caveat as above: confirm with the user first, and add
`--serial=<SERIAL>` if more than one board is in EDL.

## Write to an SD card

`disk-sdcard.img` (512-byte sectors) can be written directly to a card. Most
Qualcomm boards still boot firmware from internal storage (eMMC/UFS) and then
EFI-boot from the SD card when internal storage has no bootable OS.

Writing the image is **destructive and irreversible**: `dd` will silently
overwrite whatever `of=` names, including the host's own system disk. There is
no undo and no confirmation prompt. Do not run it until the target device is
positively identified and the user has confirmed that exact device path.

First list the candidates and identify the card by its removable flag,
transport and size:

```bash
lsblk -d -o NAME,SIZE,TYPE,RM,TRAN,MOUNTPOINT
```

The SD card should show `RM=1` (removable) and `TRAN=usb` or `mmc`. A device
with `RM=0` on `TRAN=nvme`/`sata` is an internal disk — never a valid target.
Note that `RM=1` alone is not proof: a USB-attached backup drive also reports
removable, so match the size against the card you inserted as well.

Then verify the specific device before writing, and refuse to continue if any
check fails:

```bash
DEV=/dev/sdX                                  # the device identified above
test -b "$DEV"                                # must be a block device
lsblk -no RM "$DEV" | head -1                 # must print 1
lsblk -no MOUNTPOINT "$DEV" | grep -q . && echo "MOUNTED - unmount first"
```

A device with mounted partitions is either in use or the wrong device; unmount
it (`sudo umount /dev/sdX*`) and re-check rather than forcing the write. Only
once `$DEV` is confirmed and the user has approved that path:

```bash
sudo dd if=disk-sdcard.img of="$DEV" bs=4M conv=fsync status=progress
sync
```

Never substitute a guess for `$DEV`, and never widen the target (e.g. to
`/dev/sda` because `/dev/sdb` was busy) without re-running the checks above.

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
password **`debian`**. The account ships **expired** (`chage --lastday 0`),
so the *first* login forces a password change before you get a shell:

```text
debian login: debian
Password: debian
You are required to change your password immediately (administrator enforced)
Current password: debian
New password: <new password>
Retype new password: <new password>
```

Only after this does the `debian@debian:~$` prompt appear; subsequent logins
use the new password. Anything driving the console must expect and answer the
`Current password:` / `New password:` / `Retype new password:` prompts — a
plain `debian`/`debian` login without them will not reach a shell. Simple
console drivers (including `qcom-boot-validate`) cannot do this, so get the
change out of the way interactively on first boot.

> These are Debian credentials — different from the Yocto/QLI images
> (`root` / `oelinux123`). Use the right pair for the image you flashed.

## Hand off

After flashing a physical board, power-cycle it out of EDL to boot the new
image, then validate the boot over serial with `qcom-boot-validate`.

`qcom-boot-validate` **cannot** complete the forced password change — it sends
one username and one password and then waits for a shell prompt, so a
`--password debian` run stalls at `Current password:` and fails. Complete the
change once by hand first (interactively over the serial console, per the
flow above), then hand the **new** password to the validator:

```bash
python3 scripts/boot-validate.py --port /dev/ttyUSB0 \
    --username debian --password '<new password>'
```

Note that `--password debian` will no longer authenticate once the change is
done: the old password is spent, and the validator needs the new one.

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
