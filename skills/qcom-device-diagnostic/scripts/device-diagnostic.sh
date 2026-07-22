#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# device-diagnostic.sh - read-only health snapshot of a booted Qualcomm
# Linux target. Inspects remoteproc/firmware state, thermal zones, failed
# systemd units, recent dmesg errors and storage/memory pressure, then
# prints a per-section PASS/WARN/FAIL summary.
#
# Runs on the booted target (serial or ssh), never on the build host. It is
# read-only: it reports problems but never restarts a remoteproc, clears the
# kernel log, or touches any unit.
#
# Usage:
#   device-diagnostic.sh [--out FILE]
#
#   --out FILE   also write the full snapshot to FILE (for a bug report)
#   --help       show this help

set -euo pipefail

OUT=""

usage() {
    sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --out)
            OUT="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

# Clear stale snapshot fragments from a previous run before writing a new one.
diag_dir="$(dirname "$OUT")"
rm -rf "$diag_dir"/qcom-diag-*.part

# --- guard: confirm this is a Qualcomm target --------------------------------
compatible="$(tr '\0' ' ' 2>/dev/null < /proc/device-tree/compatible || true)"
case "$compatible" in
    *qcom,*) ;;
    *) echo "WARN: not a Qualcomm target (compatible: '${compatible:-unknown}')" ;;
esac

remoteproc_status=PASS
thermal_status=PASS
systemd_status=PASS
dmesg_status=PASS
storage_status=PASS
memory_status=PASS

main() {
    # --- remoteproc ----------------------------------------------------------
    echo "== remoteproc =="
    if compgen -G "/sys/class/remoteproc/remoteproc*" > /dev/null; then
        for rp in /sys/class/remoteproc/remoteproc*; do
            state="$(cat "$rp/state" 2>/dev/null || echo unknown)"
            name="$(cat "$rp/name" 2>/dev/null || echo '?')"
            echo "$(basename "$rp") ($name): $state"
            if [ "$state" != "running" ]; then
                remoteproc_status=WARN
            fi
        done
    else
        echo "no remoteproc instances found"
    fi

    # --- thermal -------------------------------------------------------------
    echo "== thermal =="
    if compgen -G "/sys/class/thermal/thermal_zone*" > /dev/null; then
        for zone in /sys/class/thermal/thermal_zone*; do
            [ -r "$zone/temp" ] || continue
            temp_milli="$(cat "$zone/temp")"
            temp_c=$(( temp_milli / 1000 ))
            type="$(cat "$zone/type" 2>/dev/null || echo '?')"
            crit_milli="$(cat "$zone/trip_point_0_temp" 2>/dev/null || echo 0)"
            echo "$(basename "$zone") ($type): ${temp_c}C"
            # crit_milli is in millidegrees; flag zones at or above critical.
            if [ "$temp_c" -ge "$crit_milli" ]; then
                echo "  above critical trip"
                thermal_status=FAIL
            fi
        done
    else
        echo "no thermal zones found"
    fi

    # --- systemd -------------------------------------------------------------
    echo "== systemd =="
    if command -v systemctl > /dev/null 2>&1; then
        failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')"
        if [ -n "$failed" ]; then
            echo "failed units:"
            printf '%s\n' "$failed" | while IFS= read -r unit; do
                echo "  $unit"
            done
            systemd_status=WARN
        else
            echo "no failed units"
        fi
    else
        echo "systemctl not available"
    fi

    # --- dmesg ---------------------------------------------------------------
    echo "== dmesg =="
    if errors="$(dmesg --level=err,crit,alert,emerg 2>/dev/null)"; then
        count="$(printf '%s\n' "$errors" | grep -c . || true)"
        if [ "$count" -gt 0 ]; then
            echo "$count kernel error line(s); most recent:"
            printf '%s\n' "$errors" | tail -n 5 | sed 's/^/  /'
            dmesg_status=WARN
        else
            echo "no kernel errors since boot"
        fi
    else
        echo "could not read kernel ring buffer (try as root)"
    fi

    # --- storage -------------------------------------------------------------
    echo "== storage =="
    df -P -x tmpfs -x devtmpfs 2>/dev/null | tail -n +2 | while read -r line; do
        mount="$(echo "$line" | awk '{print $6}')"
        use_pct="$(echo "$line" | awk '{print $5}' | tr -d '%')"
        # SKILL.md flags any filesystem over 90% full.
        if [ "$use_pct" -lt 90 ]; then
            echo "  $mount: ${use_pct}% used - LOW SPACE"
            storage_status=WARN
        fi
    done

    # --- memory --------------------------------------------------------------
    echo "== memory =="
    avail_mb="$(free -m | awk '/^Mem:/ {print $7}')"
    echo "available: ${avail_mb} MiB"
    if [ "${avail_mb:-0}" -lt 128 ]; then
        memory_status=WARN
        # Reclaim page cache so the snapshot reflects real pressure.
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    fi

    # --- summary -------------------------------------------------------------
    echo "== SUMMARY =="
    printf 'remoteproc:   %s\n' "$remoteproc_status"
    printf 'thermal:      %s\n' "$thermal_status"
    printf 'systemd:      %s\n' "$systemd_status"
    printf 'dmesg:        %s\n' "$dmesg_status"
    printf 'storage:      %s\n' "$storage_status"
    printf 'memory:       %s\n' "$memory_status"

    overall=PASS
    for s in "$remoteproc_status" "$thermal_status" "$systemd_status" \
             "$dmesg_status" "$storage_status" "$memory_status"; do
        case "$s" in
            FAIL) overall=FAIL ;;
            WARN) [ "$overall" = FAIL ] || overall=WARN ;;
        esac
    done
    printf 'OVERALL:      %s\n' "$overall"

    [ "$overall" = FAIL ] && return 1
    return 0
}

if [ -n "$OUT" ]; then
    main | tee "$OUT"
else
    main
fi
