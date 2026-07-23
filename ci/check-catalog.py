#!/usr/bin/env python3
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""Catalog consistency checker for qcom-linux-skills.

Enforces the repository-specific conventions documented in AGENTS.md and
the README ("Skill layout and conventions") that generic tooling does not
cover, and the cross-references between skills/, README.md, ROADMAP.md,
.claude-plugin/marketplace.json and skills.json. Every violation is
reported as "[QLSnnn] path: message" and the exit code is non-zero if any
is found.

Spec-level SKILL.md validation (kebab-case limits, allowed keys, NFKC
rules) is delegated to the skills-ref reference validator in CI; this
checker owns only what skills-ref cannot know about this repository.

Usage: python3 ci/check-catalog.py
"""

import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKILLS_DIR = os.path.join(REPO, "skills")
NAME_RE = re.compile(r"^qcom-[a-z0-9]+(-[a-z0-9]+)*$")
MANIFEST_NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
KEY_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):(.*)$")
README_ROW_RE = re.compile(r"\[([a-z0-9-]+)\]\(skills/([a-z0-9-]+)/SKILL\.md\)")
VERSION_RE = re.compile(r"""^(?:"[^"]+"|'[^']+')$""")
MAX_DESCRIPTION = 1024

errors = []


def err(rule, path, message):
    errors.append("[QLS%03d] %s: %s" % (rule, os.path.relpath(path, REPO), message))


def read_text(path):
    with open(path, encoding="utf-8") as fobj:
        return fobj.read()


