#!/usr/bin/env python3
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
"""qcom-release-report.py - turn a capture into a support report.

Reads the plain-text capture produced by qcom-release-collect.sh (from a
path or on stdin) and prints the Qualcomm Linux release report: device
identity, firmware inventory, build provenance, a release fingerprint,
consistency findings and a confidence assessment.

The capture is the only input, so this also serves the offline case where
someone pastes the contents of /etc/os-release, /etc/buildinfo and
/sys/kernel/debug/qcom_socinfo/*/name from a board you cannot reach.

    qcom-release-report.py capture.txt
    qcom-release-collect.sh | qcom-release-report.py -
    qcom-release-report.py capture.txt --fingerprint
    qcom-release-report.py capture.txt --json

Exits 0 when a report was produced, 1 when the input has no recognizable
sections. Consistency findings never change the exit status.
"""

import argparse
import json
import re
import sys

SECTION_RE = re.compile(r"^=== SECTION: ([A-Z0-9_]+) ===$")

# The sections qcom-release-collect.sh emits. A capture that shares none of
# these is not a capture, however well-formed its banners look.
KNOWN_SECTIONS = frozenset([
    "MODEL", "COMPATIBLE", "SOC0", "OS_RELEASE", "BUILDINFO",
    "SOCINFO_NAMES", "SOCINFO_SCALARS", "EFI_LOADER", "KERNEL", "UPTIME",
    "SYSTEMD", "COLLECTOR",
])

# Findings are reported most-severe-first regardless of check order.
SEVERITY_ORDER = {"high": 0, "medium": 1, "info": 2}
UNAVAIL_RE = re.compile(r"^<unavailable: (.*)>$")
BUILD_ID_CI_RE = re.compile(r"^(\d+)-(\d+)$")

# /etc/buildinfo names layers by the basename of their checkout directory,
# which hides the two most important ones behind generic names.
LAYER_ALIASES = {
    "repo": "meta-qcom",
    "meta": "openembedded-core",
}

# Layers worth calling out first in the provenance table.
LAYER_HIGHLIGHTS = [
    "repo",
    "meta-qcom",
    "meta-qcom-distro",
    "meta",
    "meta-ai",
    "meta-updater",
    "meta-virtualization",
]

ACTIONS_RUN_URL = "https://github.com/qualcomm-linux/meta-qcom/actions/runs/%s"


class Capture(object):
    """A parsed collector capture."""

    def __init__(self, text):
        self.sections = {}
        self.unavailable = {}
        self._split(text)
        self.os_release = self._parse_os_release(self.body("OS_RELEASE"))
        self.build_config, self.layers = self._parse_buildinfo(
            self.body("BUILDINFO"))
        self.soc0 = self._parse_kv(self.body("SOC0"))
        self.socinfo = self._parse_kv(self.body("SOCINFO_NAMES"))
        self.scalars = self._parse_kv(self.body("SOCINFO_SCALARS"))
        self.efi = self._parse_kv(self.body("EFI_LOADER"))
        self.collector = self._parse_kv(self.body("COLLECTOR"))

    def _split(self, text):
        name = None
        lines = []
        for line in text.splitlines():
            match = SECTION_RE.match(line.strip())
            if match:
                if name is not None:
                    self._store(name, lines)
                name = match.group(1)
                lines = []
            elif name is not None:
                lines.append(line)
        if name is not None:
            self._store(name, lines)

    def _store(self, name, lines):
        body = "\n".join(lines).strip()
        match = UNAVAIL_RE.match(body)
        if match:
            self.unavailable[name] = match.group(1)
            body = ""
        self.sections[name] = body

    def body(self, name):
        return self.sections.get(name, "")

    def has(self, name):
        return bool(self.sections.get(name))

    def state(self, name):
        """'present', 'not collected', or 'not present: <reason>'.

        A section absent from the capture was never collected (offline
        captures routinely carry only some of them); a section carrying an
        <unavailable: ...> marker was collected and found missing on the
        target. Conflating the two tells the reader a file is absent from a
        board nobody looked at.
        """
        if self.sections.get(name):
            return "present"
        if name in self.unavailable:
            return "not present: %s" % self.unavailable[name]
        if name in self.sections:
            return "not present"
        return "not collected"

    @staticmethod
    def _parse_kv(text):
        values = {}
        for line in text.splitlines():
            if " = " not in line:
                continue
            key, value = line.split(" = ", 1)
            values[key.strip()] = value.strip()
        return values

    @staticmethod
    def _parse_os_release(text):
        values = {}
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[key.strip()] = value
        return values

    @staticmethod
    def _parse_buildinfo(text):
        config = {}
        layers = {}
        mode = "config"
        for line in text.splitlines():
            line = line.strip()
            if not line or set(line) <= set("-|"):
                continue
            if line.startswith("Build Configuration:"):
                mode = "config"
                continue
            if line.startswith("Layer Revisions:"):
                mode = "layers"
                continue
            if " = " not in line:
                continue
            # Split on the first " = ": the class pads names to 17 columns,
            # but longer names (meta-virtualization) break the alignment.
            key, value = line.split(" = ", 1)
            key = key.strip()
            value = value.strip()
            if mode == "config":
                config[key] = value
                continue
            modified = value.endswith("-- modified")
            if modified:
                value = value[: -len("-- modified")].strip()
            branch, _, revision = value.partition(":")
            layers[key] = {
                "branch": branch,
                "revision": revision,
                "modified": modified,
            }
        return config, layers


