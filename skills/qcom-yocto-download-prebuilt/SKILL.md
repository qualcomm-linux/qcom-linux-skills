---
name: qcom-yocto-download-prebuilt
description: >-
  Download prebuilt Qualcomm Linux (Yocto/QLI) flashable images from the
  public CodeLinaro archive for supported boards (RB3 Gen 2, IQ-615,
  IQ-8275, IQ-9075, IQ-X5121, IQ-X7181), picking release, distro
  (qcom-distro / qcom-distro-sota) and image variant, then staging the
  extracted flashables for QDL. Use when asked to "download a prebuilt
  image", "get the QLI image for the IQ-9075 / RB3 Gen 2", "fetch the
  multimedia image", or "get flashable binaries without building". Do NOT
  use for building images yourself (see qcom-yocto-build-image), for
  flashing (see qcom-flash-qdl), or for Ubuntu/Debian images.
metadata:
  version: "0.1"
---

# Download prebuilt Qualcomm Linux images

Fetches ready-to-flash Qualcomm Linux (QLI) images published on CodeLinaro,
following the Dragonwing "Obtain Prebuilt Images" flash guide
(<https://dragonwingdocs.qualcomm.com/Key-Documents/Flash-Guide/obtain-prebuilts.md>).
No login is required; artifacts are public.

## URL scheme

```text
https://artifacts.codelinaro.org/artifactory/qli-ci/flashable-binaries/meta-qcom/[<distro>/]<machine>/<release>-<image>.zip
```

| Field | Values |
|---|---|
| `<distro>` | omit the path segment for `qcom-distro` (default); `qcom-distro-sota/` for the OTA-enabled variant |
| `<machine>` | `rb3gen2-core-kit`, `iq-615-evk`, `iq-8275-evk`, `iq-9075-evk`, `iq-x5121`, `iq-x7181` |
| `<release>` | `qli-2.0` (current at time of writing) |
| `<image>` | `qcom-multimedia-image` or `qcom-multimedia-proprietary-image` |

Examples:

```text
.../meta-qcom/rb3gen2-core-kit/qli-2.0-qcom-multimedia-image.zip
.../meta-qcom/qcom-distro-sota/iq-9075-evk/qli-2.0-qcom-multimedia-proprietary-image.zip
```

Browse <https://artifacts.codelinaro.org/ui/native/qli-ci/flashable-binaries/meta-qcom/>
to discover newer releases or additional machines before assuming a URL —
the machine directory names do not always match meta-qcom `MACHINE` names
exactly (e.g. `iq-x5121` here vs the `iq-x5121-evk` machine).

## Procedure

### 1. Pick the artifact

Ask/confirm three choices: **board**, **distro** (`qcom-distro` unless the
user wants OTA/SOTA support), and **image** (`qcom-multimedia-image` unless
the user explicitly wants the proprietary variant — it contains
license-restricted binaries; the user is responsible for accepting the
applicable license terms).

### 2. Download

The zips are large (roughly 1–2 GB), so download resumably and confirm
size before unpacking:

```bash
curl -fLO --retry 3 -C - <url>     # or: wget -c <url>
unzip -t <file>.zip >/dev/null && echo "archive OK"
```

### 3. Extract and locate the flashables

```bash
unzip -q <file>.zip -d <dest>
ls <dest>/*/images/<machine>/<image>-<machine>/
```

The flashable set is the usual QDL bundle: `prog_firehose_ddr.elf`,
`rawprogram*.xml`, `patch*.xml`, plus the partition images. Report the
extracted path, the release version, and the total size.

### 4. Hand off to flashing

Flash with the `qcom-flash-qdl` skill from the extracted directory. Notes
from the per-board Dragonwing flash guides:

- These prebuilt bundles target UFS storage; the documented invocation uses
  `qdl --storage ufs prog_firehose_ddr.elf rawprogram*.xml patch*.xml`.
- Some boards need one-time provisioning or extra firmware before the first
  OS flash (e.g. the IQ-9075 EVK: UFS `provision.zip` from the
  `codelinaro-le/Qualcomm_Linux/<SoC>` archive and SAIL firmware flashed to
  SPI-NOR). Follow the board's "Flash using QDL" page on
  <https://dragonwingdocs.qualcomm.com> for these steps — do not improvise
  provisioning XMLs.

## Notes

- Prebuilt images exist only for the boards/images listed by the flash
  guide; for any other machine, distro or image (e.g. `qcom-console-image`,
  a `nodistro` build, or a different kernel), build it with the
  `qcom-yocto-build-image` skill.
- An embedded SDK (eSDK) matching the release is published under the
  `qcom-armv8a` directory of the same archive for application developers
  who need the toolchain without a full Yocto build.
- Downloads come from Qualcomm's QLI CI archive on CodeLinaro; artifact
  layout may change between releases — when a URL 404s, re-check the
  browsable index and the flash guide rather than guessing.
