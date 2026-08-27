---
name: qcom-yocto-lava-ci-report
description: >-
  Produce a self-contained HTML CI/CD reliability report for a meta-qcom
  family layer (meta-qcom, meta-qcom-distro, meta-qcom-3rdparty) over a
  window of days: sweep every LAVA job the layer's CI submitted plus the
  GitHub Actions runs that built the images, separate real platform
  failures from test-harness artefacts and lab faults, quantify coverage
  lost to silent skips, and close with follow-up suggestions split by
  owner. Use when asked to "report on CI health", "why is CI so red",
  "analyse the last two weeks of LAVA results", "which boards are flaky",
  "where are we losing test coverage", or "what should we fix to
  stabilise CI". The skill reports and suggests only, it never edits a
  test suite or a layer. Do NOT use it to root-cause a single LAVA job
  from its URL or ID (see qcom-lava-log), or to run meta-qcom's CI-parity
  checks before opening a pull request (see qcom-yocto-pre-pr-checks).
metadata:
  version: "0.1"
---

# qcom-yocto-lava-ci-report

Turn a window of CI history into one HTML report that says what is actually
breaking, who owns each item, and how much each one costs.

The report answers a question a per-job dashboard cannot: a lab can show a
93% per-job pass rate while nearly every pull request comes back red, because
a pull request fans out to a hundred jobs. Getting from "everything is a bit
red" to "these eleven things are wrong, here is the evidence for each" needs a
sweep over the whole window, cross-referenced against the board inventory and
the builds that produced the images.

Scope is the meta-qcom family. The procedure is parameterised by the LAVA
project path and the GitHub repository, so it works for `meta-qcom`,
`meta-qcom-distro` and `meta-qcom-3rdparty` alike.

## When to use

- A maintainer asks why CI is red, or which boards are unreliable.
- Someone needs a written case to send to lab administrators, kernel
  developers, or the test-suite maintainers.
- Before or after a lab or test-framework change, to measure the difference.
- To find coverage that is silently missing rather than failing.

Do not use it for a single failing job (`qcom-lava-log`), for local pre-PR
checks (`qcom-yocto-pre-pr-checks`), or to submit jobs to the lab.

## Prerequisites

Tools on the host: `curl`, `python3`, `xz`, `jq`. No checkout of the layer is
needed; everything comes from public APIs.

**LAVA access.** The default instance is `lava.infra.foundries.io`. Most of
the sweep works anonymously:

| Endpoint | Anonymous |
|---|---|
| `/api/v0.2/jobs/` (list, filter, paginate) | yes |
| `/api/v0.2/jobs/<id>/` (metadata + definition) | yes |
| `/api/v0.2/jobs/<id>/tests/` (per-case results) | yes |
| `/api/v0.2/jobs/<id>/logs/` (console log) | yes |
| `/api/v0.2/devices/`, `/api/v0.2/workers/` | yes |
| `/api/v0.2/tags/` | **no — 401** |

`/devices/` returns tags as integer IDs. `/api/v0.2/tags/` is the only
endpoint that maps those IDs to names such as `display`, `has-bt` and
`has-camera`, and it is the only one that refuses anonymous access. **A LAVA
account with a personal API token is therefore a prerequisite** — without it
the device-tag audit cannot run, and that audit is where the report finds
whole device types with no real coverage.

Two ways to hold the token:

- Through the **`lava` MCP server**, which is how this skill was developed.
  Agents that have it can call the MCP tools directly for lab health and
  device inventory, and can read the same token for raw REST calls:

  ```sh
  TOKEN=$(jq -r '[.projects[].mcpServers.lava.headers["X-Lava-Token"] | select(.)][0]' ~/.claude.json)
  ```

- Directly, for any agent or host without the MCP server: create a token in
  the LAVA web UI under the user profile and send it as a header.

  ```sh
  curl -s -H "Authorization: Token $TOKEN" "https://$HOST/api/v0.2/tags/?limit=100"
  ```

The token is also what makes jobs with `visibility: personal` readable. CI
jobs are public, so this only matters when the window includes hand-submitted
work.

**GitHub access.** The build half of the report needs the `gh` CLI
authenticated against the layer's repository. Without it, produce the report
LAVA-only and say so in the method section — do not silently drop the
section, because "no build failures listed" and "builds were not examined"
look identical to a reader.

## Instructions

### 1. Scope the run

Agree four things before fetching anything:

- **Window.** Default to the last 7 days; 14 is the practical maximum before
  the sweep gets slow. State it in UTC in the report.
