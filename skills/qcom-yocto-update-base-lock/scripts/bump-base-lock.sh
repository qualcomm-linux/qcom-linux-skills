#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# bump-base-lock.sh - refresh ci/base.lock.yml layer pins to the latest
# upstream commit, git-only.
#
# Iterates over exactly the repos already pinned in ci/base.lock.yml, resolves
# each one's latest commit on its configured branch (URL/branch come from the
# ci/*.yml kas configs), rewrites the pin in place, and writes a changelog-style
# commit message with one "Relevant changes for <layer>:" section per changed
# layer. It NEVER adds or removes repos - the lock set is hand-curated
# (meta-qcom-distro is intentionally left floating, meta-dpdk is intentionally
# pinned), so only existing commit: values are touched.
#
# It does NOT create a branch or commit - that is the reviewed final step done
# by the caller (see SKILL.md).
#
# Usage (run from the meta-qcom repo root):
#   bump-base-lock.sh [--dry-run] [--cache-dir DIR] [--message-file FILE]
#                     [--lock-file FILE]
#
#   --dry-run        Resolve + show old->new and the proposed message; write
#                    nothing to the lock.
#   --cache-dir DIR  Bare-clone cache (default: ~/.cache/meta-qcom-base-lock).
#   --message-file F Where to write the commit message
#                    (default: <cache-dir>/commit-message.txt).
#   --lock-file F    Lock file to read/rewrite (default: ci/base.lock.yml).

set -euo pipefail

DRY_RUN=0
CACHE_DIR="${HOME}/.cache/meta-qcom-base-lock"
MESSAGE_FILE=""
LOCK_FILE="ci/base.lock.yml"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)          DRY_RUN=1 ;;
    --cache-dir)        CACHE_DIR="$2"; shift ;;
    --cache-dir=*)      CACHE_DIR="${1#*=}" ;;
    --message-file)     MESSAGE_FILE="$2"; shift ;;
    --message-file=*)   MESSAGE_FILE="${1#*=}" ;;
    --lock-file)        LOCK_FILE="$2"; shift ;;
    --lock-file=*)      LOCK_FILE="${1#*=}" ;;
    -h|--help)          awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$LOCK_FILE" ]; then
  echo "error: '$LOCK_FILE' not found - run from the meta-qcom repo root" >&2
  exit 1
fi
if [ -z "$(ls ci/*.yml 2>/dev/null)" ]; then
  echo "error: no ci/*.yml configs found - run from the meta-qcom repo root" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR"
: "${MESSAGE_FILE:=$CACHE_DIR/commit-message.txt}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cl"