def parse_frontmatter(text):
    """Return (keys, values) of the top-level frontmatter entries.

    Folded/multi-line scalars are joined with spaces. The ``metadata`` key
    is read as a nested mapping: its indented ``sub: value`` lines are
    returned as a dict under it. Returns None when the frontmatter fences
    are missing or unterminated.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    keys = []
    values = {}
    current = None
    for line in lines[1:]:
        if line.strip() == "---":
            return keys, values
        indented = line[:1] in (" ", "\t")
        submatch = KEY_RE.match(line.strip())
        if indented and isinstance(values.get(current), dict) and submatch:
            values[current][submatch.group(1)] = submatch.group(2).strip()
            continue
        match = KEY_RE.match(line)
        if match:
            current = match.group(1)
            keys.append(current)
            value = match.group(2).strip()
            if value in (">", ">-", "|", "|-"):
                values[current] = ""
            elif value == "" and current == "metadata":
                # `metadata` is the only mapping-valued key; its indented
                # ``sub: value`` lines populate the dict below.
                values[current] = {}
            else:
                values[current] = value
        elif current is not None and line.strip():
            if isinstance(values[current], dict):
                # A key established as a mapping stays a mapping; stray text
                # that is not an indented ``sub: value`` is malformed YAML,
                # left for skills-ref and the metadata check to reject.
                continue
            values[current] = (values[current] + " " + line.strip()).strip()
    return None


def check_skill(name):
    skill_dir = os.path.join(SKILLS_DIR, name)
    skill_md = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(skill_md):
        err(1, skill_dir, "SKILL.md is missing")
        return
    parsed = parse_frontmatter(read_text(skill_md))
    if parsed is None:
        err(2, skill_md, "frontmatter is missing or not delimited by ---")
        return
    keys, values = parsed
    if keys[:2] != ["name", "description"] or set(keys) - {"name", "description", "metadata"}:
        err(3, skill_md,
            "frontmatter must start with 'name' and 'description' and may "
            "only add 'metadata' (found: %s)" % ", ".join(keys or ["none"]))
    elif len(keys) != len(set(keys)):
        err(3, skill_md,
            "frontmatter has a duplicate key (found: %s)" % ", ".join(keys))
    fm_name = values.get("name", "")
    if fm_name and fm_name != name:
        err(4, skill_md,
            "frontmatter name '%s' does not match directory '%s'"
            % (fm_name, name))
    if fm_name and not NAME_RE.match(fm_name):
        err(5, skill_md,
            "name '%s' does not match the documented naming groups "
            "(qcom-[a-z0-9-]*)" % fm_name)
    description = values.get("description", "")
    if not isinstance(description, str) or not description:
        err(6, skill_md, "description is empty or missing")
    elif len(description) > MAX_DESCRIPTION:
        err(6, skill_md,
            "description is %d characters (max %d)"
            % (len(description), MAX_DESCRIPTION))
    metadata = values.get("metadata")
    if metadata is not None:
        if not isinstance(metadata, dict) or not skill_version(values):
            err(7, skill_md,
                "metadata is present but has no quoted 'version' string "
                "(e.g. version: \"0.1\")")


def skill_version(values):
    """Return the SKILL.md metadata version, or '' when absent/invalid.

    The raw-text frontmatter parser cannot tell YAML scalar types apart, so
    a version must be written as a quoted string (``version: "0.1"``); bare
    scalars such as ``0.1``, ``[]`` or ``null`` are rejected as invalid.
    """
    metadata = values.get("metadata")
    if not isinstance(metadata, dict):
        return ""
    raw = metadata.get("version", "").strip()
    if not VERSION_RE.match(raw):
        return ""
    return raw[1:-1]


def check_scripts(name):
    scripts_dir = os.path.join(SKILLS_DIR, name, "scripts")
    if not os.path.isdir(scripts_dir):
        return
    for entry in sorted(os.listdir(scripts_dir)):
        path = os.path.join(scripts_dir, entry)
        if not os.path.isfile(path):
            continue
        text = read_text(path)
        head = "\n".join(text.splitlines()[:10])
        if not os.access(path, os.X_OK):
            err(13, path, "script is not executable")
        if entry.endswith(".sh"):
            if not text.startswith("#!"):
                err(10, path, "missing shebang on the first line")
            if "SPDX-License-Identifier: BSD-3-Clause-Clear" not in head:
                err(11, path, "missing SPDX BSD-3-Clause-Clear header")
            if "set -euo pipefail" not in text:
                err(12, path, "missing 'set -euo pipefail'")
        elif entry.endswith(".py"):
            if "SPDX-License-Identifier: BSD-3-Clause-Clear" not in head:
                err(14, path, "missing SPDX BSD-3-Clause-Clear header")


def check_readme(skills):
    readme = os.path.join(REPO, "README.md")
    rows = []
    for line in read_text(readme).splitlines():
        if line.lstrip().startswith("|"):
            rows.extend(README_ROW_RE.findall(line))
    linked = [target for _, target in rows]
    for text, target in rows:
        if text != target:
            err(21, readme,
                "table row text '%s' does not match its link target '%s'"
                % (text, target))
    for name in skills:
        count = linked.count(name)
        if count == 0:
            err(20, readme,
                "skills/%s has no row in the 'Available skills' table" % name)
        elif count > 1:
            err(20, readme, "skills/%s is listed %d times" % (name, count))
    for name in sorted(set(linked) - set(skills)):
        err(21, readme,
            "table lists '%s' but skills/%s does not exist" % (name, name))


def check_marketplace(skills):
    manifest = os.path.join(REPO, ".claude-plugin", "marketplace.json")
    if not os.path.isfile(manifest):
        err(30, manifest, "marketplace manifest is missing")
        return
    try:
        data = json.loads(read_text(manifest))
    except ValueError as exc:
        err(30, manifest, "invalid JSON: %s" % exc)
        return
    plugins = {}
    for plugin in data.get("plugins", []):
        pname = plugin.get("name", "")
        if pname in plugins:
            err(31, manifest, "duplicate plugin entry '%s'" % pname)
        plugins[pname] = plugin
    for name in skills:
        plugin = plugins.get(name)
        if plugin is None:
            err(31, manifest, "skills/%s has no plugin entry" % name)
            continue
        skill_paths = plugin.get("skills", [])
        if len(skill_paths) != 1 or \
                os.path.basename(skill_paths[0].rstrip("/")) != name:
            err(31, manifest,
                "plugin '%s' must list exactly ./skills/%s" % (name, name))
    for pname in sorted(set(plugins) - set(skills)):
        err(31, manifest,
            "plugin '%s' has no matching skills/ directory" % pname)


def glob_to_regex(pattern):
    """Translate a restricted glob to a regex.

    Supports '**' (matches across '/') and '*' (matches within one path
    segment); every other character is matched literally.
    """
    out = ["^"]
    i, n = 0, len(pattern)
    while i < n:
        if pattern[i] == "*":
            if i + 1 < n and pattern[i + 1] == "*":
                out.append(".*")
                i += 2
            else:
                out.append("[^/]*")
                i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    out.append("$")
    return re.compile("".join(out))


def check_skills_json(skills):
    manifest = os.path.join(REPO, "skills.json")
    if not os.path.isfile(manifest):
        err(50, manifest, "skills.json manifest is missing")
        return
    try:
        data = json.loads(read_text(manifest))
    except ValueError as exc:
        err(50, manifest, "invalid JSON: %s" % exc)
        return
    if data.get("manifestVersion") != 1:
        err(51, manifest,
            "manifestVersion must be 1 (found: %r)"
            % data.get("manifestVersion"))
    # Each entry's one-line description must match the marketplace listing so
    # the two manifests never drift apart.
    mkt_desc = {}
    mkt_path = os.path.join(REPO, ".claude-plugin", "marketplace.json")
    try:
        mkt = json.loads(read_text(mkt_path))
        for plugin in mkt.get("plugins", []):
            mkt_desc[plugin.get("name", "")] = plugin.get("description", "")
    except (OSError, ValueError):
        mkt_desc = {}
    entries = {}
    for entry in data.get("skills", []):
        name = entry.get("name", "")
        for field in ("name", "version", "owner", "description"):
            if not entry.get(field):
                err(52, manifest,
                    "entry '%s' is missing required field '%s'"
                    % (name or "?", field))
        if name:
            if not MANIFEST_NAME_RE.match(name):
                err(53, manifest,
                    "name '%s' is not lowercase kebab-case" % name)
            if name in entries:
                err(53, manifest, "duplicate entry '%s'" % name)
            entries[name] = entry
        for agent in entry.get("agents", []):
            if agent not in ("claude", "codex"):
                err(57, manifest,
                    "entry '%s' lists unsupported agent '%s'"
                    % (name or "?", agent))
    for name in skills:
        entry = entries.get(name)
        if entry is None:
            err(54, manifest, "skills/%s has no manifest entry" % name)
            continue
        path = entry.get("path", "")
        doc = entry.get("docPath", "")
        for field, value in (("path", path), ("docPath", doc)):
            if value.startswith("/") or ".." in value.split("/"):
                err(55, manifest,
                    "entry '%s' has unsafe %s '%s'" % (name, field, value))
        if path and path.rstrip("/") != "skills/%s" % name:
            err(55, manifest,
                "entry '%s' path must be skills/%s (found '%s')"
                % (name, name, path))
        if doc and not os.path.isfile(os.path.join(REPO, doc)):
            err(55, manifest,
                "entry '%s' docPath '%s' does not exist" % (name, doc))
        target = doc or "skills/%s/SKILL.md" % name
        files = entry.get("files", [])
        if not files or not any(glob_to_regex(p).match(target) for p in files):
            err(56, manifest,
                "entry '%s' files must cover its SKILL.md (%s)"
                % (name, target))
        desc = entry.get("description", "")
        if name in mkt_desc and desc != mkt_desc[name]:
            err(58, manifest,
                "entry '%s' description does not match marketplace.json"
                % name)
        parsed = parse_frontmatter(read_text(os.path.join(SKILLS_DIR, name,
                                                          "SKILL.md")))
        fm_version = skill_version(parsed[1]) if parsed else ""
        if fm_version and entry.get("version") != fm_version:
            err(59, manifest,
                "entry '%s' version '%s' does not match SKILL.md metadata "
                "version '%s'" % (name, entry.get("version"), fm_version))
    for name in sorted(set(entries) - set(skills)):
        err(54, manifest,
            "entry '%s' has no matching skills/ directory" % name)


def check_roadmap(skills):
    roadmap = os.path.join(REPO, "ROADMAP.md")
    lines = read_text(roadmap).splitlines()
    for name in skills:
        marker = "`%s`" % name
        rows = [line for line in lines
                if marker in line and line.lstrip().startswith("|")]
        if not any("available" in row.lower() for row in rows):
            err(40, roadmap,
                "skills/%s is not marked 'available' in any roadmap table"
                % name)


def main():
    if not os.path.isdir(SKILLS_DIR):
        print("[QLS000] skills/ directory not found", file=sys.stderr)
        return 1
    skills = sorted(entry for entry in os.listdir(SKILLS_DIR)
                    if os.path.isdir(os.path.join(SKILLS_DIR, entry)))
    for name in skills:
        check_skill(name)
        check_scripts(name)
    check_readme(skills)
    check_marketplace(skills)
    check_skills_json(skills)
    check_roadmap(skills)
    if errors:
        for line in errors:
            print(line, file=sys.stderr)
        print("check-catalog: %d problem(s) found" % len(errors),
              file=sys.stderr)
        return 1
    print("check-catalog: %d skills OK" % len(skills))
    return 0


if __name__ == "__main__":
    sys.exit(main())