def short(sha, length=8):
    return sha[:length] if sha else ""


def compact(value):
    """Shorten any full-length git SHA embedded in a version string."""
    return re.sub(r"\b([0-9a-f]{8})[0-9a-f]{12,32}\b", r"\1", value or "")


def uefi_version(value):
    """'Qualcomm Technologies, Inc. 24614.1796' -> '24614.1796'."""
    if not value:
        return ""
    tail = value.split()[-1]
    return tail if re.match(r"^[0-9][0-9.]*$", tail) else value


def decode_build_id(build_id):
    """Classify os-release BUILD_ID; see references/release-sources.md."""
    if not build_id:
        return ("absent", "no BUILD_ID in /etc/os-release", None)
    if build_id.startswith("local-"):
        return ("local", "locally built image (BUILD_ID = local-<DATETIME>)",
                None)
    match = BUILD_ID_CI_RE.match(build_id)
    if match:
        return ("ci", "meta-qcom CI run %s attempt %s"
                % (match.group(1), match.group(2)),
                ACTIONS_RUN_URL % match.group(1))
    return ("unknown", "unrecognized BUILD_ID format", None)


def parse_build_string(value):
    """Split a firmware build string into its parts.

    BOOT.MXF.1.0.c1-00532-KODIAKLA-1
      family BOOT, branch MXF.1.0.c1, build 00532, platform KODIAKLA,
      release 1
    """
    parts = value.split("-")
    head = parts[0]
    family = head.split(".")[0]
    branch = head[len(family) + 1:] if "." in head else ""
    return {
        "family": family,
        "branch": branch,
        "build": parts[1] if len(parts) > 1 else "",
        "platform": parts[2] if len(parts) > 2 else "",
        "release": parts[3] if len(parts) > 3 else "",
    }


def firmware_entries(cap):
    """Subsystem -> {build, index, oem, variant} for non-empty entries."""
    entries = {}
    for key, value in cap.socinfo.items():
        if "." in key:
            continue
        entries[key] = {"build": value}
    for key, value in cap.socinfo.items():
        if "." not in key:
            continue
        subsystem, field = key.rsplit(".", 1)
        if subsystem in entries:
            entries[subsystem][field] = value
    return entries


def snapshot_sha(os_release):
    """The SHA embedded in a '<ver>+snapshot-<sha>' DISTRO_VERSION."""
    for field in ("VERSION_ID", "VERSION"):
        value = os_release.get(field, "")
        match = re.search(r"snapshot[-+.]?([0-9a-f]{7,40})", value)
        if match:
            return match.group(1)
    return ""


def image_type(cap):
    kind = decode_build_id(cap.os_release.get("BUILD_ID", ""))[0]
    is_snapshot = bool(snapshot_sha(cap.os_release))
    if kind == "local":
        return "locally generated build"
    if kind == "ci":
        return ("snapshot/CI build" if is_snapshot
                else "release build from meta-qcom CI")
    if is_snapshot:
        return "snapshot build (no CI build identifier)"
    if kind == "unknown":
        return "provenance unclear (unrecognized BUILD_ID)"
    distro_id = cap.os_release.get("ID", "")
    if distro_id and distro_id != "qcom-distro" and not cap.layers:
        # e.g. a Qualcomm Debian/Ubuntu image: no Yocto provenance to look
        # for, so do not imply a meta-qcom build that was never made.
        return "%s image - not a meta-qcom/Yocto build" % distro_id
    if cap.os_release:
        # Absent BUILD_ID covers an official release zip *and* any custom
        # kas setup, so it is not evidence of a release image.
        return "no meta-qcom CI build identifier (official release image or custom kas build)"
    return "unknown"


