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

- **qdl** — obtained via one of these sources (checked in order):
  1. **Qualcomm IDE VS Code extension** (preferred, no download needed; only
     applicable if Qualcomm IDE is installed): the extension bundles prebuilt
     qdl binaries for all platforms. Locate them based on your OS:

     **Linux / WSL (remote extension host):**

     ```bash
     ls ~/.vscode-server/extensions/qualcomm.qualcomm-ide*/build/extension/tools/qdl/
     # or for local VS Code installs:
     ls ~/.vscode/extensions/qualcomm.qualcomm-ide*/build/extension/tools/qdl/
     ```

     Use `QDL_Linux_x64/qdl` or `QDL_Linux_ARM64/qdl` depending on your arch.

     **macOS:**

     ```bash
     ls ~/.vscode/extensions/qualcomm.qualcomm-ide*/build/extension/tools/qdl/
     ```

     Use `QDL_Mac_ARM64/qdl` (Apple Silicon) or `QDL_Mac_x64/qdl` (Intel).

     **Windows (PowerShell):**

     ```powershell
     ls "$env:USERPROFILE\.vscode\extensions\qualcomm.qualcomm-ide*\build\extension\tools\qdl\"
     ```

     Use `QDL_Win_x64\qdl.exe` or `QDL_Win_ARM64\qdl.exe`.

  2. **Download from upstream linux-msm/qdl releases** (if the extension is
     absent): official prebuilt binaries are published at
     `https://github.com/linux-msm/qdl/releases` (e.g. the `v2.8` release).
     Download the archive for your platform and extract it. On Linux/macOS run
     `chmod +x qdl` after extracting.

  3. **System PATH**: if `qdl` (or `qdl.exe` on Windows) is already on PATH
     it can be used directly.

- **USB access / host OS setup** (skip the steps that do not apply to your OS):
  - **Linux**: add a udev rule for VID:PID `05c6:9008` so qdl can access the
    EDL device as a non-root user (see "Update udev rules" in the Qualcomm
    flashing docs). Without it, prefix each `qdl` command with `sudo`.
    Also stop ModemManager if it is running — it will grab the EDL device:

    ```bash
    systemctl is-active ModemManager && sudo systemctl stop ModemManager
    ```

  - **WSL**: USB passthrough is required. Attach the EDL device with
    `usbipd` from a Windows administrator shell before running qdl in WSL:

    ```powershell
    # List devices — find the one with VID 05c6 PID 9008
    usbipd list
    usbipd bind --busid <BUSID>
    usbipd attach --wsl --busid <BUSID>
    ```

    The udev rule and ModemManager steps above still apply inside WSL.

  - **macOS**: no udev or ModemManager. qdl needs raw USB access — run it
    with `sudo` or grant it via a kernel extension/entitlement if your
    security policy requires.

  - **Windows**: no udev. Run `qdl.exe` from a Command Prompt or PowerShell
    with administrator privileges if required by your USB driver setup.

- The flash bundle: a `*.qcomflash` directory or archive from the build deploy
  dir or prebuilt download, containing `prog_firehose_ddr.elf`,
  `rawprogram*.xml`, and `patch*.xml`.

## Procedure

> **Invoking qdl**: if the binary is not on PATH, replace bare `qdl` in all
> commands below with the full path to the binary located in the Prerequisites
> step (the path printed by the `ls` command for your OS).
>
> **PowerShell note**: PowerShell requires the `&` call operator to invoke an
> executable by path (e.g. `& "C:\path\to\qdl.exe" --storage ufs ...`). Also,
> PowerShell does not expand wildcards in command arguments the way bash does —
> replace `rawprogram*.xml` and `patch*.xml` with the explicit file list, or
> use `(Get-Item rawprogram*.xml)` and `(Get-Item patch*.xml)` to expand them
> inline:
>
> ```powershell
> & ".\qdl.exe" --storage ufs prog_firehose_ddr.elf (Get-Item rawprogram*.xml) (Get-Item patch*.xml)
> ```

### 0. Identify device and storage type

Ask the user which board they are flashing if not already stated. This
determines storage type, whether UFS provisioning is needed, whether SAIL must
be flashed, and which CDT to use.

See [references/storage-types.md](references/storage-types.md) for the default
storage type per board. Surface the storage type early — the `qdl` command and
several later steps depend on it.

### 1. Stage the flash bundle

**Prebuilt image (zip archive):**

Linux/macOS/WSL:

```bash
unzip <prebuilt-image>.zip
cd <unzipped-image-directory>/images/<machine>/<image>-<machine>
```

Windows (PowerShell):

```powershell
Expand-Archive <prebuilt-image>.zip -DestinationPath .
cd <unzipped-image-directory>\images\<machine>\<image>-<machine>
```

