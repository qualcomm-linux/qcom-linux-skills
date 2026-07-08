---
name: qcom-device-info
description: >-
  Print a concise summary of the Qualcomm Linux device this runs on: board
  model and SoC (device tree + socinfo), OS release including BUILD_ID,
  kernel version, uptime and systemd state. Use when asked to "print device
  info", "what board/SoC is this", "which image/build is this board
  running", or to capture a baseline before tests. Read-only, runs on the
  booted target (not the build host). Do NOT use for health diagnostics or
  for host-side build questions. This is an example skill and the authoring
  template for this catalog.
---

# qcom-device-info

Prints a concise summary of the Qualcomm Linux device this skill runs on.

This skill is intended as a reference example for the `qcom-linux-skills`
catalog: it shows the expected frontmatter, section layout, and reporting
style. It runs on the booted target (not the host PC) and performs read-only
inspection — useful as a baseline capture before running tests or reporting
a bug.

## When to use

- Verifying that a freshly flashed board runs the expected image
  (`BUILD_ID`, kernel version).
- Capturing a baseline of the software stack before a test run or in a bug
  report.

## Prerequisites

- Running on the Qualcomm Linux target (serial console or ssh), not the
  host PC.
- Standard CLIs only: `cat`, `tr`, `uname`, `uptime`. `systemctl` is
  optional — the skill falls back gracefully without it.

## Instructions

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
   systemctl is-system-running 2>/dev/null || echo "systemctl not available"
   ```

## Output format

Print a short report with these sections, one line each where possible:

```text
Model:        <device-tree model string>
Compatible:   <device-tree compatible list>
SoC:          <socinfo machine / family / soc_id / revision>
OS release:   <PRETTY_NAME, VERSION, BUILD_ID>
Kernel:       <uname -a>
Uptime:       <uptime -p>
System state: <systemctl is-system-running>
```

## Example

Example output on an RB3 Gen 2 running a qcom-distro console image:

```text
Model:        Qualcomm Technologies, Inc. Robotics RB3gen2
Compatible:   qcom,qcs6490-rb3gen2 qcom,qcm6490
SoC:          QCM6490 / Snapdragon / 497 / 1.0
OS release:   PRETTY_NAME="Qualcomm Linux 1.5" BUILD_ID="20260708..."
Kernel:       Linux qcs6490-rb3gen2-core-kit 7.1.0 ... aarch64
Uptime:       up 12 minutes
System state: running
```

## Error handling

Each command falls back to a clearly labeled "not available" string if the
underlying file or binary is missing — the report never aborts midway. If
`/proc/device-tree/compatible` does not contain a `qcom,` entry, exit early
with a clear "not running on a Qualcomm target" message instead of printing
misleading info.

## Notes

- Read-only. Do not change any system state, install packages, or modify
  files.
- `systemctl is-system-running` may report `degraded`; that still means the
  board booted — report it verbatim rather than treating it as a failure
  (use a diagnostic skill to chase the failed units).