def find_layer(cap, name):
    """Look a layer up by its real name or by its checkout basename."""
    if name in cap.layers:
        return cap.layers[name]
    for basename, alias in LAYER_ALIASES.items():
        if alias == name and basename in cap.layers:
            return cap.layers[basename]
    return None


def fingerprint(cap):
    fw = firmware_entries(cap)
    meta_qcom = find_layer(cap, "meta-qcom")
    oe_core = find_layer(cap, "openembedded-core")
    machine = cap.soc0.get("machine", "")
    board = (cap.body("COMPATIBLE").split() or [""])[0]
    fields = [
        ("QLI", compact(cap.os_release.get("VERSION_ID", "")),
         "os-release VERSION_ID"),
        ("BUILD", cap.os_release.get("BUILD_ID", ""), "os-release BUILD_ID"),
        ("DISTRO", cap.os_release.get("ID", ""), "os-release ID"),
        ("MACHINE", "/".join([p for p in (machine, board) if p]),
         "soc0/machine + device-tree compatible"),
        ("META_QCOM", short(meta_qcom["revision"]) if meta_qcom else "",
         "buildinfo 'repo' line"),
        ("OE", short(oe_core["revision"]) if oe_core else "",
         "buildinfo 'meta' line"),
        ("BOOT", fw.get("boot", {}).get("build", ""), "socinfo boot/name"),
        ("TZ", fw.get("tz", {}).get("build", ""), "socinfo tz/name"),
        ("UEFI", uefi_version(cap.efi.get("LoaderFirmwareInfo", "")),
         "EFI LoaderFirmwareInfo"),
    ]
    return [(k, v or "<unavailable>", src) for k, v, src in fields]


def fingerprint_line(cap):
    return "|".join("%s:%s" % (k, v) for k, v, _ in fingerprint(cap))


def findings(cap):
    """Consistency checks. Returns [(severity, text), ...]."""
    out = []
    fw = firmware_entries(cap)

    dirty = sorted(name for name, info in cap.layers.items()
                   if info["modified"])
    if dirty:
        out.append(("high",
                    "Layer(s) %s were dirty at build time (' -- modified'); "
                    "the image cannot be reproduced from git alone."
                    % ", ".join(LAYER_ALIASES.get(n, n) for n in dirty)))

    patched = sorted(name for name, info in cap.layers.items()
                     if info["branch"].startswith("patched-"))
    if patched:
        out.append(("info",
                    "kas applied patches to %s; the recorded revision is the "
                    "patched tree, not the upstream branch tip."
                    % ", ".join(LAYER_ALIASES.get(n, n) for n in patched)))

    kind, note, url = decode_build_id(cap.os_release.get("BUILD_ID", ""))
    if kind == "local":
        out.append(("info",
                    "Locally built image - no CI artifact to correlate with."))
    elif kind == "absent" and cap.os_release:
        out.append(("medium",
                    "No BUILD_ID: the image was not built from meta-qcom's "
                    "kas CI config, so it cannot be mapped to a CI run."))
    elif kind == "unknown":
        out.append(("medium", "BUILD_ID '%s' does not match either known "
                    "format (local-<DATETIME> or <run_id>-<attempt>)."
                    % cap.os_release.get("BUILD_ID", "")))

    if not cap.os_release:
        out.append(("high", "No /etc/os-release: the software version cannot "
                    "be identified at all."))
    if not cap.layers:
        out.append(("medium",
                    "No /etc/buildinfo layer revisions: there is no git-level "
                    "provenance for this image."))

    # os-release and buildinfo must agree; they are written by the same build.
    sha = snapshot_sha(cap.os_release)
    oe_core = find_layer(cap, "openembedded-core")
    if sha and oe_core and oe_core["revision"]:
        if not oe_core["revision"].startswith(sha):
            out.append(("high",
                        "VERSION_ID snapshot SHA (%s) does not match the "
                        "openembedded-core revision in /etc/buildinfo (%s); "
                        "the two metadata sources disagree."
                        % (short(sha), short(oe_core["revision"]))))
    distro_version = cap.build_config.get("DISTRO_VERSION", "")
    os_version = cap.os_release.get("VERSION", "")
    if distro_version and os_version and distro_version != os_version:
        out.append(("high",
                    "buildinfo DISTRO_VERSION (%s) differs from os-release "
                    "VERSION (%s)." % (distro_version, os_version)))

    boot_build = fw.get("boot", {}).get("build", "")
    uefi = cap.efi.get("LoaderFirmwareInfo", "")
    if not boot_build and not uefi:
        out.append(("high", "Boot firmware version is unavailable from both "
                    "socinfo and the EFI loader variables."))

    if not fw and "SOCINFO_NAMES" in cap.unavailable:
        out.append(("medium",
                    "Firmware inventory not collected (%s). This is a "
                    "collection problem, not a firmware fault - re-run as "
                    "root with debugfs mounted."
                    % cap.unavailable["SOCINFO_NAMES"]))

    # Within one firmware family every subsystem should carry the same build.
    families = {}
    for subsystem, info in fw.items():
        parsed = parse_build_string(info["build"])
        families.setdefault(parsed["family"], {}).setdefault(
            info["build"], []).append(subsystem)
    for family, builds in sorted(families.items()):
        if len(builds) > 1:
            detail = "; ".join(
                "%s on %s" % (build, ", ".join(sorted(subs)))
                for build, subs in sorted(builds.items()))
            out.append(("high", "Mixed %s firmware: %s." % (family, detail)))

    # Deliberately no SoC-vs-variant check: socinfo chip_id is a
    # firmware-supplied string with no guaranteed relationship to the boot
    # firmware variant, so matching them would fire on healthy boards whose
    # naming happens not to overlap.

    # Fix 3: the contract promises most-severe-first; check order must not
    # decide presentation order.
    return sorted(out, key=lambda item: SEVERITY_ORDER.get(item[0], 99))


