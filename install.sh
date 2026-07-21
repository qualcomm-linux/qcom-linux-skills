#!/usr/bin/env bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# Install the qcom-linux-skills catalog into the directories that common
# agents (Claude Code, Codex, Cursor) read skills from.
#
# Safe to re-run: correct links are left untouched and stale links into an
# old clone are repaired. Existing entries that are not from this catalog
# are never touched unless --force is passed.
#
# Usage:
#   ./install.sh                                  # all skills, all personal targets
#   ./install.sh --targets claude,cursor          # selected personal targets
#   ./install.sh --targets project --project DIR  # DIR/.claude/skills
#   ./install.sh --skills qcom-flash-qdl          # only the named skills
#   ./install.sh --list                           # list available skills and exit
#   ./install.sh --copy                           # copy instead of symlink
#   ./install.sh --force                          # replace existing catalog entries
#
# Targets:
#   claude  -> ~/.claude/skills/
#   codex   -> ~/.codex/skills/
#   cursor  -> ~/.cursor/skills/
#   project -> <project>/.claude/skills/ (requires --project)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"
MODE=symlink
TARGETS="claude,codex,cursor"
SKILLS=""
PROJECT_DIR=""
FORCE=0
LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE=copy; shift ;;
    --force) FORCE=1; shift ;;
    --list) LIST=1; shift ;;
    --targets)
      [ $# -ge 2 ] || { echo "--targets requires a value (e.g. claude,codex,cursor,project)" >&2; exit 1; }
      TARGETS="$2"; shift 2 ;;
    --targets=*) TARGETS="${1#--targets=}"; shift ;;
    --skills)
      [ $# -ge 2 ] || { echo "--skills requires a value (e.g. qcom-flash-qdl,qcom-boot-validate)" >&2; exit 1; }
      SKILLS="$2"; shift 2 ;;
    --skills=*) SKILLS="${1#--skills=}"; shift ;;
    --project)
      [ $# -ge 2 ] || { echo "--project requires a path" >&2; exit 1; }
      PROJECT_DIR="$2"; shift 2 ;;
    --project=*) PROJECT_DIR="${1#--project=}"; shift ;;
    --help|-h)
      sed -n '5,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

ok()   { echo "  [ok]   $*"; }
skip() { echo "  [skip] $*"; }
err()  { echo "  [err]  $*"; }

want_target() {
  case ",${TARGETS}," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
  esac
}

# With no --skills selection every skill is wanted.
want_skill() {
  [ -z "$SKILLS" ] && return 0
  case ",${SKILLS}," in
    *,"$1",*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print "<name>  <first line of the frontmatter description>" per skill.
list_skills() {
  local src name desc
  for src in "$SKILLS_SRC"/*/; do
    name="$(basename "${src%/}")"
    desc="$(awk '/^description:/ {
        line = $0; sub(/^description:[ ]*/, "", line)
        if (line != ">-" && line != ">" && line != "") { print line; exit }
        getline; sub(/^[ ]+/, ""); print; exit
      }' "$src/SKILL.md" 2>/dev/null)"
    printf '  %-32s %s\n' "$name" "$desc"
  done
}

# An entry may be replaced with --force only if it is one of ours: a symlink,
# or a directory whose name matches a skill shipped by this catalog.
is_catalog_entry() {
  local path="$1"
  local base; base="$(basename "$path")"
  [ -d "$SKILLS_SRC/$base" ] || return 1
  [ -L "$path" ] || [ -e "$path/SKILL.md" ]
}

install_entry() {
  local src="$1" dst="$2"
  local name; name="$(basename "$src")"

  if [ "$MODE" = symlink ]; then
    if [ -L "$dst" ]; then
      local current; current="$(readlink "$dst")"
      if [ "$current" = "$src" ]; then
        skip "$name (already linked)"
        return
      fi
      skip "$name (repairing stale link: $current)"
      rm "$dst"
    elif [ -e "$dst" ]; then
      if [ "$FORCE" -eq 1 ] && is_catalog_entry "$dst"; then
        skip "$name (replacing existing entry because --force was passed)"
        rm -rf "$dst"
      else
        err "$name - $dst exists and is not a symlink; skipping (use --force to replace catalog entries)"
        return
      fi
    fi
    ln -s "$src" "$dst"
    ok "$name -> $src"
  else
    if [ -e "$dst" ]; then
      if [ "$FORCE" -eq 1 ] && is_catalog_entry "$dst"; then
        skip "$name (replacing existing entry because --force was passed)"
        rm -rf "$dst"
      else
        err "$name - $dst exists; skipping (use --force to replace catalog entries)"
        return
      fi
    fi
    cp -r "$src" "$dst"
    ok "$name (copied)"
  fi
}

install_skills_into() {
  local dst_dir="$1" label="$2"
  mkdir -p "$dst_dir"
  echo ""
  echo "[$label] Skills -> $dst_dir"
  local src name missing=0 checked=0
  for src in "$SKILLS_SRC"/*/; do
    src="${src%/}"
    name="$(basename "$src")"
    want_skill "$name" || continue
    install_entry "$src" "$dst_dir/$name"
  done
  for src in "$SKILLS_SRC"/*/; do
    name="$(basename "${src%/}")"
    want_skill "$name" || continue
    checked=$((checked + 1))
    [ -f "$dst_dir/$name/SKILL.md" ] || missing=$((missing + 1))
  done
  if [ "$missing" -eq 0 ]; then
    ok "$label verified ($checked skills visible)"
  else
    err "$label verification failed ($missing of $checked skills missing)"
  fi
}

if [ ! -d "$SKILLS_SRC" ] || [ -z "$(ls -A "$SKILLS_SRC" 2>/dev/null)" ]; then
  echo "No skills found under $SKILLS_SRC" >&2
  exit 1
fi

if [ "$LIST" -eq 1 ]; then
  echo "Available skills in $SKILLS_SRC:"
  list_skills
  exit 0
fi

for t in ${TARGETS//,/ }; do
  case "$t" in
    claude|codex|cursor|project) ;;
    *) echo "Unknown target: '$t' (valid: claude, codex, cursor, project)" >&2; exit 1 ;;
  esac
done

for s in ${SKILLS//,/ }; do
  if [ ! -d "$SKILLS_SRC/$s" ]; then
    echo "Unknown skill: '$s' (valid names below)" >&2
    list_skills >&2
    exit 1
  fi
done

if want_target project; then
  if [ -z "$PROJECT_DIR" ]; then
    echo "--project is required when using --targets project" >&2
    exit 1
  fi
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "--project path does not exist or is not a directory: $PROJECT_DIR" >&2
    exit 1
  fi
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
fi

echo "Mode: $MODE"
echo "Targets: $TARGETS"
echo "Source: $REPO_DIR"
[ -n "$SKILLS" ] && echo "Skills: $SKILLS"
[ -n "$PROJECT_DIR" ] && echo "Project: $PROJECT_DIR"

want_target claude  && install_skills_into "${HOME}/.claude/skills" "claude"
want_target codex   && install_skills_into "${HOME}/.codex/skills"  "codex"
want_target cursor  && install_skills_into "${HOME}/.cursor/skills" "cursor"
want_target project && install_skills_into "${PROJECT_DIR}/.claude/skills" "project"

echo ""
echo "Done. Restart your agent, or start a new session, to pick up new skills."
