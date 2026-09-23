---
name: qcom-kernel-platform-backport
description: >-
  Backport upstream board/platform enablement into the qualcomm-linux kernel
  LTS branch (qcom-6.18.y): identify the commits a platform needs, cherry-pick
  them preserving authorship under the UPSTREAM/BACKPORT/FROMGIT prefixes,
  prove no other platform regresses, validate on hardware, and open the pull
  request. Use when asked to "backport board support to 6.18", "get <board>
  working on the LTS kernel", "identify the patches to backport for
  <platform>", or "prepare a kernel PR for <board>". Do NOT use for a plain
  standalone kernel build (see qcom-kernel-qcom-next-build), for bumping a
  meta-qcom kernel SRCREV, or for building a full image (see
  qcom-yocto-build-image).
metadata:
  version: "0.1"
---

# Backport platform enablement to the qualcomm-linux LTS kernel

A board that is already enabled upstream usually will not work on the
qualcomm-linux LTS branch: the board DTS, the SoC dtsi deltas it depends on,
its bindings and a handful of driver fixes all landed in later releases. This
skill turns "make `<board>` work on `qcom-6.18.y`" into a reviewable series of
cherry-picks, validated locally and on hardware before the PR.

The worked example throughout is the Arduino UNO Q (`qrb2210-arduino-imola`,
QCM2290/"agatti"), backported to `qcom-6.18.y` as a 30-commit series. Replace
the platform identifiers with your own.

## Prerequisites