# --------------------------------------------------------------------------
# Phase A: parse the lock + ci/*.yml -> repos.tsv (repo \t url \t branch \t old)
#          preserving lock order. URL/branch are resolved from the ci configs,
#          preferring the canonical definitions (base/qcom-distro/meta-arm/dpdk).
# --------------------------------------------------------------------------
python3 - "$LOCK_FILE" "$WORK/repos.tsv" ci/*.yml <<'PY'
import os, re, sys

lock_path, out_path = sys.argv[1], sys.argv[2]
ci_files = sys.argv[3:]

def indent(s):
    return len(s) - len(s.lstrip(' '))

def top_block(lines, key):
    """Return (start, end) line range of a top-level `key:` block (indent 0)."""
    for i, ln in enumerate(lines):
        if indent(ln) == 0 and ln.strip() == key + ':':
            j = i + 1
            while j < len(lines):
                l2 = lines[j]
                if l2.strip() and not l2.lstrip().startswith('#') and indent(l2) == 0:
                    break
                j += 1
            return i + 1, j
    return None

# --- ordered [(repo, oldsha)] from overrides: -> repos: -> <repo>: -> commit: ---
lock_lines = open(lock_path).read().splitlines()
locked = []
ov = top_block(lock_lines, 'overrides')
if ov:
    in_repos, repos_indent, cur = False, None, None
    for ln in lock_lines[ov[0]:ov[1]]:
        if not ln.strip() or ln.lstrip().startswith('#'):
            continue
        ind = indent(ln)
        if re.match(r'^\s*repos:\s*$', ln):
            in_repos, repos_indent = True, ind
            continue
        if in_repos:
            if ind <= repos_indent:
                in_repos = False
                continue
            mc = re.match(r'^\s*commit:\s*([0-9a-fA-F]{7,40})\s*$', ln)
            mr = re.match(r'^\s*([A-Za-z0-9][\w.\-]*):\s*$', ln)
            if mc and cur:
                locked.append((cur, mc.group(1)))
                cur = None
            elif mr:
                cur = mr.group(1)
if not locked:
    sys.stderr.write("error: no pinned repos found in %s\n" % lock_path)
    sys.exit(1)

# --- url/branch per repo from ci/*.yml ---
def parse_kas(path):
    lines = open(path).read().splitlines()
    default_branch = None
    db = top_block(lines, 'defaults')
    if db:
        for k in range(*db):
            m = re.match(r'^\s*branch:\s*(\S+)\s*$', lines[k])
            if m:
                default_branch = m.group(1)
                break
    repos = {}
    rb = top_block(lines, 'repos')
    if rb:
        cur = None
        for ln in lines[rb[0]:rb[1]]:
            if not ln.strip() or ln.lstrip().startswith('#'):
                continue
            ind = indent(ln)
            mr = re.match(r'^  ([A-Za-z0-9][\w.\-]*):\s*$', ln)  # repo at indent 2
            if ind == 2 and mr:
                cur = mr.group(1)
                repos.setdefault(cur, {})
                continue
            if cur and ind == 4:  # direct child of the repo
                mu = re.match(r'^\s*url:\s*(\S+)\s*$', ln)
                mb = re.match(r'^\s*branch:\s*(\S+)\s*$', ln)
                if mu:
                    repos[cur]['url'] = mu.group(1)
                if mb:
                    repos[cur]['branch'] = mb.group(1)
    return default_branch, repos

# Prefer canonical config files so url/branch are unambiguous.
PRIO = ['base.yml', 'qcom-distro.yml', 'meta-arm.yml', 'dpdk.yml']
def rank(f):
    b = os.path.basename(f)
    return (PRIO.index(b) if b in PRIO else len(PRIO), b)

url_branch = {}
for f in sorted(ci_files, key=rank):
    default_branch, repos = parse_kas(f)
    for repo, info in repos.items():
        if repo in url_branch or 'url' not in info:
            continue
        url_branch[repo] = (info['url'], info.get('branch') or default_branch or 'master')

with open(out_path, 'w') as o:
    for repo, old in locked:
        if repo not in url_branch:
            sys.stderr.write("WARN: %s is pinned in the lock but no url found in "
                             "ci/*.yml; skipping\n" % repo)
            continue
        url, branch = url_branch[repo]
        o.write("%s\t%s\t%s\t%s\n" % (repo, url, branch, old))
PY

if [ ! -s "$WORK/repos.tsv" ]; then
  echo "error: could not resolve any locked repos from ci/*.yml" >&2
  exit 1
fi

# --------------------------------------------------------------------------
# Phase B: fetch latest per repo and compute the changelog for changed ones.
# --------------------------------------------------------------------------
: > "$WORK/changes.tsv"
echo ">> Resolving latest commits (cache: $CACHE_DIR)"
while IFS=$'\t' read -r repo url branch old; do
  mirror="$CACHE_DIR/$repo.git"
  if [ ! -d "$mirror" ]; then
    # tree:0 keeps all commit objects (enough for `git log --oneline`) while
    # skipping trees/blobs, so big-history clones stay light. Servers without
    # partial-clone support transparently fall back to a full clone.
    git clone --quiet --bare --filter=tree:0 "$url" "$mirror" \
      || { echo "ERROR: clone failed for $repo ($url)" >&2; exit 1; }
  fi
  if ! git -C "$mirror" fetch --quiet origin \
         "+refs/heads/$branch:refs/heads/$branch" 2>"$WORK/fetcherr"; then
    echo "ERROR: fetch failed for $repo ($url branch $branch):" >&2
    cat "$WORK/fetcherr" >&2
    exit 1
  fi
  new="$(git -C "$mirror" rev-parse "refs/heads/$branch")"

  if [ "$new" = "$old" ]; then
    printf '  %-22s up-to-date (%s)\n' "$repo" "${old:0:10}"
    continue
  fi
  if ! git -C "$mirror" cat-file -e "${old}^{commit}" 2>/dev/null; then
    echo "  WARN: $repo old pin ${old:0:10} not found upstream (history rewritten?);" \
         "pin will bump but changelog is omitted - review manually" >&2
    : > "$WORK/cl/$repo.txt"
    printf '%s\t%s\t%s\t0\n' "$repo" "$old" "$new" >> "$WORK/changes.tsv"
    continue
  fi
  git -C "$mirror" log --oneline --no-merges "$old..$new" > "$WORK/cl/$repo.txt"
  count="$(wc -l < "$WORK/cl/$repo.txt" | tr -d ' ')"
  printf '  %-22s %s -> %s  (%s commits)\n' "$repo" "${old:0:10}" "${new:0:10}" "$count"
  printf '%s\t%s\t%s\t%s\n' "$repo" "$old" "$new" "$count" >> "$WORK/changes.tsv"
done < "$WORK/repos.tsv"

if [ ! -s "$WORK/changes.tsv" ]; then
  echo
  echo ">> All locked layers are already at their latest upstream commit. Nothing to do."
  exit 0
fi

# --------------------------------------------------------------------------
# Phase C: assemble the commit message (lock order) and rewrite the lock.
# --------------------------------------------------------------------------
NAME="$(git config user.name  2>/dev/null || true)"
EMAIL="$(git config user.email 2>/dev/null || true)"

python3 - "$WORK/changes.tsv" "$WORK/cl" "$MESSAGE_FILE" "$NAME" "$EMAIL" <<'PY'
import os, sys
changes, cldir, msgpath, name, email = sys.argv[1:6]
rows = [l.rstrip('\n').split('\t') for l in open(changes) if l.strip()]
out = ["ci: base.lock: update layers to latest", ""]
for repo, old, new, count in rows:
    out.append("Relevant changes for %s:" % repo)
    cl = os.path.join(cldir, repo + ".txt")
    lines = [l.rstrip('\n') for l in open(cl)] if os.path.exists(cl) else []
    lines = [l for l in lines if l.strip()]
    if lines:
        out += ["- " + l for l in lines]
    else:
        out.append("- (changelog omitted - resolve manually, "
                   "%s -> %s)" % (old[:10], new[:10]))
    out.append("")
out.append("Signed-off-by: %s <%s>" % (name, email) if name and email
           else "Signed-off-by: ")
open(msgpath, "w").write("\n".join(out) + "\n")
PY

if [ "$DRY_RUN" -eq 1 ]; then
  echo
  echo ">> DRY RUN - $LOCK_FILE NOT modified. Proposed commit message:"
  echo "------------------------------------------------------------------"
  cat "$MESSAGE_FILE"
  echo "------------------------------------------------------------------"
  exit 0
fi

# Rewrite the lock: swap each changed repo's old SHA for the new one. SHAs are
# unique 40-char strings, so a plain replace preserves formatting and order.
python3 - "$LOCK_FILE" "$WORK/changes.tsv" <<'PY'
import sys
lock, changes = sys.argv[1], sys.argv[2]
text = open(lock).read()
for l in open(changes):
    if not l.strip():
        continue
    repo, old, new, _count = l.rstrip('\n').split('\t')
    if old not in text:
        sys.stderr.write("ERROR: old sha %s for %s not present in %s\n"
                         % (old, repo, lock))
        sys.exit(1)
    text = text.replace(old, new)
open(lock, "w").write(text)
PY

echo
echo ">> Updated $LOCK_FILE"
echo ">> Commit message written to: $MESSAGE_FILE"
echo ">> Review with: git --no-pager diff $LOCK_FILE"
