#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# qcom-release-collect.sh - capture everything needed to identify the
# software and firmware stack of a booted Qualcomm Linux target.
#
# QLI 1.x shipped a single Ver_Info.txt; QLI 2.x does not. The equivalent
# information is still on the device, spread over /etc/os-release,
# /etc/buildinfo, the qcom_socinfo debugfs tree and the EFI loader
# variables. This script reads all of them and prints one plain-text
# capture that qcom-release-report.py turns into a support report.
#
# Read-only: it opens files and runs uname/uptime/systemctl, nothing else.
#
# Usage (on the target):
#   qcom-release-collect.sh [--force] > capture.txt
#
# Usage (from a host that can reach the target over ssh):
#   ssh <target> 'bash -s' < qcom-release-collect.sh > capture.txt
#
#   --force   Collect even when the device tree does not look like a
#             Qualcomm target (useful for producing test captures).
#   -h,--help Print this header.
#
# Exit status: 0 when a capture was written, 2 when the target is not a
# Qualcomm device (and --force was not given). Missing individual sources
# are recorded in the capture as "<unavailable: ...>", never fatal.
set -euo pipefail

COLLECTOR_VERSION="0.2"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --force)    FORCE=1 ;;
    -h|--help)
      # $0 is "bash" when the script is piped in (ssh <target> 'bash -s'),
      # so the header cannot be re-read; fall back to a short usage rather
      # than letting awk fail on a file that is not this script.
      if [ -r "$0" ] && grep -q 'qcom-release-collect.sh - capture' "$0" 2>/dev/null; then
        awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"
      else
        echo "usage: qcom-release-collect.sh [--force] > capture.txt" >&2
        echo "The full header cannot be shown when the script is piped in" >&2
        echo "over stdin; read the file itself for the complete help." >&2
      fi
      exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

section() { printf '\n=== SECTION: %s ===\n' "$1"; }
unavail() { printf '<unavailable: %s>\n' "$1"; }

# Read a NUL-terminated device-tree string without tripping `set -e` when
# /proc/device-tree is absent (e.g. on an x86 host).
dt_read() {
  tr -d '\0' 2>/dev/null < "$1" || true
}

# efivar payload = 4 attribute bytes followed by a UTF-16LE string.
efi_decode() {
  if command -v iconv >/dev/null 2>&1; then
    tail -c +5 "$1" 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr -d '\0' || true
  else
    tail -c +5 "$1" 2>/dev/null | tr -d '\0' || true
  fi
}

model=$(dt_read /proc/device-tree/model)
compatible=$(tr '\0' ' ' 2>/dev/null < /proc/device-tree/compatible || true)

case "$compatible" in
  *qcom,*) ;;
  *)
    if [ "$FORCE" -ne 1 ]; then
      echo "Not running on a Qualcomm target (compatible: '${compatible:-unknown}')" >&2
      echo "Use --force to collect anyway." >&2
      exit 2
    fi
    ;;
esac

# ---------------------------------------------------------------- identity
section MODEL
printf '%s\n' "${model:-$(unavail "no /proc/device-tree/model")}"

section COMPATIBLE
printf '%s\n' "${compatible:-$(unavail "no /proc/device-tree/compatible")}"

