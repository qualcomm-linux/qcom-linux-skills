---
name: qcom-device-info
description: >-
  Print a concise summary of the Qualcomm Linux device this runs on: board
  model and SoC (device tree + socinfo), OS release including BUILD_ID,
  kernel, uptime and systemd state. On request, produce a full release
  report instead: firmware inventory from qcom_socinfo, UEFI version from
  the EFI loader variables, Yocto layer revisions from /etc/buildinfo,
  consistency findings and a release fingerprint — the QLI 2.x Ver_Info.txt
  replacement. Use when asked to "print device info", "what board/SoC is
  this", "which image/build is this board running", "release report", "what
  firmware is on this board", "which meta-qcom commit built this image",
  "reconstruct Ver_Info", or to capture a baseline before tests. Read-only;
  runs on the booted target, or offline on a capture someone pasted. Do NOT
  use for health diagnostics or host-side build questions (see
  qcom-yocto-build-image). This is an example skill and the authoring
  template for this catalog.
metadata:
  version: "0.2"
---

# qcom-device-info

Identifies the Qualcomm Linux device this skill runs on, in two modes:

- a **quick summary** — board, SoC, OS release, kernel, uptime, systemd
  state — which is what "print device info" should produce;
- a **release report** — the above plus the firmware inventory, the Yocto
  layer revisions the image was built from, consistency findings and a
  release fingerprint. QLI 1.x answered these questions with a single
  `Ver_Info.txt`; QLI 2.x has no such file, so the report reconstructs the
  answer by correlating four separate sources.

This skill is also the reference example for the `qcom-linux-skills`
catalog: it shows the expected frontmatter, the section layout and the
reporting style, and it uses all three parts of the skill layout
(`SKILL.md`, `scripts/`, `references/`). All inspection is read-only.

## When to use

- Verifying that a freshly flashed board runs the expected image
  (`BUILD_ID`, kernel version).
- Capturing a baseline of the software stack before a test run or in a bug
  report.
- Answering "which firmware is on this board?" or "which meta-qcom commit
  built this image?" for a support or triage ticket.
- Deciding whether an image can be reproduced from git, or is a local build
  with uncommitted layer changes.
- Analyzing file dumps someone else pasted from a board you cannot reach.

## Prerequisites

- For the on-device modes: running on the Qualcomm Linux target (serial
  console or ssh), not the host PC.
- Standard CLIs only: `cat`, `tr`, `uname`, `uptime`. `systemctl`,
  `mountpoint` and `iconv` are optional — every step falls back gracefully.
- The firmware inventory reads debugfs, so it needs **root** and debugfs
  mounted on `/sys/kernel/debug`. Everything else, including the UEFI
  firmware version, works as an ordinary user.
- `scripts/qcom-release-report.py` runs on the host and needs only Python 3
  from the standard library. Script paths below are relative to this
  skill's directory.

## Instructions

### Quick summary (default)