**Compiled image (already in deploy dir):**

```bash
cd build/tmp/deploy/images/<machine>/<image>-<machine>.rootfs.qcomflash
```

Confirm the bundle is intact — these files must all exist:

Linux/macOS/WSL:

```bash
ls prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

Windows (PowerShell):

```powershell
ls prog_firehose_ddr.elf, rawprogram*.xml, patch*.xml
```

All subsequent commands run from this directory unless stated otherwise.

### 2. Open the serial console (recommended)

Connect the debug UART and open it at 115200 baud so flashing and the first
boot can be observed.

**Linux/WSL** — find the device with `dmesg | grep tty` (e.g. `/dev/ttyUSB0`):

> **WSL**: the debug UART is a separate USB device from the EDL interface.
> Attach it in WSL before attempting to open it — from a Windows administrator
> shell, identify the UART's bus ID with `usbipd list` and attach it:
>
> ```powershell
> usbipd bind --busid <UART-BUSID>
> usbipd attach --wsl --busid <UART-BUSID>
> ```

```bash
picocom -b 115200 /dev/ttyUSB0
```

**macOS** — find the device with `ls /dev/tty.usbserial*` or `ls /dev/tty.SLAB_*`:

```bash
screen /dev/tty.usbserial-XXXX 115200
```

**Windows** — find the COM port in Device Manager under "Ports (COM & LPT)",
then use a serial-capable client such as PuTTY or TeraTerm at 115200 baud.

### 3. Put the board in EDL mode

See [references/entering-edl.md](references/entering-edl.md) for per-board
instructions (e.g. RB3 Gen 2: hold `F_DL` while applying power). Then
confirm the host sees the EDL device:

**Linux/WSL:**

```bash
lsusb -d 05c6:9008
```

**macOS:**

```bash
system_profiler SPUSBDataType | grep -A5 "9008"
```

**Windows (PowerShell):**

```powershell
pnputil /enum-devices /connected | Select-String "VID_05C6&PID_9008" -Context 3
```

Alternatively, open Device Manager and look for "Qualcomm HS-USB QDLoader 9008"
under "Ports (COM & LPT)" or "Universal Serial Bus devices".

No match means the board is not in EDL — do not proceed; re-check the
button/switch sequence and the USB cable.

> **WSL note**: if `lsusb` shows the device on the Windows side but not in
> WSL, the USB device is not attached — run the `usbipd attach` command from
> the Prerequisites step.

### 4. Provision UFS

> Skip this step for **IQ-615-EVK** (EMMC storage).

UFS must be provisioned before the first flash, and re-provisioned if the LUN
layout has changed. It is safe to re-run when unsure. See
[references/provision-ufs.md](references/provision-ufs.md) for the per-board
download URL and `qdl` command.

The device reboots after provisioning. Confirm it is back in EDL using the
same OS-appropriate command from step 3 before proceeding.

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

```bash UFS (IQ-9075-EVK, IQ-8275-EVK, QCS6490)
qdl --storage ufs prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

```bash EMMC (IQ-615-EVK)
qdl --storage emmc prog_firehose_ddr.elf rawprogram*.xml patch*.xml
```

```bash UFS/SPINOR (IQ-X7181-EVK, IQ-X5121-EVK)
cd spinor
qdl --storage spinor xbl_s_devprg_ns.melf rawprogram*.xml patch*.xml
cd ..
qdl --storage ufs xbl_s_devprg_ns.melf rawprogram*.xml patch*.xml
```

With **multiple boards** connected, select one by serial. Obtain the serial
number with the OS-appropriate command:

Linux/WSL:

```bash
lsusb -v -d 05c6:9008 | grep iSerial
```

macOS:

```bash
system_profiler SPUSBDataType | grep -A10 "9008" | grep "Serial Number"
```

Windows (PowerShell):

```powershell
pnputil /enum-devices /connected | Select-String "VID_05C6&PID_9008" -Context 5
```

Then pass it to qdl:

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
- `qdl` "Waiting for EDL device" that never completes:
  - **Linux/WSL**: ModemManager may have stolen the device, the udev rule may
    be missing, or the board dropped out of EDL. On WSL, also check that the
    USB device is still attached via `usbipd`.
  - **All OSes**: power-cycle the board back into EDL and retry.
- Never mix bundles: `rawprogram*.xml` describes the partition layout for
  exactly the machine the image was built for; flashing another board's
  bundle can brick storage contents (EDL itself remains available for
  recovery).
- This flow writes the full partition table and images. If the user only
  wants to update a kernel or rootfs partition, confirm intent before
  flashing everything.
