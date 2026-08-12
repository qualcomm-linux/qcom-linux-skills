---
name: qcom-device-diagnostic
description: >-
  Capture a read-only health snapshot of a booted Qualcomm Linux target and
  flag likely problems: remoteproc/firmware state, thermal zones, failed
  systemd units, recent dmesg errors, and storage/memory pressure. Use when
  asked to "run device diagnostics", "why is this board unhealthy", "check
  remoteproc/thermal/failed units", or to attach a health report to a bug.
  Runs on the booted target (not the build host). Do NOT use for a plain
  identity summary (see qcom-device-info), for triaging a board that never
  reaches a shell (see qcom-boot-validate), or for host-side build issues.
---

# qcom-device-diagnostic

Collects a read-only health snapshot of the Qualcomm Linux device this skill
runs on and highlights the subsystems most likely to explain a misbehaving
board: co-processor (remoteproc) firmware, thermal state, failed systemd
units, kernel error messages, and storage/memory pressure.

Like [qcom-device-info](../qcom-device-info/SKILL.md) this runs on the booted
target over serial or ssh and never changes system state. Where
`qcom-device-info` answers "what is this board", this skill answers "is this
board healthy, and if not, where does it hurt".

## When to use

- A board boots but misbehaves (a peripheral is dead, it runs hot, a service
  keeps restarting) and you need a structured first-pass triage.
- Capturing an evidence snapshot to attach to a bug report before rebooting
  or reflashing (which would destroy the current kernel log).

## Prerequisites

- Running on the Qualcomm Linux target (serial console or ssh), not the host
  PC. The [qcom-device-info](../qcom-device-info/SKILL.md) checks apply here
  too — the script exits early if `/proc/device-tree/compatible` has no
  `qcom,` entry.
- Standard CLIs only: `cat`, `grep`, `dmesg`, `free`, `df`. `systemctl` is
  optional — the script degrades gracefully when it is absent (non-systemd
  images).
- `dmesg` must be readable by the current user. On images that set
  `kernel.dmesg_restrict=1` this means running as root; the script reports
  that it could not read the ring buffer rather than failing.

## Instructions

Run the helper script and read its report. It is read-only and prints a
per-section `PASS`/`WARN`/`FAIL` summary at the end.

```bash
scripts/device-diagnostic.sh
```

To also write the full snapshot to a file for a bug report, pass a path:

```bash
scripts/device-diagnostic.sh --out /tmp/diag-$(date +%Y%m%d-%H%M%S).log
```

The script performs these checks in order; each is independent so a missing
subsystem never aborts the run:

1. **Guard** — confirm this is a Qualcomm target, exit early otherwise.
2. **remoteproc** — list every `/sys/class/remoteproc/remoteproc*` and its
   `state`; anything not `running` is a `WARN` (co-processors such as the
   ADSP/CDSP/modem should be `running` on a healthy board).
3. **thermal** — read each `/sys/class/thermal/thermal_zone*/temp` and
   compare against the zone's trip points; a zone above its passive trip is
   a `WARN`, above critical is a `FAIL`.
4. **systemd** — list failed units (`systemctl --failed`); any failed unit
   is a `WARN`.
5. **dmesg** — count kernel errors since boot and show the most recent few.
6. **storage/memory** — flag any mounted filesystem over 90% full and low
   available memory.

## Output format

The script prints one block per section followed by a summary table:

```text
== remoteproc ==
remoteproc0 (700b0000.remoteproc / adsp): running
remoteproc1 (b00000.remoteproc / cdsp):   running
...
== SUMMARY ==
remoteproc:   PASS
thermal:      PASS
systemd:      WARN (1 failed unit: qcom-foo.service)
dmesg:        WARN (3 errors)
storage:      PASS
memory:       PASS
OVERALL:      WARN
```

`OVERALL` is `FAIL` if any section failed, else `WARN` if any warned, else
`PASS`.

## Notes

- Read-only. The script never restarts a remoteproc, clears the dmesg ring,
  or touches any unit — it only reports. Acting on the findings (restarting a
  crashed remoteproc, chasing a failed unit) is deliberately left to the
  operator.
- `systemctl is-system-running` reporting `degraded` is expected on many
  images and is surfaced as `WARN`, not `FAIL`: the board booted.
- To act on remoteproc firmware crashes you usually need the kernel log lines
  the dmesg section surfaces (`remoteproc ... crash`) plus the firmware build
  the image shipped — see [references/subsystems.md](references/subsystems.md).