def assessment(cap):
    """Per-question and overall confidence."""
    fw = firmware_entries(cap)
    has_os = bool(cap.os_release)
    has_layers = bool(cap.layers)
    has_fw = bool(fw.get("boot", {}).get("build")
                  or cap.efi.get("LoaderFirmwareInfo"))
    dirty = any(info["modified"] for info in cap.layers.values())
    kind = decode_build_id(cap.os_release.get("BUILD_ID", ""))[0]

    per_question = [
        ("identify the software version", "HIGH" if has_os else "LOW"),
        ("identify the boot firmware version", "HIGH" if has_fw else "LOW"),
        ("correlate with a known build",
         "HIGH" if kind == "ci" else "MEDIUM" if has_layers else "LOW"),
        ("reproduce the environment",
         "LOW" if not has_layers else "MEDIUM" if dirty else "HIGH"),
    ]

    if has_os and has_layers and has_fw and not dirty:
        overall = "HIGH"
    elif has_os and (has_layers or has_fw):
        overall = "MEDIUM"
    else:
        overall = "LOW"
    return per_question, overall


def table(rows, headers):
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    lines = ["| " + " | ".join(h.ljust(widths[i])
                               for i, h in enumerate(headers)) + " |",
             "|-" + "-|-".join("-" * w for w in widths) + "-|"]
    for row in rows:
        lines.append("| " + " | ".join(cell.ljust(widths[i])
                                       for i, cell in enumerate(row)) + " |")
    return lines


