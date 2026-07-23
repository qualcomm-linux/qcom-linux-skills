---
name: qcom-flash-qdl
description: >-
  Flash a Qualcomm Linux qcomflash image bundle onto a board in Emergency
  Download (EDL) mode using the QDL tool, including multi-board selection
  via --serial. Use when asked to "flash the board", "flash the RB3 Gen2 /
  rb1 / EVK", "flash the qcomflash image", "reflash over EDL", or when a
  device shows up as USB 05c6:9008. Do NOT use for building images (see
  qcom-yocto-build-image), for boot validation after flashing (see
  qcom-boot-validate), or for fastboot/U-Boot based flows.
metadata:
  version: "0.1"
---

# Flash a board over EDL with QDL

Flashes the `qcomflash` bundle produced by a meta-qcom build (see
`qcom-yocto-build-image`) or a prebuilt image download (see
`qcom-yocto-download-prebuilt`) onto a board in EDL mode, following
meta-qcom's `docs/flashing.md` and the Dragonwing flash guide.

## Prerequisites

- **qdl** built from [linux-msm/qdl](https://github.com/linux-msm/qdl)
  (follow its build instructions), or available on PATH.
- A udev rule granting raw USB access to VID:PID `05c6:9008` so qdl runs as
  a non-root user (see the "Update udev rules" section of the Qualcomm
  flashing docs). Without it, qdl must run via sudo — prefer the udev rule.
- ModemManager must not be running (it grabs the EDL USB device):
  `systemctl is-active ModemManager` — stop it if active.
- The flash bundle: a `*.qcomflash` directory or archive from the build deploy
  dir or prebuilt download, containing `prog_firehose_ddr.elf`,
  `rawprogram*.xml`, and `patch*.xml`.

## Procedure

### 0. Identify device and storage type

Ask the user which board they are flashing if not already stated. This
determines storage type, whether UFS provisioning is needed, whether SAIL must
be flashed, and which CDT to use.

See [references/storage-types.md](references/storage-types.md) for the default
storage type per board. Surface the storage type early — the `qdl` command and
several later steps depend on it.

### 1. Stage the flash bundle

**Prebuilt image (zip archive):**
```bash
unzip <prebuilt-image>.zip
cd <unzipped-image-directory>/images/<machine>/<image>-<machine>
```

**Compiled image (already in deploy dir):**
```bash
cd build/tmp/deploy/images/<machine>/<image>-<machine>.rootfs.qcomflash
```

Confirm the bundle is intact — these files must all exist:
```bash
ls prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

All subsequent commands run from this directory unless stated otherwise.

### 2. Open the serial console (recommended)

Connect the debug UART and open it at 115200 baud so flashing and the first
boot can be observed (`dmesg | grep tty` shows the device, e.g.
`/dev/ttyUSB0`):

```bash
picocom -b 115200 /dev/ttyUSB0
```

### 3. Put the board in EDL mode

See [references/entering-edl.md](references/entering-edl.md) for per-board
instructions (e.g. RB3 Gen 2: hold `F_DL` while applying power). Then
confirm the host sees the EDL device:

```bash
lsusb -d 05c6:9008
```

No output means the board is not in EDL — do not proceed; re-check the
button/switch sequence and the USB cable.

### 4. Provision UFS

> Skip this step for **IQ-615-EVK** (EMMC storage).

UFS must be provisioned before the first flash, and re-provisioned if the LUN
layout has changed. It is safe to re-run when unsure. See
[references/provision-ufs.md](references/provision-ufs.md) for the per-board
download URL and `qdl` command.

The device reboots after provisioning. Confirm it is back in EDL
(`lsusb -d 05c6:9008`) before proceeding.

### 5. Flash SAIL

> Only for **IQ-9075-EVK** and **IQ-8275-EVK**. Skip for all other boards.

SAIL (Safety Island) is isolated safety-critical firmware. Its artifacts are in
the `sail_nor/` subdirectory of the flash bundle:

```bash
cd sail_nor
qdl --storage spinor prog_firehose_ddr.elf rawprogram0.xml patch0.xml
cd ..
```

### 6. Configure CDT

The Configuration Data Table (CDT) is device-specific initialization data. See
[references/cdt-by-device.md](references/cdt-by-device.md) for the selection
steps:

- **IQ-X7181 / IQ-X5121**: download a separate CDT tarball from CodeLinaro and
  flash it with `qdl` before the main image.
- **All other kits**: multiple CDT binaries ship inside the qcomflash bundle;
  copy the correct one over `cdt.bin`.

### 7. Flash

Run `qdl` with the storage type for the board (from step 0):

```bash  UFS (IQ-9075-EVK, IQ-8275-EVK, QCS6490)
qdl --storage ufs prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

```bash  EMMC (IQ-615-EVK)
qdl --storage emmc prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

```bash  UFS/SPINOR (IQ-X7181-EVK, IQ-X5121-EVK)
cd spinor
qdl --storage spinor xbl_s_devprg_ns.melf rawprogram*.xml patch*.xml
cd ..
qdl --storage ufs xbl_s_devprg_ns.melf rawprogram*.xml patch*.xml
```

With **multiple boards** connected, select one by serial (obtained via
`lsusb -v -d 05c6:9008 | grep iSerial`):

```bash
qdl --storage ufs --serial=<SERIAL> prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

A healthy run starts with the firehose handshake
(`HELLO version: 0x2 ...`) followed by per-partition program/patch
progress. Report the qdl exit status and the last lines of output.

### 8. Boot and hand off

After a successful flash, power-cycle the board (or exit EDL per the board's
guide) so it boots the new image, then validate the boot with the
`qcom-boot-validate` skill.

## Notes / gotchas

- A failed or interrupted `qdl` leaves the board in EDL mode — the recovery
  is simply to re-run the qdl command; no re-arming is needed.
- `qdl` "Waiting for EDL device" that never completes usually means
  ModemManager stole the device, the udev rule is missing, or the board
  dropped out of EDL (power-cycle back into EDL and retry).
- Never mix bundles: `rawprogram*.xml` describes the partition layout for
  exactly the machine the image was built for; flashing another board's
  bundle can brick storage contents (EDL itself remains available for
  recovery).
- This flow writes the full partition table and images. If the user only
  wants to update a kernel or rootfs partition, confirm intent before
  flashing everything.