section SOC0
if [ -d /sys/devices/soc0 ]; then
  for f in /sys/devices/soc0/*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    [ "$name" = "uevent" ] && continue
    value=$(cat "$f" 2>/dev/null || true)
    [ -n "$value" ] && printf '%s = %s\n' "$name" "$value"
  done
else
  unavail "no /sys/devices/soc0"
fi

# ------------------------------------------------------------- os identity
section OS_RELEASE
if [ -r /etc/os-release ]; then
  cat /etc/os-release
else
  unavail "no /etc/os-release"
fi

section BUILDINFO
if [ -r /etc/buildinfo ]; then
  cat /etc/buildinfo
else
  unavail "no /etc/buildinfo - image not built with the image-buildinfo class"
fi

# ---------------------------------------------------------------- firmware
SOCINFO=/sys/kernel/debug/qcom_socinfo
# Three states, because "could not tell" is not the same as "not mounted":
# mountpoint is optional, and even when present it cannot stat the directory
# as an ordinary user.
if ! command -v mountpoint > /dev/null 2>&1; then
  debugfs_state="unknown (mountpoint not available)"
elif mountpoint -q /sys/kernel/debug 2>/dev/null; then
  debugfs_state="mounted"
elif [ -d /sys/kernel/debug ]; then
  debugfs_state="unknown (cannot confirm without root)"
else
  debugfs_state="not mounted"
fi

section SOCINFO_NAMES
if [ ! -d "$SOCINFO" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    unavail "needs root (debugfs is root-only)"
  elif [ "$debugfs_state" = "not mounted" ]; then
    unavail "debugfs is not mounted on /sys/kernel/debug"
  elif [ "$debugfs_state" != "mounted" ]; then
    unavail "debugfs state $debugfs_state; $SOCINFO is not readable"
  else
    unavail "no $SOCINFO - qcom_socinfo debugfs interface absent"
  fi
else
  found=0
  for d in "$SOCINFO"/*/; do
    [ -r "$d/name" ] || continue
    subsystem=${d%/}
    subsystem=${subsystem##*/}
    raw=$(cat "$d/name" 2>/dev/null || true)
    # Empty entries are normal: the subsystem is absent or not loaded.
    [ -n "$raw" ] || continue
    found=1
    # Values are "NN:<build string>"; NN is the subsystem index.
    case "$raw" in
      [0-9][0-9]:*) index=${raw%%:*}; build=${raw#*:} ;;
      *)            index=""; build=$raw ;;
    esac
    printf '%s = %s\n' "$subsystem" "$build"
    [ -n "$index" ] && printf '%s.index = %s\n' "$subsystem" "$index"
    for extra in oem variant; do
      [ -r "$d/$extra" ] || continue
      value=$(cat "$d/$extra" 2>/dev/null || true)
      [ -n "$value" ] && printf '%s.%s = %s\n' "$subsystem" "$extra" "$value"
    done
  done
  [ "$found" -eq 1 ] || unavail "every subsystem name is empty"
fi

section SOCINFO_SCALARS
if [ -d "$SOCINFO" ]; then
  for f in "$SOCINFO"/*; do
    [ -f "$f" ] || continue
    name=${f##*/}
    value=$(head -n 1 "$f" 2>/dev/null || true)
    [ -n "$value" ] && printf '%s = %s\n' "$name" "$value"
  done
else
  unavail "no $SOCINFO"
fi

section EFI_LOADER
if [ -d /sys/firmware/efi/efivars ]; then
  found=0
  # Text-valued loader variables only; the others hold binary data.
  for var in LoaderFirmwareInfo LoaderFirmwareType LoaderInfo LoaderStubInfo \
             LoaderImageIdentifier LoaderEntrySelected LoaderDevicePartUUID; do
    for f in /sys/firmware/efi/efivars/"$var"-*; do
      [ -r "$f" ] || continue
      value=$(efi_decode "$f")
      value=${value%"${value##*[![:space:]]}"}
      [ -n "$value" ] || continue
      found=1
      printf '%s = %s\n' "$var" "$value"
    done
  done
  [ "$found" -eq 1 ] || unavail "no readable systemd-boot loader variables"
else
  unavail "not an EFI boot (no /sys/firmware/efi/efivars)"
fi

# ------------------------------------------------------------------ runtime
section KERNEL
uname -a 2>/dev/null || unavail "uname failed"

section UPTIME
uptime -p 2>/dev/null || uptime 2>/dev/null || unavail "uptime not available"

section SYSTEMD
# Exits non-zero for every state except "running" (degraded, starting,
# maintenance...), so key off the output, not the status.
systemd_state=$(systemctl is-system-running 2>/dev/null) || true
if [ -n "$systemd_state" ]; then
  printf '%s\n' "$systemd_state"
else
  unavail "systemctl not available"
fi

section COLLECTOR
printf 'collector_version = %s\n' "$COLLECTOR_VERSION"
if [ "$(id -u)" -eq 0 ]; then printf 'ran_as_root = yes\n'; else printf 'ran_as_root = no\n'; fi
printf 'debugfs = %s\n' "$debugfs_state"
