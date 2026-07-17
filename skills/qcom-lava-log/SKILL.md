---
name: lava-logs
description: Fetch and analyze LAVA test job logs, metadata, results, and definitions from a Foundries/Linaro LAVA instance (default lava.infra.foundries.io). Use when given a LAVA job URL or job ID (e.g. .../scheduler/job/256592) and asked to investigate a test failure, root-cause a job, or read the serial console / kernel boot log. The LAVA web UI is behind Anubis anti-bot protection so WebFetch returns 403 — use the REST API endpoints below instead.
---

# Accessing LAVA logs

The LAVA **web UI** (`/scheduler/job/<id>`) is behind Anubis anti-bot protection, so
`WebFetch` / plain browser fetches return **HTTP 403**. Use the **REST API v0.2**
endpoints instead — they serve public jobs without authentication.

Default host: `lava.infra.foundries.io`. A URL like
`https://lava.infra.foundries.io/scheduler/job/256592#L3656` means **job ID `256592`**
(the `#L3656` is a UI line anchor, not part of the API).

## Endpoints (no auth for public jobs)

```bash
HOST=lava.infra.foundries.io
JOB=256592

# Metadata: status, device_type, actual_device, submitter, times, and the full job definition
curl -s "https://$HOST/api/v0.2/jobs/$JOB/"

# Full logs (YAML list of JSON log records) — this is the main artifact
curl -s "https://$HOST/api/v0.2/jobs/$JOB/logs/"

# Same log content via the scheduler plain endpoint (fallback if the API path changes)
curl -s "https://$HOST/scheduler/job/$JOB/log_file/plain"

# Per-test-suite results (if needed)
curl -s "https://$HOST/api/v0.2/jobs/$JOB/tests/"
```

A helper is provided: `./scripts/lava.sh <job_id_or_url> [host]` downloads metadata +
logs to `/tmp/lava_<job>.{json,logs}` and prints a quick result summary. It transparently
handles XZ-compressed logs (see below).

## ⚠️ Compressed (archived) logs

The `/logs/` (and `/log_file/plain`) endpoint serves **plain text for recent/live jobs but
raw XZ-compressed bytes for older / archived jobs**. This is *not* HTTP `Content-Encoding`
— it's the stored `.xz` file served as-is, so `curl` does **not** decompress it, and your
greps silently return nothing (or `UnicodeDecodeError` in Python). Detect it by the XZ
magic at byte 0: `FD 37 7A 58 5A 00` (`\xFD7zXZ`).

Always decompress-or-passthrough after fetching:

```bash
# robust fetch that works for BOTH plain and xz logs
curl -s "https://$HOST/api/v0.2/jobs/$JOB/logs/" -o /tmp/raw.bin
{ xz -dc /tmp/raw.bin 2>/dev/null || cat /tmp/raw.bin; } > /tmp/lava_$JOB.logs

# or streaming, in one line:
curl -s "https://$HOST/api/v0.2/jobs/$JOB/logs/" | { xz -dc 2>/dev/null || cat; } > /tmp/lava_$JOB.logs

# quick check whether a downloaded file is xz:
xxd /tmp/raw.bin | head -1   # leading "fd37 7a58 5a00" => xz
```

When sweeping **many** jobs (e.g. extracting per-job kernel versions), this matters a lot:
a naive `curl | grep` will mark every archived job as "blank/missing" if you skip the
`xz -dc` step.

## Log format

Each log line is a YAML list item wrapping one JSON record:

```
- {"dt": "2026-06-10T14:11:19.154147", "lvl": "target", "msg": "..."}
```

- `lvl` values: `info`, `debug`, `warning`, `error`, `results`, and **`target`**.
- **`target`** = serial console output from the device under test (DUT) — this is where
  the **kernel boot log / dmesg** and test-script stdout live. Grep these first for
  hardware/driver root causes.
- `results` records carry test-case outcomes; `msg` is itself a JSON object with
  `definition`, `case`, `result` (pass/fail/skip), `duration`, `commit_id`, etc.
- Test scripts print `[PASS]/[FAIL]/[INFO]/[WARN]` lines and emit
  `<<<LAVA_SIGNAL_TESTCASE TEST_CASE_ID=<name> RESULT=<PASS|FAIL>>>>`.

## Useful queries

```bash
LOGS=/tmp/lava_$JOB.logs   # downloaded via the helper or curl above

# All test-case results (pass/fail/skip) in order
grep -oE '"definition": "[0-9][^"]*", "case": "[^"]*", "result": "[^"]*"' "$LOGS"

# Find a specific failing test and its [FAIL] reason
grep -n "RESULT=FAIL\|\[FAIL\]" "$LOGS"

# Read only the DUT serial console / kernel log (lvl == target), de-noised
grep '"lvl": "target"' "$LOGS" | sed 's/.*"msg": //; s/}}\?$//'

# Pretty-print a line range (UI #L<n> anchor maps roughly to file line n)
sed -n '3636,3760p' "$LOGS" | sed 's/.*"lvl": "\([a-z]*\)", "msg": /[\1] /; s/}}\?$//'

# Kernel hardware probe failures (common root causes)
grep '"lvl": "target"' "$LOGS" | grep -iE "never came up|failed|error|cut here|WARNING|Call trace|timed out"

# Job status + device from metadata
python3 -c "import json,sys; d=json.load(open('/tmp/lava_$JOB.json')); print(d['state'],d['health'],d['requested_device_type'],d['actual_device'])"
```

## Investigation workflow

1. Resolve the **job ID** from the URL (digits after `/job/`).
2. Fetch metadata → note `device_type`, `actual_device`, `state`, `health`, and read the
   job `definition` (lists deploy image URL and the test definitions/expected cases).
3. Fetch logs → list all test-case results to see which case failed.
4. Jump to the failing case's `target` lines for the `[FAIL]` reason and surrounding
   script output.
5. Correlate with the **kernel boot log** (`lvl: target`) for the underlying hardware/
   driver cause (e.g. `Phy link never came up`, probe `-EPROBE_DEFER`, firmware load
   errors, missing DT node). A driver that prints *zero* kernel messages usually means it
   never bound to any device.
6. Check whether the triggering change (e.g. the GitHub Actions build/commit) could
   plausibly cause the failure, or whether it's a pre-existing board/lab/DT issue.