- **LAVA project.** The `metadata.path` carried in the job's metadata:
  `projects/meta-qcom/`, `projects/meta-qcom-3rdparty/`, and so on. Filter on
  this exact path, never on a job-name prefix: `meta-qcom` is itself a prefix
  of `meta-qcom-3rdparty`, so a prefix match contaminates a meta-qcom-only
  report with 3rdparty jobs.
- **GitHub repository**, e.g. `qualcomm-linux/meta-qcom`.
- **Output path** for the HTML file. Default
  `./ci-report-<start>_<end>.html` in the working directory.

### 2. Collect the LAVA jobs

There is no server-side date filter — see
[references/lava-rest-recipes.md](references/lava-rest-recipes.md) for which
filters the API accepts and which it rejects. Page backwards from the newest
job and cut on `submit_time` client-side:

```sh
curl -sSf --retry 3 "https://$HOST/api/v0.2/jobs/?limit=100&offset=$OFF&ordering=-id"
```

`-f` with `--retry` makes a bad page fail loudly instead of feeding an error
body into the sweep; count the pages fetched against the pages requested
before analysing, and re-fetch any that failed. Keep only jobs whose
top-level `metadata.path` equals the project path exactly. A page is
~700 KB and takes ~3 s, so run ~12 offsets in parallel; a week of meta-qcom
history is 12–15k jobs and 250 pages. Strip the `definition` field as you go
but keep, per job: `id`, `description`, `requested_device_type`,
`actual_device`, `state`, `health`, `submit_time`, `start_time`, `end_time`,
and the `metadata` field (which carries `path`, `build-url`, `pr-number`,
`gh-workflow-run-id`, `gh-workflow-run-attempt`).

### 3. Collect per-case results

For every Finished job:

```sh
curl -sSf --retry 3 "https://$HOST/api/v0.2/jobs/$JOB/tests/?limit=2000"
```

~30 KB and ~0.4 s each, so 16 in parallel finishes 12k jobs in a few minutes.
Track the jobs whose fetch still failed after the retries and re-fetch them —
a missing `/tests/` result silently removes that job from every rate.
This is the backbone of the report: it carries both the test cases and the
`lava` suite, whose `job` case holds `error_msg` and `error_type` — the only
place the cause of a dead job is recorded.

### 4. Fetch definitions and logs, selectively

Definitions (`/api/v0.2/jobs/<id>/`) only for jobs that failed, when you need
the deploy URL to recover which distro and kernel a job actually tested.

Console logs are 0.5–5 MB each. **Never fetch them for every job.** Fetch
three targeted sets:

- a random sample (~200) of Complete jobs that carry a failing case, for the
  signal-integrity and clock-step measurements;
- **all** boot/login timeouts, because the sub-classification only comes from
  reading them and there are usually only a couple of hundred;
- a targeted set for whatever single hypothesis you are testing, for example
  all jobs on one device type to attribute a panic to one kernel branch.

Logs may be xz-compressed; `qcom-lava-log` documents the detection and the
`xz -dc` fallback, and its `scripts/lava.sh` has a hardened fetch loop for the
flaky archive endpoint. Reuse it rather than re-deriving it.

### 5. Inventory the boards

```sh
curl -s "https://$HOST/api/v0.2/devices/?limit=300"
curl -s "https://$HOST/api/v0.2/workers/"
curl -s -H "Authorization: Token $TOKEN" "https://$HOST/api/v0.2/tags/?limit=100"
```

Join them: device → tag IDs → tag names, plus health, state and worker. This
is what turns "the display test skips a lot" into "these six boards carry the
`display` tag and have never once seen a connected display".

### 6. Collect the builds

```sh
gh run list -R "$REPO" --limit 800 --created ">=$START" \
  --json databaseId,workflowName,event,status,conclusion,createdAt,displayTitle,url
gh api --paginate "repos/$REPO/actions/runs/$RUN/jobs?per_page=100"
gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$JOB/logs"
```

`-R "$REPO"` keeps `gh run list` working without a checkout, and `--paginate`
matters on the jobs endpoint because a fan-out run can exceed one page. A
`gh run list` result that lands exactly on its `--limit` is truncated, not
complete — raise the limit or split the window into `--created "$A..$B"`
slices until every slice returns fewer runs than its limit, and state the
run count in the method section.
The log endpoint returns terminal escape sequences; without
`--allow-escape-sequences` the CLI refuses to print them. Strip them with
`sed 's/\x1b\[[0-9;]*m//g'` and grep for `^ERROR`, `^| ERROR`, `##[error]`,
`Nothing (RPROVIDES|PROVIDES)` and `cannot find`. Record, per failed job, the
failing step name and the first real error line.

