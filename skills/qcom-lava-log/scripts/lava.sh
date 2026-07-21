#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# Fetch LAVA job metadata + logs and print a quick result summary.
# Usage: lava.sh <job_id_or_url> [host]
#   lava.sh 256592
#   lava.sh https://lava.infra.foundries.io/scheduler/job/256592#L3656
set -euo pipefail

arg="${1:?usage: lava.sh <job_id_or_url> [host]}"
host="${2:-lava.infra.foundries.io}"

# Extract host from the URL if one was passed, and the numeric job id.
if [[ "$arg" =~ ^https?://([^/]+)/ ]]; then
  host="${BASH_REMATCH[1]}"
fi
# Prefer the id right after /job/ (ignore any #L<line> anchor); else treat arg as a bare id.
if [[ "$arg" =~ /job/([0-9]+) ]]; then
  job="${BASH_REMATCH[1]}"
elif [[ "$arg" =~ ^[0-9]+$ ]]; then
  job="$arg"
else
  echo "could not parse job id from: $arg" >&2; exit 1
fi

meta="/tmp/lava_${job}.json"
logs="/tmp/lava_${job}.logs"

echo "Fetching job $job from $host ..." >&2
curl -fsS --http1.1 --retry 5 --retry-delay 2 --retry-all-errors \
  -m 60 "https://${host}/api/v0.2/jobs/${job}/" -o "$meta"

# Archived logs are served XZ-compressed (raw .xz, not Content-Encoding); recent jobs are
# plain text. The archive endpoint is FLAKY (HTTP/2 INTERNAL_ERROR / early close / curl 18),
# and curl's own --retry does not validate integrity. So loop: download, then verify the
# blob is a complete xz (xz -t) or non-trivial plain text; retry until good.
fetch_logs() {
  local url="https://${host}/api/v0.2/jobs/${job}/logs/" raw="${logs}.raw" i
  for i in $(seq 1 8); do
    curl -fsS --http1.1 -m 180 "$url" -o "$raw" || true
    if head -c6 "$raw" 2>/dev/null | grep -q $'\xFD7zXZ'; then
      # xz: accept only if it decompresses completely
      if xz -t "$raw" 2>/dev/null; then xz -dc "$raw" > "$logs"; rm -f "$raw"; return 0; fi
    elif [ -s "$raw" ] && ! head -c2 "$raw" | grep -q $'\x1f\x8b' && grep -qm1 '"lvl"' "$raw" 2>/dev/null; then
      # plain-text log (has at least one record) — accept
      mv "$raw" "$logs"; return 0
    fi
    echo "  log fetch attempt $i incomplete, retrying..." >&2; sleep 2
  done
  echo "ERROR: could not fetch a complete log for job $job after 8 tries" >&2; return 1
}
fetch_logs

echo "  metadata: $meta"
echo "  logs:     $logs ($(wc -l < "$logs") lines)"
echo

python3 - "$meta" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"job {d['id']}: state={d['state']} health={d['health']}")
print(f"  device_type={d.get('requested_device_type')} actual_device={d.get('actual_device')}")
print(f"  submitter={d.get('submitter')} desc={d.get('description')}")
print(f"  start={d.get('start_time')} end={d.get('end_time')}")
PY

echo
echo "=== test-case results ==="
grep -oE '"definition": "[0-9][^"]*", "case": "[^"]*", "result": "[^"]*"' "$logs" || echo "(none found)"

echo
echo "=== FAIL markers ==="
grep -n "RESULT=FAIL\|\[FAIL\]" "$logs" | sed 's/.*"msg": //; s/}}\?$//' || echo "(none)"
