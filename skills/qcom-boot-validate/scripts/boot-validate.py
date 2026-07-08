#!/usr/bin/env python3
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
"""boot-validate.py - validate a Qualcomm Linux board boots to a login shell.

Watches the board's serial console, waits for the login prompt, logs in with
the given credentials, and runs a few sanity checks (uname, /etc/os-release
including BUILD_ID, systemctl is-system-running).

Run it on whichever host has the serial console attached (locally, or piped
over ssh so nothing is left on the remote host):

    python3 boot-validate.py --port /dev/ttyUSB0 --password oelinux123
    ssh <host> "python3 - --port /dev/ttyUSB0" < boot-validate.py

By default the script only watches the console: start it, then power-cycle
or reset the board (or start it right after flashing). Alternatively pass
--power-cycle-cmd with a host command that power-cycles the board (e.g. a
lab automation wrapper); it is run once at startup.

Prints "BOOT-VALIDATION: PASS ..." and exits 0 on success; prints
"BOOT-VALIDATION: FAIL ..." and exits non-zero otherwise. The full console
capture is mirrored to a log file for evidence.
"""

import argparse
import os
import re
import subprocess
import sys
import time

try:
    import serial  # pyserial
except ImportError:
    sys.exit("error: pyserial is required (pip install pyserial)")


def grab(text, start, end):
    """Return the slice of `text` between markers `start` and `end`."""
    try:
        i = text.index(start) + len(start)
    except ValueError:
        return ""
    if end:
        try:
            j = text.index(end, i)
        except ValueError:
            j = len(text)
    else:
        j = len(text)
    return text[i:j].strip()


