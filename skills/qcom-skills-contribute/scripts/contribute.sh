#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
#
# Turn local modifications to an installed qcom-linux-skills skill into a
# DCO-signed commit on a topic branch, ready to submit as a pull request.
#
# The symlink install (install.sh default) points every installed skill
# back into the git clone, so local edits already sit on a branchable
# work tree; this script finds that clone, validates the change, and
# packages it the way the catalog's CONTRIBUTING.md expects. Copy
# installs are supported through a fallback that clones upstream into a
# temporary directory and transplants the modified skill.
#
# Usage:
#   contribute.sh --summary "one line" [options] <skill-name>
#
# Options:
#   --summary TEXT      one-line change summary; the commit subject
#                       becomes "skills/<skill-name>: TEXT" (required)
#   --body-file FILE    commit body: why-first prose wrapped at ~72 cols
#   --assisted-by TEXT  add an "Assisted-by: TEXT" trailer (AGENT:MODEL)
#   --branch NAME       topic branch name (default: contribute/<skill-name>)
#   --repo-dir DIR      catalog clone to use (skips discovery)
#   --skip-checks       skip the catalog validation checks
#   --pr                after committing: fork if needed, push, open the
#                       pull request (asks for confirmation on a tty)
#   --yes               assume "yes" for the --pr confirmation (needed
#                       when running without a tty)
#   --help              show this help

set -euo pipefail

UPSTREAM_SLUG="qualcomm-linux/qcom-linux-skills"
UPSTREAM_URL="https://github.com/${UPSTREAM_SLUG}.git"
INSTALL_DIRS=("${HOME}/.claude/skills" "${HOME}/.codex/skills" "${HOME}/.cursor/skills")

SKILL_NAME=""
SUMMARY=""
BODY_FILE=""
ASSISTED_BY=""
BRANCH=""
REPO_DIR=""
SKIP_CHECKS=0
DO_PR=0
ASSUME_YES=0

info() { echo "[info] $*"; }
warn() { echo "[warn] $*" >&2; }
fail() { echo "[fail] $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --summary)     [ $# -ge 2 ] || fail "--summary requires a value"; SUMMARY="$2"; shift 2 ;;
    --summary=*)   SUMMARY="${1#--summary=}"; shift ;;
    --body-file)   [ $# -ge 2 ] || fail "--body-file requires a path"; BODY_FILE="$2"; shift 2 ;;
    --body-file=*) BODY_FILE="${1#--body-file=}"; shift ;;
    --assisted-by) [ $# -ge 2 ] || fail "--assisted-by requires a value"; ASSISTED_BY="$2"; shift 2 ;;
    --assisted-by=*) ASSISTED_BY="${1#--assisted-by=}"; shift ;;
    --branch)      [ $# -ge 2 ] || fail "--branch requires a name"; BRANCH="$2"; shift 2 ;;
    --branch=*)    BRANCH="${1#--branch=}"; shift ;;
    --repo-dir)    [ $# -ge 2 ] || fail "--repo-dir requires a path"; REPO_DIR="$2"; shift 2 ;;
    --repo-dir=*)  REPO_DIR="${1#--repo-dir=}"; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    --pr)          DO_PR=1; shift ;;
    --yes)         ASSUME_YES=1; shift ;;
    --help|-h)     sed -n '5,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            fail "Unknown option: $1" ;;
    *)             [ -z "$SKILL_NAME" ] || fail "Only one skill name may be given"
                   SKILL_NAME="$1"; shift ;;
  esac
done

[ -n "$SKILL_NAME" ] || fail "A skill name is required (see --help)"
[ -n "$SUMMARY" ] || fail "--summary is required"
if [ -n "$BODY_FILE" ] && [ ! -r "$BODY_FILE" ]; then
  fail "--body-file is not readable: $BODY_FILE"
fi
BRANCH="${BRANCH:-contribute/${SKILL_NAME}}"

# --- Locate the catalog clone -------------------------------------------

# A symlink install points <agent>/skills/<name> at <clone>/skills/<name>;
# resolving it recovers the clone. A copy install only yields the copy, so
# remember it as the fallback source.
COPY_SRC=""
if [ -z "$REPO_DIR" ]; then
  for dir in "${INSTALL_DIRS[@]}"; do
    entry="$dir/$SKILL_NAME"
    if [ -L "$entry" ]; then
      target="$(readlink -f "$entry")" || continue
      candidate="${target%/skills/"${SKILL_NAME}"}"
      if [ "$candidate" != "$target" ] && git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        REPO_DIR="$candidate"
        info "Found catalog clone via $entry -> $REPO_DIR"
        break
      fi
    elif [ -d "$entry" ] && [ -z "$COPY_SRC" ]; then
      COPY_SRC="$entry"
    fi
  done
fi

