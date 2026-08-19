# Release report format and assessment models

This is the output contract for the release report: the report skeleton, the
release fingerprint, the consistency checks worth raising, and how to score
confidence. `scripts/qcom-release-report.py` implements all of it; this
document is what to follow when producing the report by hand (for example
from values a customer pasted into a ticket) and how to read what the script
emits.

Parse rules for the underlying files live in
[release-sources.md](release-sources.md).

## Report skeleton

```text
# Device Identification     model, SoC, QLI release, BUILD_ID + decode, image type, kernel
# Firmware Versions         per-subsystem table, then the EFI loader values
# Build Provenance          DISTRO/DISTRO_VERSION, then the layer table
# Release Correlation       RELEASE_FINGERPRINT
# Key Findings              consistency checks, most severe first
# Support Assessment        per-question confidence + which sources were present
# Overall Confidence        HIGH / MEDIUM / LOW
```

Report every unavailable value explicitly as `<unavailable>` rather than
dropping the row. For Customer Engineering, "the board could not tell us its
boot firmware version" is a finding, not a blank.

Distinguish three states, because they call for different responses:

| State | Meaning | What to do |
|---|---|---|
| `present` | the source was collected and parsed | — |
| `not collected` | the capture has no such section at all | ask for a fuller capture |
| `not present: <reason>` | the source was looked for and was missing or unreadable on the target | report it; the reason says whether root or a mount would fix it |

Never report `not collected` as though the file were absent from the board:
an offline capture routinely carries only the sections someone pasted.

## RELEASE_FINGERPRINT

One block that identifies the image, plus a one-line form to paste into a
ticket. Shorten git SHAs to 8 characters and strip the vendor prefix from
the UEFI version, so the line stays readable.

```text
RELEASE_FINGERPRINT
  QLI       = 2.99-snapshot-f527b723                   # os-release VERSION_ID
  BUILD     = 32085063241-1                            # os-release BUILD_ID
  DISTRO    = qcom-distro                              # os-release ID
  MACHINE   = QCS9100/qcom,qcs9100-ride-r3             # soc0/machine + device-tree compatible
  META_QCOM = 2c63ba21                                 # buildinfo 'repo' line
  OE        = f527b723                                 # buildinfo 'meta' line
  BOOT      = BOOT.MXF.1.0.c1-00532-KODIAKLA-1         # socinfo boot/name
  TZ        = TZ.XF.5.29.1-00171.1-KODIAKAAAAANAAZT-1  # socinfo tz/name
  UEFI      = 24614.1796                               # EFI LoaderFirmwareInfo
```

One-line form:

```text
QLI:2.99-snapshot-f527b723|BUILD:32085063241-1|DISTRO:qcom-distro|MACHINE:QCS9100/qcom,qcs9100-ride-r3|META_QCOM:2c63ba21|OE:f527b723|BOOT:BOOT.MXF.1.0.c1-00532-KODIAKLA-1|TZ:TZ.XF.5.29.1-00171.1-KODIAKAAAAANAAZT-1|UEFI:24614.1796
```

`META_QCOM` comes from the `repo` line and `OE` from the `meta` line — see
the layer-naming section of [release-sources.md](release-sources.md) before
quoting either.

## Consistency checks

Raise these, each with the evidence that triggered it. Emit them ordered
`high` → `medium` → `info`, independent of the order the checks run in.

| Finding | Trigger | Severity |
|---|---|---|
| Not reproducible | a layer line ends `-- modified` | high |
| Sources disagree | `VERSION_ID` snapshot SHA ≠ the `meta` layer revision, or buildinfo `DISTRO_VERSION` ≠ os-release `VERSION` | high |
| Boot firmware unknown | socinfo `boot/name` empty **and** no EFI `LoaderFirmwareInfo` | high |
| Genuinely mixed firmware | two subsystems in the same family carry different build strings | high |
| Software version unknown | no `/etc/os-release` | high |
| No layer provenance | no `/etc/buildinfo` | medium |
| No CI provenance | `BUILD_ID` absent | medium |
| Unrecognized BUILD_ID | matches neither `local-<DATETIME>` nor `<run_id>-<attempt>` | medium |
| Firmware inventory unavailable | every socinfo `name` empty, or the tree is unreadable | medium |
| Patched metadata | a layer branch is `patched-<sha>` | info |
| Local build | `BUILD_ID` starts with `local-` | info |

Wording matters for two of these:

- **Firmware inventory unavailable is a collection problem, not a firmware
  fault.** It means the capture was not taken as root, debugfs was not
  mounted, or the `qcom_socinfo` interface is absent. Say that, and say to
  re-run as root, instead of implying the board has no firmware.
- **Do not compare the SoC identity to the boot firmware `variant`.**
  socinfo `chip_id` is a firmware-supplied string with no guaranteed
  relationship to the variant name, so a "wrong firmware package" check
  built on matching them fires on healthy boards whose naming happens not
  to overlap. There is no validated SoC-to-variant mapping to check against.
- **Do not report different platform codenames across families.**
  `BOOT…KODIAKLA` + `TZ…KODIAKAAAAANAAZT` + `DSP…LEMANS` together is the
  healthy state of a LeMans board. Only disagreement *within* a family is
  a real finding.

## Confidence

Score what can be answered, not how many files exist — all four sources can
be present while a dirty layer still makes the environment unreproducible.

Per question:

| Question | HIGH | MEDIUM | LOW |
|---|---|---|---|
| identify the software version | `/etc/os-release` present | — | absent |
| identify the boot firmware version | socinfo `boot` or EFI `LoaderFirmwareInfo` present | — | neither |
| correlate with a known build | `BUILD_ID` resolves to a CI run | layer revisions available | neither |
| reproduce the environment | layer revisions, none modified | layer revisions, some modified | no `/etc/buildinfo` |

Overall:

| Level | Condition |
|---|---|
| HIGH | os-release **and** buildinfo **and** a firmware source, with no layer marked `-- modified` |
| MEDIUM | os-release plus at least one of buildinfo / a firmware source |
| LOW | os-release missing, or nothing else collected |

Close the report by stating which of the four sources were present, and
whether the capture was taken as root with debugfs mounted — that tells the
reader whether a better capture is available for the asking.