def strip_ansi(s):
    """Remove ANSI/OSC/DCS escape sequences so plaintext markers survive.

    OE images enable bash's semantic prompt, which sprays OSC-8/OSC-3008
    sequences around the prompt and command echo; strip them before parsing.
    """
    s = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", s)  # OSC (BEL or ST terminated)
    s = re.sub(r"\x1b[P^_X][^\x1b]*\x1b\\", "", s)           # DCS/PM/APC/SOS
    s = re.sub(r"\x1b\[[0-9;?=><]*[ -/]*[@-~]", "", s)       # CSI
    s = re.sub(r"\x1b[()#][0-9A-Za-z]", "", s)               # charset select
    s = re.sub(r"\x1b[@-Z\\-_=>78c]", "", s)                 # other short ESC (incl DECSC/DECRC)
    return s.replace("\x07", "")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default="/dev/ttyUSB0",
                    help="serial console device (default: /dev/ttyUSB0)")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--username", default="root")
    ap.add_argument("--password", default="",
                    help="login password ('' for nodistro images; oelinux123 for qcom-distro)")
    ap.add_argument("--timeout", type=float, default=300.0,
                    help="seconds to wait for the login prompt")
    ap.add_argument("--power-cycle-cmd", default=None,
                    help="optional host command that power-cycles the board; run once at startup")
    ap.add_argument("--logfile", default=None,
                    help="console capture path (default: /tmp/qcom-boot-validate-<ts>.log)")
    args = ap.parse_args()

    logpath = args.logfile or ("/tmp/qcom-boot-validate-%d.log" % int(time.time()))
    try:
        logdir = os.path.dirname(logpath)
        if logdir:
            os.makedirs(logdir, exist_ok=True)
        logf = open(logpath, "w", buffering=1, errors="replace")
    except OSError:
        logf = None

    def log(msg):
        line = "[bv] %s" % msg
        print(line, flush=True)
        if logf:
            logf.write(line + "\n")

    def finish(ok, msg, warn=False):
        tag = "PASS" if ok else "FAIL"
        if ok and warn:
            tag = "PASS(warn)"
        if not ok:
            tail = "\n".join(buf.splitlines()[-40:])
            print("---- last console output ----", flush=True)
            print(tail, flush=True)
            print("---- end console output ----", flush=True)
        print("BOOT-VALIDATION: %s - %s" % (tag, msg), flush=True)
        print("boot log: %s" % logpath, flush=True)
        if logf:
            logf.flush()
            logf.close()
        sys.exit(0 if ok else 1)

    try:
        ser = serial.Serial(args.port, args.baud, timeout=0.2)
    except serial.SerialException as e:
        sys.exit("error: could not open %s: %s (is something else, e.g. screen, holding it?)"
                 % (args.port, e))

    buf = ""

    def read_chunk():
        nonlocal buf
        chunk = ser.read(4096)
        if chunk:
            text = chunk.decode(errors="replace")
            buf += text
            if logf:
                logf.write(text)
            return True
        return False

    def wait_for(patterns, timeout):
        """Read until one compiled regex in `patterns` matches buf; return its index or None."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            read_chunk()  # blocks up to the serial read timeout (0.2s)
            for i, p in enumerate(patterns):
                if p.search(buf):
                    return i
        return None

    def send(line):
        ser.write((line + "\n").encode())
        ser.flush()

    def at_prompt():
        """True if the last non-empty console line looks like an interactive shell prompt."""
        tail = strip_ansi(buf)[-400:]
        lines = [ln.rstrip() for ln in tail.splitlines() if ln.strip()]
        if not lines:
            return False
        return lines[-1].endswith("#") or lines[-1].endswith("$")

    def wait_for_prompt(timeout):
        """Wait until the shell prompt is actually present, nudging with a newline.

        Crucially this waits for the shell to be *ready* before we send anything
        (an early command gets swallowed during login/session setup)."""
        deadline = time.monotonic() + timeout
        last_nudge = 0.0
        while time.monotonic() < deadline:
            read_chunk()
            if at_prompt():
                return True
            now = time.monotonic()
            if now - last_nudge > 2.0:
                send("")  # a bare newline; harmless, re-prints the prompt once ready
                last_nudge = now
        return False

    def wait_for_text(needle, timeout):
        """Wait until `needle` appears in the (escape-stripped) console buffer."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            read_chunk()
            if needle in strip_ansi(buf):
                return True
        return False

    # 1) trigger a clean boot -------------------------------------------------
    if args.power_cycle_cmd:
        log("power-cycling board via: %s" % args.power_cycle_cmd)
        r = subprocess.run(args.power_cycle_cmd, shell=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log("power-cycle rc=%d: %s" % (r.returncode,
                                       r.stdout.decode(errors="replace").strip()))
        if r.returncode != 0:
            log("WARNING: power-cycle command returned non-zero; continuing to watch console")
    else:
        log("no --power-cycle-cmd given: power-cycle or reset the board now "
            "if it is not already booting")
    # drop anything captured before/around the power-cycle so we don't match a
    # stale login prompt from a previous session.
    ser.reset_input_buffer()
    buf = ""

    # 2) wait for the login prompt -------------------------------------------
    log("waiting up to %.0fs for a login prompt on %s ..." % (args.timeout, args.port))
    if wait_for([re.compile(r"login:", re.IGNORECASE)], args.timeout) is None:
        if not buf.strip():
            finish(False, "no output at all on %s - wrong console or nothing is booting" % args.port)
        finish(False, "timed out waiting for the login prompt")
    log("got login prompt")

    # 3) log in ---------------------------------------------------------------
    time.sleep(0.5)
    ser.reset_input_buffer()
    buf = ""
    send(args.username)

    # A password prompt appears for qcom-distro (oelinux123); an empty-password
    # image may go straight to a shell prompt.
    pw_sent = False
    idx = wait_for([re.compile(r"[Pp]assword:"),
                    re.compile(r"@[\w.-]+:[^\r\n]*[#$]\s*\Z")], 10)
    if idx == 0:
        log("sending password")
        send(args.password)
        pw_sent = True

    # Wait for the shell to actually be ready (do NOT send commands before this).
    if not wait_for_prompt(30):
        if re.search(r"[Ll]ogin incorrect", strip_ansi(buf)):
            finish(False, "'Login incorrect' - wrong password for this image?")
        if args.password and not pw_sent:
            log("no shell yet; sending password and retrying")
            send(args.password)
            if not wait_for_prompt(30):
                finish(False, "login did not reach a shell (after password retry)")
        else:
            finish(False, "login did not reach a shell")
    log("login successful (shell prompt reached)")

    # 4) sanity checks (fenced with split markers) ---------------------------
    ser.reset_input_buffer()
    buf = ""
    cmd = ('echo BV""START; '
           'echo "--UNAME--"; uname -a; '
           'echo "--OSREL--"; (grep -E "^(PRETTY_NAME|VERSION|BUILD_ID)=" /etc/os-release 2>/dev/null || echo "no /etc/os-release"); '
           'echo "--SYSTEMD--"; (systemctl is-system-running 2>&1 || true); '
           'echo BV""END')
    send(cmd)
    # The typed command echo contains BV""END (with quotes); only the executed
    # output prints a bare "BVEND", so this waits for the command to actually run.
    if not wait_for_text("BVEND", 60):
        finish(False, "sanity-check command did not complete")

    clean = strip_ansi(buf)
    section = grab(clean, "BVSTART", "BVEND")
    uname = grab(section, "--UNAME--", "--OSREL--")
    osrel = grab(section, "--OSREL--", "--SYSTEMD--")
    systemd = grab(section, "--SYSTEMD--", None)

    log("uname : %s" % uname.strip())
    for line in osrel.splitlines():
        if line.strip():
            log("os-release : %s" % line.strip())
    sd = systemd.strip().splitlines()[-1].strip() if systemd.strip() else ""
    log("systemd is-system-running : %s" % (sd or "<none>"))

    # be tidy: log out of the serial session
    try:
        send("exit")
    except Exception:
        pass

    # 5) verdict --------------------------------------------------------------
    if not uname.strip():
        finish(False, "reached a shell but 'uname -a' produced no output")
    if sd in ("running", "starting"):
        finish(True, "system '%s'; kernel: %s" % (sd, uname.strip()))
    elif sd == "degraded":
        finish(True, "booted, but systemd is 'degraded' (some unit failed); kernel: %s"
               % uname.strip(), warn=True)
    else:
        # e.g. sysvinit image where systemctl is absent - shell + uname is still a good boot signal
        finish(True, "reached login shell (systemd state '%s'); kernel: %s"
               % (sd or "unknown", uname.strip()), warn=True)


if __name__ == "__main__":
    main()