if [ -z "$REPO_DIR" ] && [ -n "$COPY_SRC" ]; then
  # Copy-install fallback: clone upstream and transplant the modified skill.
  warn "$SKILL_NAME is a copy install ($COPY_SRC), not a symlink into a clone."
  WORK_DIR="$(mktemp -d)"
  info "Cloning $UPSTREAM_URL into $WORK_DIR ..."
  git clone --quiet "$UPSTREAM_URL" "$WORK_DIR/qcom-linux-skills"
  REPO_DIR="$WORK_DIR/qcom-linux-skills"
  rm -rf "${REPO_DIR:?}/skills/${SKILL_NAME}"
  cp -r "$COPY_SRC" "$REPO_DIR/skills/$SKILL_NAME"
  info "Transplanted $COPY_SRC into the fresh clone"
fi

[ -n "$REPO_DIR" ] || fail "Could not find $SKILL_NAME under ${INSTALL_DIRS[*]} (pass --repo-dir <clone>)"
git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || fail "$REPO_DIR is not a git work tree"
[ -d "$REPO_DIR/skills/$SKILL_NAME" ] || fail "$REPO_DIR has no skills/$SKILL_NAME"
cd "$REPO_DIR"

# --- Preflight ------------------------------------------------------------

CHANGES="$(git status --porcelain -- "skills/$SKILL_NAME")"
[ -n "$CHANGES" ] || fail "No local changes under skills/$SKILL_NAME - nothing to contribute"
info "Changes to contribute:"
echo "$CHANGES"

OTHER="$(git status --porcelain | grep -v " skills/$SKILL_NAME/" || true)"
if [ -n "$OTHER" ]; then
  warn "Other local changes exist and will NOT be included:"
  echo "$OTHER" >&2
fi

if [ "$SKIP_CHECKS" -eq 0 ]; then
  info "Running catalog checks ..."
  if command -v shellcheck >/dev/null 2>&1; then
    find install.sh "skills/$SKILL_NAME" -name '*.sh' -print0 \
      | xargs -0 shellcheck || fail "shellcheck reported issues (fix them or rerun with --skip-checks)"
  else
    warn "shellcheck not found; skipping shell lint"
  fi
  find "skills/$SKILL_NAME" -name '*.py' -print0 \
    | xargs -0 --no-run-if-empty python3 -m py_compile \
    || fail "python compile check failed"
  ./install.sh --targets project --project "$(mktemp -d)" >/dev/null \
    || fail "install.sh self-verification failed"
  info "Catalog checks passed"
fi

# --- Topic branch + DCO commit ---------------------------------------------

git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null \
  && fail "Branch $BRANCH already exists (pass --branch to pick another name)"
CURRENT="$(git symbolic-ref --short -q HEAD || echo '(detached)')"
info "Creating branch $BRANCH from $CURRENT"
git switch -c "$BRANCH" >/dev/null

git add -A -- "skills/$SKILL_NAME"
COMMIT_ARGS=(-s -m "skills/${SKILL_NAME}: ${SUMMARY}")
if [ -n "$BODY_FILE" ]; then
  COMMIT_ARGS+=(-m "$(cat "$BODY_FILE")")
else
  warn "No --body-file given: the commit body should explain WHY the change is needed"
fi
[ -n "$ASSISTED_BY" ] && COMMIT_ARGS+=(-m "Assisted-by: ${ASSISTED_BY}")
git commit --quiet "${COMMIT_ARGS[@]}"
info "Committed:"
git log -1 --stat

# --- Push + pull request (opt-in) -------------------------------------------

cat <<EOF

[next] The commit is ready on branch '$BRANCH' in $REPO_DIR.
[next] Consider rebasing before submitting:
[next]   git pull --rebase $UPSTREAM_URL main
[next] To submit it as a pull request:
[next]   gh repo fork $UPSTREAM_SLUG --remote --remote-name fork
[next]   git push -u fork $BRANCH
[next]   gh pr create --repo $UPSTREAM_SLUG --base main --fill
EOF

if [ "$DO_PR" -eq 0 ]; then
  info "Stopping before push (rerun with --pr to fork, push and open the PR)"
  exit 0
fi

command -v gh >/dev/null 2>&1 || fail "--pr requires the gh CLI"
if [ "$ASSUME_YES" -eq 0 ]; then
  [ -t 0 ] || fail "--pr without a tty requires --yes to confirm the push"
  printf 'Fork, push %s and open the PR now? [y/N] ' "$BRANCH"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) info "Aborted before push"; exit 0 ;;
  esac
fi

if ! git remote get-url fork >/dev/null 2>&1; then
  gh repo fork "$UPSTREAM_SLUG" --remote --remote-name fork
fi
git push -u fork "$BRANCH"
gh pr create --repo "$UPSTREAM_SLUG" --base main --fill
info "PASS: pull request opened"
