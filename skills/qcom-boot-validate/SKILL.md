---
name: qcom-boot-validate
description: >-
  Validate that a Qualcomm Linux board boots to a working login shell by
  watching its serial console: wait for the login prompt, log in with the
  image's default credentials, and check uname, /etc/os-release (incl.
  BUILD_ID) and systemd state, reporting BOOT-VALIDATION: PASS/FAIL. Use
  after flashing, when asked to "validate the board boots", "check the
  board over serial", "did the new image come up", or "watch the boot
  console". Needs the serial console attached to this host (or reachable
  over ssh). Do NOT use for flashing (see qcom-flash-qdl) or for
  diagnosing a healthy-but-degraded system.
metadata:
  version: "0.1"
---

# Validate a board boots over the serial console

Drives the board's serial console to prove a boot actually reached a usable
shell — the natural follow-up to `qcom-flash-qdl`. Everything is done by
`scripts/boot-validate.py` (paths relative to this skill's directory).

## Prerequisites

- The board's debug UART attached to a host you can run Python on, at
  115200 baud (check `dmesg | grep tty` for the device, e.g. `/dev/ttyUSB0`).
- `python3` with `pyserial` on that host; the user in the `dialout` group
  (or equivalent) so the port opens without root.
- Nothing else holding the serial port (close `screen`/`picocom`/`minicom`
  sessions first — the validator warns if it reads no output).
- The image's login credentials (see matrix below).

## Credentials matrix

| Image | username | password |
|---|---|---|
| nodistro `core-image-base` (debug image) | `root` | empty |
| qcom-distro images (`qcom-console-image`, ...) | `root` | `oelinux123` |

## Usage

Local serial port:

```bash
python3 scripts/boot-validate.py --port /dev/ttyUSB0 --password oelinux123 \
    [--timeout 300] [--power-cycle-cmd '<host command>'] [--logfile PATH]
```

Serial port on a remote host (nothing is copied to it — the script is piped
over ssh):

```bash
ssh <host> "python3 - --port /dev/ttyUSB0 --password oelinux123" \
    < scripts/boot-validate.py
```

- With no `--power-cycle-cmd`, the script watches the console and tells you
  to power-cycle/reset the board — start it right before (or immediately
  after) resetting, e.g. right after a flash completes.
- `--power-cycle-cmd` runs a host command once at startup for setups that
  can drive board power programmatically (lab automation, smart PDU). Keep
  site-specific automation in that command, not in this skill.
- Exit code `0` on `BOOT-VALIDATION: PASS`, non-zero on failure. The full
  console capture is mirrored to the log file (default
  `/tmp/qcom-boot-validate-<timestamp>.log`) for evidence.

## How validation works

1. Optionally power-cycle, then discard any stale console output so an old
   login prompt cannot satisfy the check.
2. Wait (default 300 s) for a fresh `login:` prompt.
3. Log in; handle both password and no-password images, and wait for the
   shell to actually be ready before typing (early commands get swallowed
   during session setup).
4. Run fenced sanity checks: `uname -a`, `PRETTY_NAME`/`VERSION`/`BUILD_ID`
   from `/etc/os-release`, `systemctl is-system-running`.
5. Verdict: `PASS` for `running`/`starting`; `PASS(warn)` for `degraded`
   (booted, but some unit failed) or non-systemd images; `FAIL` otherwise,
   with the last 40 console lines printed for triage.

Compare the reported `BUILD_ID` with the build you just flashed — a PASS on
a stale image is not a validation of the new one.

## Notes / gotchas

- "no output at all" almost always means the wrong tty device, a console
  muxed away by DIP switches, or another process holding the port.
- OE images enable bash's semantic prompt escapes; the validator strips
  ANSI/OSC sequences before parsing, so don't be surprised that the raw log
  file looks noisier than the parsed report.
- `degraded` is reported as PASS(warn) on purpose: the board booted. Chase
  the failing units separately (`systemctl --failed`) rather than treating
  the boot as broken.
- The script is read-only on the target apart from logging in and running
  the three sanity commands; it logs out (`exit`) when done.