### 7. Analyse

The rules that decide whether the report is right are in
[references/failure-taxonomy.md](references/failure-taxonomy.md). The ones
that change the headline numbers:

- **Four buckets, never mixed.** Green (Complete, no failing case),
  test-case failure (Complete, at least one failing case), dead (Incomplete),
  and canceled (Canceled — someone stopped it; count it, exclude it from
  every rate). A dead job reports its unfinished cases as `fail`; folding
  those into per-case rates inflates every number in the table, often by
  several times.
- **Cause comes from the `lava` suite**, its `job` case. The job record itself
  carries no error field.
- **Report the per-change clean rate, not only the per-job rate.** Group the
  jobs that carry a `gh-workflow-run-id`, keep only each run's highest
  `gh-workflow-run-attempt`, and count runs with zero failures. Jobs without
  a run id stay ungrouped — folding them together fabricates one giant
  always-red run — and counting superseded attempts marks every rerun as
  permanently failed. The gap between the two rates is usually the most
  important sentence in the report.
- **Break every rate down per board as well as per device type.** A failure
  confined to one board is a lab item; the same rate across a whole pool is a
  platform item. Nothing else separates them.
- **Treat skips as findings.** A case that skips 100% of the time on a board
  is missing hardware or a tag the lab is not honouring. A case that skips
  part of the time on a board where it also passes is a detection race.
- **Check signal integrity before believing a failure.** A case recorded
  `fail` with no clean `RESULT=FAIL` in the console log did not fail; the
  signal was corrupted in transit.
- **Distrust every duration measured across a wall-clock step.**

### 8. Write the report

Follow [references/report-template.md](references/report-template.md) for the
sections and the HTML skeleton. The output contract:

- one self-contained `.html` file, no external assets required to read it;
- readable in light and dark, driven by CSS custom properties;
- wide tables inside `overflow-x: auto` containers;
- every claim carries the measurement behind it — a bare "Bluetooth is flaky"
  is not a finding, "43 of 198 runs on hamoa-iot-evk-02 and -03" is.

Tell the user the path when it is written.

### 9. Suggest follow-ups, do not make them

The report ends in suggestions grouped by owner, because the four groups act
on different timescales and none of them can act on the others' items:

| Owner | Typical items |
|---|---|
| Test framework (qcom-linux-testkit) | Races, one-shot checks that should poll, watchdogs with no escalation, unbounded recovery paths that burn a job's budget |
| Kernel and image | Panics, driver hangs, storage enumeration, systemd units with no timeout, package conflicts |
| CI plumbing (workflows, lava-test-plans) | Test-shell budgets, job naming, pinned refs, how skips are reported, retry policy for infrastructure faults |
| Lab administrators | Board tags that do not match the hardware, individual bad boards, power control, artifact-cache reliability |

Each suggestion names the measurement that justifies it and the boards or
configs it applies to, so the owner can verify it independently.

**This skill does not change any repository.** It does not open pull requests
against the test suite or the layer, and it does not edit test scripts. If the
user asks for a fix after reading the report, that is a separate task in the
relevant repository.

## Output format

A single HTML file, plus a short spoken summary: the window, the volume
analysed, the three or four headline numbers, and the count of suggestions per
owner. Do not paste the whole report into the conversation.

## Error handling

- **A blank or unparseable log** is usually xz-compressed. See
  `qcom-lava-log`; a naive `curl | grep` marks every archived job as empty.
- **The log archive endpoint is flaky** (HTTP/2 stream errors, early close).
  Retry and verify completeness before accepting a log as read.
- **`gh api ... /logs` refuses to print** without `--allow-escape-sequences`.
- **The MCP `list_jobs` result can exceed the tool result cap** and be spilled
  to a file; grep that file rather than re-listing. For a sweep of this size,
  prefer raw REST with your own pagination.
- **Do not report a section you could not collect.** If `gh` was unavailable
  or a device type had no jobs in the window, say so in the method section.

## Notes

- Job names look like
  `<project>-<distro>-<run-id>-<attempt>-<boot test|pre-merge|post-merge>[-<suite>]`.
  In meta-qcom today the distro field is a constant, so the nodistro,
  qcom-distro and 6.18 test flows are indistinguishable by name — recover the
  real one from the deploy URL in the job definition. That is itself worth
  reporting as a CI-plumbing item.
- Queue time is rarely the problem. Measure it (`start_time - submit_time`)
  so the report can say so with a number rather than assuming it.
- Keep the raw sweep on disk. Re-running an analysis over a cached sweep costs
  seconds; re-fetching costs a quarter of an hour.