def render(cap):
    out = []
    add = out.append
    fw = firmware_entries(cap)

    add("# Device Identification")
    add("")
    add("Model:        %s" % (cap.body("MODEL") or "<unavailable>"))
    soc = " / ".join(
        [v for v in (cap.soc0.get("machine"), cap.soc0.get("family"),
                     cap.soc0.get("soc_id"), cap.soc0.get("revision")) if v])
    add("SoC:          %s" % (soc or "<unavailable>"))
    add("QLI release:  %s" % (cap.os_release.get("PRETTY_NAME")
                              or "<unavailable>"))
    add("Version ID:   %s" % (cap.os_release.get("VERSION_ID")
                              or "<unavailable>"))
    build_id = cap.os_release.get("BUILD_ID", "")
    _, note, url = decode_build_id(build_id)
    add("Build ID:     %s (%s)" % (build_id or "<absent>", note))
    if url:
        add("              %s" % url)
    add("Image type:   %s" % image_type(cap))
    add("Kernel:       %s" % (cap.body("KERNEL") or "<unavailable>"))
    add("")

    add("# Firmware Versions")
    add("")
    if fw:
        rows = []
        for subsystem in sorted(fw):
            parsed = parse_build_string(fw[subsystem]["build"])
            rows.append([subsystem, parsed["family"], fw[subsystem]["build"],
                         parsed["platform"] or "-",
                         parsed["release"] or "-"])
        out.extend(table(rows, ["Subsystem", "Component", "Build string",
                                "Platform", "Release"]))
        variant = fw.get("boot", {}).get("variant")
        oem = fw.get("boot", {}).get("oem")
        if variant or oem:
            add("")
            if variant:
                add("Boot firmware variant: %s" % variant)
            if oem:
                add("Boot firmware built on: %s" % oem)
        add("")
        add("Subsystems with an empty socinfo name are omitted: that is "
            "normal, it means the subsystem is absent or not loaded.")
    else:
        add("<unavailable: %s>" % cap.state("SOCINFO_NAMES"))
    add("")
    if cap.efi:
        for key in ("LoaderFirmwareInfo", "LoaderFirmwareType", "LoaderInfo",
                    "LoaderEntrySelected"):
            if cap.efi.get(key):
                add("%-21s %s" % (key + ":", cap.efi[key]))
    else:
        add("EFI loader variables: <unavailable: %s>"
            % cap.state("EFI_LOADER"))
    add("")

    add("# Build Provenance")
    add("")
    if cap.layers:
        if cap.build_config:
            for key in sorted(cap.build_config):
                add("%s = %s" % (key, cap.build_config[key]))
            add("")
        ordered = [n for n in LAYER_HIGHLIGHTS if n in cap.layers]
        ordered += [n for n in sorted(cap.layers) if n not in ordered]
        rows = []
        for name in ordered:
            info = cap.layers[name]
            alias = LAYER_ALIASES.get(name)
            label = "%s (%s)" % (name, alias) if alias else name
            flags = []
            if info["modified"]:
                flags.append("modified")
            if info["branch"].startswith("patched-"):
                flags.append("kas-patched")
            rows.append([label, info["branch"], info["revision"],
                         ", ".join(flags) or "-"])
        out.extend(table(rows, ["Layer", "Branch", "Revision", "Flags"]))
    else:
        add("<unavailable: %s>" % cap.state("BUILDINFO"))
    add("")

    add("# Release Correlation")
    add("")
    add("RELEASE_FINGERPRINT")
    for key, value, source in fingerprint(cap):
        add("  %-9s = %-40s # %s" % (key, value, source))
    add("")
    add("One-line form:")
    add("  %s" % fingerprint_line(cap))
    add("")

    add("# Key Findings")
    add("")
    items = findings(cap)
    if items:
        for severity, text in items:
            add("- [%s] %s" % (severity, text))
    else:
        add("- No consistency issues detected.")
    add("")

    add("# Support Assessment")
    add("")
    per_question, overall = assessment(cap)
    for question, level in per_question:
        add("- %-36s %s" % (question, level))
    add("")
    sources = []
    for name, label in (("OS_RELEASE", "/etc/os-release"),
                        ("BUILDINFO", "/etc/buildinfo"),
                        ("SOCINFO_NAMES", "qcom_socinfo"),
                        ("EFI_LOADER", "EFI loader variables")):
        sources.append("%s: %s" % (label, cap.state(name)))
    add("Sources: %s" % "; ".join(sources))
    if cap.collector:
        add("Collected as root: %s; debugfs: %s"
            % (cap.collector.get("ran_as_root", "unknown"),
               cap.collector.get("debugfs", "unknown")))
    add("")
    add("# Overall Confidence")
    add("")
    add(overall)
    return "\n".join(out)


def as_json(cap):
    per_question, overall = assessment(cap)
    return {
        "identity": {
            "model": cap.body("MODEL"),
            "soc0": cap.soc0,
            "kernel": cap.body("KERNEL"),
            "image_type": image_type(cap),
        },
        "os_release": cap.os_release,
        "build_config": cap.build_config,
        "layers": cap.layers,
        "firmware": firmware_entries(cap),
        "socinfo_scalars": cap.scalars,
        "efi": cap.efi,
        "fingerprint": dict((k, v) for k, v, _ in fingerprint(cap)),
        "fingerprint_line": fingerprint_line(cap),
        "findings": [{"severity": s, "text": t} for s, t in findings(cap)],
        "assessment": dict(per_question),
        "confidence": overall,
        "unavailable": cap.unavailable,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("capture", nargs="?", default="-",
                    help="capture file from qcom-release-collect.sh "
                         "('-' or omitted reads stdin)")
    ap.add_argument("--json", action="store_true",
                    help="emit the parsed data and findings as JSON")
    ap.add_argument("--fingerprint", action="store_true",
                    help="print only the one-line release fingerprint")
    args = ap.parse_args()

    if args.capture == "-":
        text = sys.stdin.read()
    else:
        with open(args.capture, "r", errors="replace") as handle:
            text = handle.read()

    cap = Capture(text)
    if not set(cap.sections) & KNOWN_SECTIONS:
        sys.stderr.write(
            "error: no recognized '=== SECTION: ... ===' banners found - "
            "this does not look like a qcom-release-collect.sh capture\n")
        return 1

    if args.fingerprint:
        print(fingerprint_line(cap))
    elif args.json:
        print(json.dumps(as_json(cap), indent=2, sort_keys=True))
    else:
        print(render(cap))
    return 0


if __name__ == "__main__":
    sys.exit(main())