- A clone of [qualcomm-linux/kernel](https://github.com/qualcomm-linux/kernel)
  with mainline, `linux-next` and the qcom SoC tree as extra remotes — you
  need the upstream history to find and cherry-pick from:

  ```bash
  git remote add linux-next https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git
  git fetch linux-next --tags

  # Bjorn Andersson's qcom SoC tree: where Qualcomm platform patches land
  # first, before they reach linux-next and mainline.
  git remote add qcom https://git.kernel.org/pub/scm/linux/kernel/git/qcom/linux.git
  git fetch qcom --tags
  ```

- An aarch64 cross toolchain, plus `dtschema` for `CHECK_DTBS`
  (`pip install dtschema` in a venv; `dt-validate` must be on `PATH`).
- For hardware validation: a meta-qcom / BSP-layer checkout and either lab
  access (see `qcom-lava-log`) or a board (`qcom-flash-qdl`,
  `qcom-boot-validate`).
- `gh` authenticated, for reading CI results on the pull request.
- The helper scripts named below (`find-candidates.sh`, `backport-commit.sh`,
  `dtbs-compare.sh`, `check-series.sh`) live in this skill's `scripts/`
  directory and run from the kernel checkout. Invoke them by full path
  (`<skill-dir>/scripts/...`): a bare `scripts/...` there resolves into the
  kernel's own `scripts/` tree.

## 1. Pin down the platform and the target branch

Establish four facts before touching anything:

```bash
git log --oneline -1 qcom-6.18.y                  # target branch tip = your base
git ls-tree --name-only -r qcom-6.18.y arch/arm64/boot/dts/qcom/ | grep -i <soc>
git ls-tree --name-only -r linux-next/master arch/arm64/boot/dts/qcom/ | grep -i <board>
git log --oneline -1 --grep="<board>" linux-next/master   # where it landed upstream
```

- **Base**: the branch tip you will cherry-pick onto.
- **Board DTS name** upstream, and whether it exists on the branch at all.
- **SoC dtsi name on each side.** These often differ: upstream renamed
  `qcm2290.dtsi` to `agatti.dtsi` in v6.19, while the LTS branch still has the
  old name. Do **not** backport the rename — adapt each patch instead.
- **Which release** the board landed in, so you know the range to sweep.

Cache the branch's own subjects once; you will grep it constantly to tell what
is already backported:

```bash
git log --format="%h%x09%s" v6.18..qcom-6.18.y > /tmp/branch-subjects.txt
```

The branch carries thousands of `FROMLIST:`/`BACKPORT:` patches already, so
always check before adding anything.

## 2. Find the candidate commits

### Where to look, in order of maturity

Qualcomm platform patches flow **qcom SoC tree → linux-next → mainline**, so
sweep all three. Searching only mainline misses everything for a board enabled
in the current cycle.

| Tree | Ref | What it tells you |
|---|---|---|
| Mainline | `v<x>.<y>` tags | Released. Cherry-pick as `UPSTREAM:`. |
| qcom SoC tree | `qcom/for-next` | Queued by the maintainer, not yet released. Cherry-pick as `FROMGIT:`. |
| linux-next | `linux-next/master` | Integration; a commit here that is not in the qcom tree came via another subsystem tree. `FROMGIT:`. |

The qcom tree also carries per-release topic branches — `arm64-for-<ver>`
(which is where DTS lives nowadays; the old `dts-for-*` branches stopped at
6.7), plus `drivers-for-<ver>`, `clk-for-<ver>`, `arm32-for-<ver>` and their
`-fixes-for-` and `-defconfig-for-` variants. Each pull request the maintainer
sends is tagged to match (`qcom-arm64-for-7.3`, `qcom-clk-for-7.3`, ...), which
is how you tell *which release* an untagged commit is queued for:

```bash
git describe --contains --match 'qcom-*-for-*' <sha>   # -> qcom-arm64-for-7.3-2~28
```

Do not add `--all` to that command: git then ignores `--match` and reports the
nearest ref of any kind, such as a linux-next snapshot tag.

### Sweep

`scripts/find-candidates.sh` searches every listed tree, annotates each commit
with where it has got to, and flags whether the target branch already has it:

```bash
scripts/find-candidates.sh \
    --base qcom-6.18.y --upstream linux-next/master,qcom/for-next \
    --keywords "agatti,qcm2290,qrb2210,imola,pm4125"
```

Output is one line per commit — `sha | WHERE | IN-BASE? | subject` — where
`WHERE` is a release tag (`v7.1-rc1`), a qcom queue (`arm64-for-7.3`),
`in-next`, or `unmerged`.

Widen the net beyond the keyword sweep by walking the paths the board's DTS
actually uses — the bridge driver, the PHY, the clock controllers, the codec —
and by reading the board DTS itself for every `&label` it enables. Anything the
DTS references must exist in the SoC dtsi on the branch.

For a large area, delegate a subsystem sweep (display, audio, WiFi/BT, USB) to
a subagent and have it report *required vs optional vs excluded* with the
release tag and the in-branch status for each commit.

### Triage rules

Take it when the board genuinely needs it:

- the board DTS, its bindings, and the SoC dtsi nodes it references;
- driver support the DTS depends on (a bridge's Type-C support, a new
  compatible, a `spidev` table entry);
- fixes with a `Fixes:` tag against something already on the branch;
- a **dependency of a patch you are taking** — e.g. a vendor prefix in
  `Documentation/devicetree/bindings/vendor-prefixes.yaml`. Missing these is
  the most common cause of avoidable CI warnings.

Leave it out when it is not enablement:

- SoC dtsi **renames** and tree-wide cosmetic sweeps (lowercase hex, dropping
  GICv3 CPU masks) — pure churn for every other board;
- wide refactors (a UBWC rework, a version-detection rework) — especially when
  the branch has diverged locally in the same code;
- features the board does not have (IPA when there is no modem data path,
  camera pinctrl when there is no camera);
- accessory hardware (add-on panels, camera modules, carrier boards).

> **The "other board" exclusion does not survive a shared-file change.** Those
> rules filter by *board*. A commit that edits a shared file — the SoC dtsi, a
> binding — has to be reasoned about by *file*, because the rest of its upstream
> series may fix other files that include the very node you just changed.
> Taking half of a tree-wide fix leaves the tree partly converted, which is
> worse than uniformly wrong and is what a reviewer notices first.
>
> This is easy to get wrong. One series backported the PCIe `iommu-map`
> correction (four cells to five, as `#iommu-cells = <2>` requires) into
> `monaco.dtsi` and `monaco-monza-som.dtsi`, but filtered out the sibling
> commit for `monaco-evk-ifp-mezzanine.dtso` as "a different board" — leaving
> the only four-cell map in the family, against the SMMU it had just changed.
>
> After taking a commit that touches a shared file, sweep its series:
>
> ```bash
> # the rest of the same tree-wide fix
> git log --oneline "${since}..${upstream}" --grep="Fix the PCIe iommu-map"
> # who else references the node you changed?
> grep -rl '&pcie_smmu' arch/arm64/boot/dts/qcom/
> ```
>
> Search for the **label you changed**, not for files including the dtsi. An
> overlay consumes base-tree labels without including anything — the `.dtso` in
> the case above has no `#include` of `monaco.dtsi` at all, so a search for the
> dtsi finds every board in the family except the one that was actually wrong.
>
> Then assert the family agrees, rather than assuming it. Count the old and new
> forms across every file the label search returned; the old form must be gone:
>
> ```bash
> grep -c '<0x[0-9a-f]* &pcie_smmu 0x[0-9a-f]* 0x1>' <each file>   # want 0
> ```
>
> `dtbs-compare.sh --match` will not catch this on its own: the leftover file
> is usually as malformed after your series as before it, so it shows up as a
> *pre-existing* warning, not a new one.

When a needed patch is not upstream at all, say so plainly and scope it out
rather than inventing a local version — see *Known gaps* in the PR text.

## 3. Apply, preserving authorship

Use `scripts/backport-commit.sh`, which cherry-picks with the original author
intact, prefixes the subject, and appends your `Signed-off-by`:

```bash
scripts/backport-commit.sh <upstream-sha> UPSTREAM
scripts/backport-commit.sh <upstream-sha> BACKPORT "applied to qcm2290.dtsi, as the rename to agatti.dtsi is not part of this branch"
```

Prefixes, as the branch and its CI use them:

| Prefix | Meaning | `WHERE` column shows |
|---|---|---|
| `UPSTREAM:` | clean cherry-pick from a Linus tag | `v7.1-rc1` |
| `BACKPORT:` | needed adaptation; explain it in a `[you: ...]` note | any |
| `FROMGIT:` | in a maintainer tree / linux-next, not yet in a Linus tag | `arm64-for-7.3`, `in-next` |
| `FROMLIST:` | posted to a list, not merged | `unmerged` |

A commit queued in the qcom tree is a normal thing to take — `FROMGIT:` exists
for exactly that — but note it will rebase until it is merged, so record the
SHA you used and re-check it before the branch is rebased onto a new -rc.

> **Authorship is easy to destroy.** `git cherry-pick -n` followed by a
> separate `git commit` makes *you* the author of someone else's patch. And
> `git commit --amend` silently ignores `GIT_AUTHOR_*` — it keeps the existing
> author unless you pass `--author` explicitly. The helper script gets both
> right; verify with:
>
> ```bash
> git log --format="%h | A:%an <%ae> | C:%cn" <base>..HEAD
> ```

> **A clean cherry-pick is not always a faithful one.** `git cherry-pick` can
> succeed while quietly diverging from the posted patch: rename detection lands
> the diff on a differently-named file, or the 3-way merge drops a hunk whose
> content is already present. Neither conflicts, so nothing warns you, but the
> commit is now a `BACKPORT:` wearing an `UPSTREAM:` label — and
> `check-patch-compliance` compares diffs, so it fails there instead. Always
> check the file list, not just the exit status:
>
> ```bash
> git show --stat <upstream-sha>   # vs
> git show --stat HEAD
> ```
>
> `check-series.sh` flags this for the whole range.

### Getting a `Link:` when the commit has none

Every commit needs a `Link:` to the lore posting — CI fetches it with `b4` and
diffs it against your commit. Most upstream commits already carry one; when a
commit only has `Message-ID:`, derive `https://lore.kernel.org/r/<message-id>`.
`backport-commit.sh` does both for you and says so at pick time.

When there is neither, **do not guess** — a wrong `Link:` fails the fetch. And
do not expect to browse lore for it: `lore.kernel.org` sits behind Anubis bot
protection, so `WebFetch` and plain `curl` both get an "Access Denied" /
"Making sure you're not a bot!" page, the `?x=A` atom endpoint included.
`lkml.org` is gated the same way. Query patchwork instead:

```bash
curl -sS -G "https://patchwork.kernel.org/api/1.2/patches/" \
  --data-urlencode "q=<exact commit subject>" \
  --data-urlencode "order=-date"
# each result carries .date, .submitter.name, .msgid, .name
```

Then confirm the hit — subjects repeat across reposts *and* across unrelated
commits years apart (`hwmon: (ina2xx) Fix various overflow issues` exists
twice). Two checks that work:

- the posting timestamp should equal the commit's **author** date in UTC
  (`git log -1 --format=%ad --date=iso <sha>`);
- `https://patchwork.kernel.org/api/1.2/patches/<id>/` returns a `diff` field;
  diff it against `git show <sha>` — the same comparison `b4` makes.

When the subject is ambiguous, filter by project and date window instead:

```bash
curl -sS -G "https://patchwork.kernel.org/api/1.2/patches/" \
  --data-urlencode "project=linux-hwmon" \
  --data-urlencode "since=2026-06-09T00:00:00" \
  --data-urlencode "before=2026-06-13T00:00:00"
```

Order the series so it reads as a story and each commit stands alone: SoC dtsi
and bindings first, then the board, then driver support, then fixes, then
config. A partial backport (one hunk out of a tree-wide commit) is legitimate —
say so in the note.

You will not get that order right on the first pass, because you discover
prerequisites as you go. Do the picks in whatever order you find them, then
reorder once at the end with a scripted sequence editor rather than an
interactive rebase — and make it refuse to run if the commit set changes, so a
reorder can never silently drop a commit:

```bash
cat > /tmp/seq.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
todo="$1"; order=/tmp/order.txt        # one short SHA per line, desired order
have=$(grep -E '^pick ' "$todo" | awk '{print substr($2,1,12)}' | sort)
want=$(awk 'NF{print substr($1,1,12)}' "$order" | sort)
[ "$have" = "$want" ] || { echo "REFUSING: set differs" >&2; exit 1; }
: > "$todo"; while read -r s; do [ -n "$s" ] && echo "pick $s" >> "$todo"; done < "$order"
EOF
chmod +x /tmp/seq.sh
GIT_SEQUENCE_EDITOR=/tmp/seq.sh git rebase -i <base>
```

Apply message or content fixups the same way, with `git rebase --exec` running
a script that matches on `git log -1 --format=%s` and amends only the commits
it recognises. `--amend` preserves authorship, so this is safe to repeat.

## 4. Config and packaging

Enabling a driver in the kernel is only half of it.

### The branch has two config fragments that outrank defconfig

`arch/arm64/configs/qcom.config` and `arch/arm64/configs/prune.config` are
**downstream-only** — neither exists in mainline or linux-next — and meta-qcom's
kernel recipe merges them *on top of* `defconfig`:

```
cp ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ${B}/.config
${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config \
    ${KBUILD_CONFIG_EXTRA} <recipe .cfg fragments>
```

Order is defconfig → `prune.config` → `qcom.config` → BSP-layer `.cfg`
fragments, each overriding the previous. Grep all three before writing or
backporting any config change:

```bash
grep -nE "CONFIG_<SYM>\b" arch/arm64/configs/{defconfig,qcom.config,prune.config}
```

Two things this catches, both of which bite silently:

- **The defconfig commit may be redundant.** `qcom.config` already carried
  `CONFIG_SENSORS_EMC2305` and `CONFIG_QCA808X_PHY` for one platform, added by
  its own `QCLINUX:` commits. Dropping the locally authored `QCLINUX:` defconfig
  commit removed that series' *only* `check-patch-compliance` failure.
- **`prune.config` can disable a driver the board needs**, no matter what
  defconfig says — it carries `# CONFIG_SENSORS_INA2XX is not set`, which
  removed a board's power monitor from every image. The fix belongs in the BSP
  layer as a board `.cfg` fragment, since those merge last and therefore win.

Verify the outcome in the built config rather than by reasoning:
`build/tmp/work/<machine>-oe-linux/linux-qcom/<ver>/build/.config`. Read it
before starting another build — a later build with a different `DISTRO` reusing
the same `TMPDIR` deletes it.

- **defconfig**: add what the board's DTS needs *and the fragments do not
  already provide*. Note the prefix tension — the branch uses `QCLINUX:` for
  downstream-only config changes, but `check-patch-compliance` only accepts
  `FROMLIST|FROMGIT|UPSTREAM|BACKPORT` and demands a `Link:`. Either post it
  upstream and use `FROMLIST:`, or carry the option in the BSP layer instead,
  or expect to justify the failure.
- **Module packaging**: meta-qcom installs a *curated per-SoC list*
  (`packagegroup-machine-essential`), not `kernel-modules` wholesale. A driver
  built `=m` but absent from that list simply will not be in the image. This
  is the single most misleading failure mode: the kernel is correct, the
  device never appears. Add the missing ones in the machine conf of the BSP
  layer:

  ```
  MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS += " \
      kernel-module-anx7625 \
      kernel-module-spidev \
  "
  ```

  Package names come from the module file name (`anx7625.ko` →
  `kernel-module-anx7625`); confirm against the image manifest afterwards.

  ```bash
  grep -c kernel-module- tmp/deploy/images/<machine>/<image>.rootfs.manifest
  ```

  Two things make this harder than it looks. First, **the missing module is
  often not the device you are debugging.** A pin controller, clock controller
  or regulator that fails to install shows up as a *consumer* stuck in
  `devices_deferred` — on one board the only symptom was
  `sound platform: wait for supplier /soc@0/pinctrl@3440000/lpi_i2s4-active-state`
  and an empty `/proc/asound/cards`, because
  `kernel-module-pinctrl-sm8450-lpass-lpi` was absent. meta-qcom packaged the
  sm8550 and sc7280 variants but not the one that SoC binds through its
  fallback compatible. Read a deferred-probe line as a pointer to the
  *supplier*, then check whether that supplier's driver is `=m` and packaged.

  Second, **only some images use the curated list.** `core-image-base`
  (nodistro) does; the qcom-distro images install kernel modules broadly, so the
  same series can work there and fail on nodistro. That difference is useful:
  if a device works under qcom-distro and not nodistro, packaging is the cause,
  not the kernel. Validate both.

## 5. Verify locally, across every platform

Run these before pushing. The third one is the one that catches the mistake
that matters.

```bash
# a) the board's DTB builds and validates
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=y qcom/<board>.dtb

# b) any binding you touched still validates
make ARCH=arm64 DT_SCHEMA_FILES=<binding>.yaml dt_binding_check

# c) no OTHER platform regressed
scripts/dtbs-compare.sh --base qcom-6.18.y --head HEAD
```

`dtbs-compare.sh` builds every `qcom/*.dtb` at base and at head, filters build
progress lines, and prints only warnings that are **new** at head — the same
question CI asks, without its artifacts. Both sides are built from detached
worktrees of the named refs, so `--head` validates the reference you asked for
rather than whatever is checked out; a DTB that fails to build at head is a
hard failure, never a silent pass. Use `--subdir` to narrow the vendor
directory.

A full vendor sweep is slow — `dt-validate` is effectively serial, so ~300 DTBs
runs about an hour per side. `--match '^(monaco|qcs8300)'` narrows it to the
boards that share your SoC dtsi, which is sound **only** when every binding the
series touches is permissive (a widened enum, a `const` relaxed to `oneOf`, an
extended range): such a change cannot warn on a compatible it did not already
cover. Read the binding diffs first — if any change *adds* a constraint, run
the full sweep, because that is precisely the case that breaks another SoC.

> Do not hand-roll this comparison. Two traps bite immediately: `make` will not
> re-emit warnings for a `.dtb` that is already built, so a second run looks
> clean; and without `-k` the build stops at the first failing target, leaving
> the two sides having validated *different sets of boards* — which also looks
> clean. The script builds each target into a fresh output directory for
> exactly this reason.

> A shared binding is the classic trap. `qcom,qcm2290-dispcc.yaml` also matches
> `qcom,shikra-dispcc` on this branch, so backporting a commit that added
> `power-domains` to the schema's global `required:` list broke four Shikra
> DTBs that never described a CX domain. Validating only the new board missed
> it entirely; CI caught it. When a schema covers more than your SoC, scope the
> new constraint:
>
> ```yaml
> allOf:
>   - if:
>       not:
>         properties:
>           compatible:
>             contains:
>               const: qcom,shikra-dispcc
>     then:
>       required:
>         - power-domains
> ```

Then confirm the series is CI-clean on the mechanical rules:

```bash
scripts/check-series.sh --base qcom-6.18.y --head HEAD
```

It reports missing/invalid prefixes, missing `Link:` trailers, commits whose
author was lost, commits labelled `UPSTREAM:`/`FROMGIT:` whose content no longer
matches the upstream commit, and runs `checkpatch.pl` the way CI does.

## 6. Validate on hardware

A DTB that validates is not a board that boots. Build an image with the
backported kernel and run it:

1. Point the BSP kernel recipe at your branch (a `bbappend` with `SRC_URI`/
   `SRCREV` for the machine) and build — see `qcom-yocto-build-image`.
2. Flash and boot: `qcom-flash-qdl` + `qcom-boot-validate`, or submit to the
   lab and read the results with `qcom-lava-log`.
3. Check the subsystems the series claims to enable, from sysfs and dmesg
   rather than from userspace tools that may be absent:
   `/sys/class/drm/`, `/sys/class/typec/`, `/sys/class/remoteproc/*/state`,
   `/dev/video*`, `/sys/class/net/`, `/sys/class/leds/`,
   `/sys/kernel/debug/devices_deferred` (must be empty), and dmesg for oopses
   and probe failures.

Interpret results carefully before filing a bug against your own series:

- A UART with a `bluetooth`/serdev child has **no `/dev` node** — the tty is
  owned by serdev. Its absence is correct, not a regression.
- An intermittent failure that clears on reboot is usually an allocation race,
  not a static DT problem. `no-map` reserved regions can be refused with
  `-EBUSY` when an early allocation (initrd, kernel image) lands in the window,
  leaving the range as System RAM and making `memremap()` warn.
- Compare against a run of the *unmodified* branch before attributing a
  warning to your series.
- **A deferred consumer names its supplier, not the broken thing.** Resolve
  `devices_deferred` outwards: the entry tells you which supplier never
  appeared, and that supplier is what to investigate (missing module, missing
  clock, unbound pin controller).
- **`waiting_for_supplier` in a device's sysfs directory means fw_devlink is
  holding it, so probe was never called.** Distinguish that from a probe that
  ran and failed: the latter leaves a driver link and usually a dmesg line, the
  former leaves neither. `driver=NONE` plus zero dmesg mentions plus
  `waiting_for_supplier` is a DT/fw_devlink problem, not a driver bug — do not
  go reading the driver's probe path for it.
- Run the checks as *one shell line per subsystem, each independently
  guarded*, so a missing device cannot abort the rest:
  `... || true` after every command that may legitimately find nothing. And
  note the target is usually busybox: `head -40` is rejected, `head -n 40` is
  not. A malformed check silently yields no output, which reads exactly like
  "nothing wrong".
- Keep the greps narrow. `dmesg | grep -iE "emc2305|cci|i2c|..." | head -n 60`
  drowns in unrelated `i2c` matches and truncates before reaching the line you
  need; grep for the one driver name.

Validate **both** `core-image-base` (nodistro) and a qcom-distro image. They
install kernel modules by different rules, so a device that works in one and
not the other localises the fault to packaging immediately — see §4.

## 7. Open the PR and read the checkers

**Stop here and ask before pushing.** Summarize the series and the local
validation results, and let the user decide when to push and open the PR —
pushing and opening a pull request are remote writes, and this catalog's
skills are non-destructive by default.

Once the PR is open against `qcom-6.18.y`, the `Kernel Checkers`
workflow in `qualcomm-linux/kernel-config` runs `dtb-check`, `checkpatch`,
`check-patch-compliance`, `dt-binding-check`, `sparse-check` and
`check-uapi-headers`. Read the logs with:

```bash
gh run view <run-id> --repo qualcomm-linux/kernel-config
gh run view --repo qualcomm-linux/kernel-config --job <job-id> --log
```

Some failures are real and some are structural. Triage every one — do not
assume either way. See
[references/ci-checkers.md](references/ci-checkers.md) for what each checker
enforces, which failures a backport series cannot avoid, and how to justify
them in the PR.

## Report

Summarize for a reviewer: the series size and prefix breakdown, what each group
of commits enables, what was deliberately excluded and why, the hardware
validation result, and the known gaps. Keep the excluded list — it is the
evidence that the series stayed minimal.