Run each step in order and print the captured values in the report shown
under [Output format](#output-format).

1. **Capture** the board model and **validate** this is a Qualcomm target —
   exit early otherwise:

   ```bash
   # Device-tree strings are NUL-terminated, so strip NULs before printing.
   # Keep 2>/dev/null BEFORE the input redirect: it must silence the shell's
   # own error when /proc/device-tree is absent (e.g. on an x86 host).
   model=$(tr -d '\0' 2>/dev/null < /proc/device-tree/model)
   compatible=$(tr '\0' ' ' 2>/dev/null < /proc/device-tree/compatible)
   case "$compatible" in
     *qcom,*) ;;
     *) echo "Not running on a Qualcomm target (compatible: '${compatible:-unknown}')"; exit 1 ;;
   esac
   echo "$model"
   echo "$compatible"
   ```

2. **Read** the SoC identity from socinfo (missing files are fine — print
   what exists):

   ```bash
   for f in machine family soc_id revision serial_number; do
     [ -r "/sys/devices/soc0/$f" ] && echo "$f: $(cat /sys/devices/soc0/$f)"
   done
   ```

3. **Print** the OS release, including the image `BUILD_ID` when present:

   ```bash
   grep -E '^(PRETTY_NAME|VERSION|BUILD_ID)=' /etc/os-release 2>/dev/null \
     || echo "no /etc/os-release"
   ```

4. **Print** the kernel version and uptime:

   ```bash
   uname -a
   uptime -p 2>/dev/null || uptime
   ```

5. **Print** the overall system state (optional, systemd images only):

   ```bash
   # is-system-running exits non-zero for every state except "running",
   # so key off the output - otherwise "degraded" gets reported as absent.
   state=$(systemctl is-system-running 2>/dev/null)
   echo "${state:-systemctl not available}"
   ```

Stop here unless the user asked for firmware, provenance or a support
report.

### Release report (on request)

Preferred path — one capture, one report:

```bash
# on the target (as root, for the firmware inventory)
bash scripts/qcom-release-collect.sh > capture.txt

# or from a host that can reach it
ssh <target> 'bash -s' < scripts/qcom-release-collect.sh > capture.txt

# then, anywhere
python3 scripts/qcom-release-report.py capture.txt
```

Failures here are loud, not silent: ssh reports an unreachable target on
stderr and exits non-zero, an unreadable script file fails in the shell
before anything runs, and the reporter rejects an empty capture outright. A
complete capture ends with a `COLLECTOR` section — if that is missing after
a remote run, the transfer was cut short, so re-run rather than reporting on
it, since the lost sources would otherwise show up merely as "not
collected".

`qcom-release-collect.sh` is read-only and never aborts on a missing
source — it records `<unavailable: reason>` so the report can tell "absent"
apart from "not collected". It exits 2 only when the device tree is not a
Qualcomm target (`--force` overrides). `qcom-release-report.py` also
accepts `--fingerprint` for just the one-line fingerprint and `--json` for
machine-readable output.

When the only access is a serial console and the script cannot be
transferred, gather the same four sources by hand and read them per the
rules in [references/release-sources.md](references/release-sources.md) —
it documents each file's format and the traps that produce wrong answers:

6. **Build provenance** — the Yocto layers the image was built from:

   ```bash
   cat /etc/buildinfo 2>/dev/null || echo "no /etc/buildinfo"
   ```

   Layer names are checkout-directory basenames: **`repo` is meta-qcom**
   and **`meta` is openembedded-core**. A trailing `-- modified` means that
   layer was dirty at build time; a `patched-<sha>` branch means kas
   applied patches.

7. **Firmware inventory** — per-subsystem build strings (root only):

   ```bash
   for f in /sys/kernel/debug/qcom_socinfo/*/name; do
     v=$(cat "$f" 2>/dev/null); [ -n "$v" ] && echo "${f%/name}: ${v#*:}"
   done
   ```

   Strip the leading `NN:` subsystem index, and skip empty entries — most
   subsystems are empty on a healthy board.

8. **Boot firmware from EFI** — works without root, and is the fallback
   when socinfo cannot be read:

   ```bash
   for v in /sys/firmware/efi/efivars/LoaderFirmwareInfo-* \
            /sys/firmware/efi/efivars/LoaderFirmwareType-*; do
     [ -r "$v" ] && echo "${v##*/}: $(tail -c +5 "$v" | iconv -f UTF-16LE -t UTF-8)"
   done
   ```

9. **Correlate and assess.** Decode `BUILD_ID`, build the
   `RELEASE_FINGERPRINT`, run the consistency checks and state the
   confidence, all as specified in
   [references/support-report.md](references/support-report.md) — that file
   carries the report skeleton, the finding table and the confidence model.

### Offline analysis

When someone pastes file contents from a board you cannot reach, save them
into a capture and report on it — no hardware needed:

```bash
cat > capture.txt <<'CAPTURE'
=== SECTION: OS_RELEASE ===
<paste /etc/os-release>

=== SECTION: BUILDINFO ===
<paste /etc/buildinfo>

=== SECTION: SOCINFO_NAMES ===
<paste "cat /sys/kernel/debug/qcom_socinfo/*/name", one "subsystem = value" per line>
CAPTURE

python3 scripts/qcom-release-report.py capture.txt
```

Only the sections you have are needed; the report names the missing ones
and lowers its confidence accordingly. Say plainly which sources were
available, and ask for a full `qcom-release-collect.sh` capture when the
answer matters.

## Output format

Quick summary — a short report, one line each where possible:

```text
Model:        <device-tree model string>
Compatible:   <device-tree compatible list>
SoC:          <socinfo machine / family / soc_id / revision>
OS release:   <PRETTY_NAME, VERSION, BUILD_ID>
Kernel:       <uname -a>
Uptime:       <uptime -p>
System state: <systemctl is-system-running>
```

Release report — the sections below, in this order, with unavailable values
printed as `<unavailable>` rather than omitted:

```text
# Device Identification    model, SoC, QLI release, BUILD_ID + decode, image type, kernel
# Firmware Versions        per-subsystem table, then the EFI loader values
# Build Provenance         DISTRO/DISTRO_VERSION, then the layer table
# Release Correlation      RELEASE_FINGERPRINT
# Key Findings             consistency checks, most severe first
# Support Assessment       per-question confidence + which sources were present
# Overall Confidence       HIGH / MEDIUM / LOW
```

## Example

Quick summary on an RB3 Gen 2 running a qcom-distro console image:

```text
Model:        Qualcomm Technologies, Inc. Robotics RB3gen2
Compatible:   qcom,qcs6490-rb3gen2 qcom,qcm6490
SoC:          QCM6490 / Snapdragon / 497 / 1.0
OS release:   PRETTY_NAME="Qualcomm Linux 1.5" BUILD_ID="20260708..."
Kernel:       Linux qcs6490-rb3gen2-core-kit 7.1.0 ... aarch64
Uptime:       up 12 minutes
System state: running
```

Release report excerpt from a qcs9100-ride-sx:

```text
Build ID:     32085063241-1 (meta-qcom CI run 32085063241 attempt 1)
              https://github.com/qualcomm-linux/meta-qcom/actions/runs/32085063241
Image type:   snapshot/CI build

| Subsystem | Component | Build string                            | Platform         |
|-----------|-----------|-----------------------------------------|------------------|
| boot      | BOOT      | BOOT.MXF.1.0.c1-00532-KODIAKLA-1        | KODIAKLA         |
| tz        | TZ        | TZ.XF.5.29.1-00171.1-KODIAKAAAAANAAZT-1 | KODIAKAAAAANAAZT |
| adsp      | DSP       | DSP.AT.1.0.1-00201-LEMANS-2             | LEMANS           |

| Layer                    | Branch  | Revision   | Flags       |
|--------------------------|---------|------------|-------------|
| repo (meta-qcom)         | master  | 2c63ba21.. | modified    |
| meta-qcom-distro         | main    | fc472762.. | -           |
| meta (openembedded-core) | patched-d51c6e87.. | f527b723.. | kas-patched |

RELEASE_FINGERPRINT
  QLI       = 2.99-snapshot-f527b723                   # os-release VERSION_ID
  BUILD     = 32085063241-1                            # os-release BUILD_ID
  META_QCOM = 2c63ba21                                 # buildinfo 'repo' line
  BOOT      = BOOT.MXF.1.0.c1-00532-KODIAKLA-1         # socinfo boot/name
  UEFI      = 24614.1796                               # EFI LoaderFirmwareInfo

- [high] Layer(s) meta-qcom were dirty at build time (' -- modified'); the
  image cannot be reproduced from git alone.

Overall confidence: MEDIUM
```

Note that `BOOT`/`TZ` report `KODIAK*` while the DSPs report `LEMANS`: that
is the normal state of a LeMans board, not a finding.

## Error handling

Each command falls back to a clearly labeled "not available" string if the
underlying file or binary is missing — the report never aborts midway. If
`/proc/device-tree/compatible` does not contain a `qcom,` entry, exit early
with a clear "not running on a Qualcomm target" message instead of printing
misleading info.

For the release report, distinguish three states and say which one applies:

- **present** — collected and parsed.
- **not collected** — the capture has no such section. Common with pasted
  offline captures. Recoverable: ask for a full
  `qcom-release-collect.sh` capture.
- **not present** — the source was looked for and was missing or
  unreadable on the target, with a reason (no root, debugfs not mounted, or
  no `/etc/buildinfo` on an image not built with `image-buildinfo`). That is
  itself a reportable finding.

Never present `not collected` as though the file were absent from the
board, and never present a missing firmware inventory as a firmware fault.

## Notes

- Read-only. Do not change any system state, install packages, or modify
  files.
- `systemctl is-system-running` may report `degraded`; that still means the
  board booted — report it verbatim rather than treating it as a failure
  (use a diagnostic skill to chase the failed units).
- The snapshot SHA in `VERSION_ID` is openembedded-core's revision, not
  meta-qcom's. Quote meta-qcom's commit from the `repo` line in
  `/etc/buildinfo` instead.
- `/etc/version` is a reproducible-build constant (`20180309123456`), not a
  build date, and `/etc/lsb-release` only mirrors `/etc/os-release`.
