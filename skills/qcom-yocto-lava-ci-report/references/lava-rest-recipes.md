# Sweeping the LAVA REST API over a window

Everything here is against LAVA REST API v0.2 on `lava.infra.foundries.io`,
verified August 2026. `qcom-lava-log` covers the single-job case — log
format, `lvl: target`, xz handling. This document covers what that skill does
not: listing, filtering and sweeping many jobs.

## Endpoints and authentication

| Endpoint | Returns | Anonymous |
|---|---|---|
| `/api/v0.2/jobs/` | Paginated job list, each with its full definition | yes |
| `/api/v0.2/jobs/<id>/` | One job: state, health, times, device, definition, metadata | yes |
| `/api/v0.2/jobs/<id>/tests/` | Every test case, including the `lava` suite | yes |
| `/api/v0.2/jobs/<id>/logs/` | Console log, plain or xz | yes |
| `/api/v0.2/jobs/<id>/suites/` | Suite index | yes |
| `/api/v0.2/devices/` | Device list with health, state, worker, tag **IDs** | yes |
| `/api/v0.2/devices/<hostname>/` | One device | yes |
| `/api/v0.2/workers/` | Dispatcher workers, health, last ping, load, disk | yes |
| `/api/v0.2/tags/` | Tag ID → name mapping | **no — 401** |

`/api/v0.2/` lists the roots. There is no global test-case endpoint: per-case
results are only reachable per job, which is why step 3 of the skill fetches
`/tests/` for every job rather than querying results directly.

The 401 on `/tags/` matters more than it looks. `/devices/` gives tags as
integers, so without a token a sweep can see that `rb3g2-01` carries tags
`[6, 8, 20, 25]` but not that tag 8 is `display`. Send the token as:

```sh
curl -s -H "Authorization: Token $TOKEN" "https://$HOST/api/v0.2/tags/?limit=100"
```

## Which query parameters work

Verified by probing; the API is inconsistent about rejecting what it does not
support, so an unsupported filter can look like it worked.

| Parameter | Behaviour |
|---|---|
| `limit`, `offset` | Work. `limit=100` is a good page size for jobs. |
| `ordering=-id` | Works. Newest first; the basis for the sweep. |
| `health=Incomplete` | Works. Also `Complete`, `Canceled`. |
| `state=Finished` | Works. Also `Running`, `Scheduled`, `Submitted`. |
| `description__contains=meta-qcom` | Works. |
| `submitter=q-github-bot` | **Rejected**, HTTP 400 — it wants a numeric user ID. |
| `submit_time__gte=<iso>` | **Silently ignored** — the response `count` is the unfiltered total. |
| `id__gte=<n>` | **Silently ignored**, same trap. |

The two silent ones are the dangerous pair. Always sanity-check `count`
against an unfiltered request before trusting a filter.

So there is **no server-side date filter**. Sweep with `ordering=-id` and cut
client-side on `submit_time`.

## Sweeping a window

```
page 0 .. N with limit=100, ordering=-id
  for each job:
    if submit_time < cutoff: mark done, skip
    else: keep
  stop once a page contained a job older than the cutoff
```

Cost, measured on a week of meta-qcom history:

| Request | Size | Latency |
|---|---|---|
| jobs page, `limit=100` | ~700 KB | ~3 s |
| `/tests/?limit=2000` | ~30 KB | ~0.4 s |
| `/jobs/<id>/` | ~50 KB | ~0.5 s |
| `/logs/` | 0.5–5 MB | 1–10 s |

Run ~12 offsets in parallel for the jobs sweep and ~16 for `/tests/`. A week
is 12–15k jobs, roughly 250 pages: a few minutes for the sweep, a few more
for the per-case results. Serial fetching takes over an hour, so parallelise
or the run becomes impractical.

The per-page `definition` field is most of the 700 KB. Strip it during the
sweep, keeping only the metadata block and the job name, and re-fetch full
definitions later for the few hundred jobs that failed.

## Job names

CI jobs are submitted by `q-github-bot` and named:

```
<project>-<distro>-<gh-run-id>-<attempt>-<phase>[-<suite>]
```

for example:

```
meta-qcom-qcom-distro-33028349494-2-pre-merge-gstr-video
meta-qcom-qcom-distro-33021271604-1-boot test
meta-qcom-3rdparty-qcom-distro-32944110293-1-boot test
```

Notes that cost time if you rediscover them:

- The boot phase is literally `boot test`, with a space. A regex anchored on
  `-boot-` matches nothing.
- `<suite>` is one of `basic`, `display-gfx`, `gstr-video`, `bt`, `audio`,
  `camera` for the pre-merge phase, absent for boot.
- `<project>` names the layer, but `meta-qcom` is a prefix of
  `meta-qcom-3rdparty`: select jobs by an exact match on `metadata.path`,
  never by a name prefix.
- **`<distro>` is not trustworthy.** meta-qcom's `lava-test-plans` action
  writes `OS_INFO=qcom-distro` unconditionally, so nodistro, qcom-distro and
  the 6.18-kernel flow all render as `qcom-distro` in the job name. Three
  distinct test matrices are indistinguishable by name.

To recover what a job actually tested, read the deploy URL out of the job
definition:

```
.../<gh-run-id>-<attempt>//<distro>/<machine>/<image>-<machine>.rootfs.qcomflash.tar.gz
```

The `<distro>` path component there is the real one, including a kernel
suffix such as `qcom-distro_linux-qcom-6.18`. Alternatively read the kernel
version out of the console log's `Linux version` banner, which is what to do
when attributing a failure to a kernel branch.

## Job metadata

The job definition's `metadata` block links back to GitHub, and the REST job
record surfaces it as a top-level `metadata` field — reading it needs no
definition parsing:

```yaml
metadata:
  path: projects/meta-qcom/
  build-url: https://.../meta-qcom/33021271604-1/
  pr-url: https://github.com/qualcomm-linux/meta-qcom/pull/3004
  pr-number: 3004
  gh-workflow-url: https://github.com/qualcomm-linux/meta-qcom/actions/runs/33028349494
  gh-workflow-run-id: 33028349494
  gh-workflow-run-attempt: 2
```

`gh-workflow-run-id` is the join key for the per-change clean rate: group the
jobs that carry a run id, keep only the highest `gh-workflow-run-attempt` per
id — a GitHub rerun keeps the run id and increments the attempt, so the
superseded attempt no longer speaks for the change — and a run is clean only
if every job in that final attempt is. `pr-number` gives the per-pull-request
view. Push and nightly runs leave these fields empty: use the emptiness to
separate pre-merge from post-merge, but never fold the id-less jobs into one
group.

## Device tags

Tags are how a test plan targets boards with particular hardware — a
display-suite job carries `tags: [display]` in its definition and LAVA only
schedules it onto boards holding that tag. The report's tag audit compares
what a tag promises against what the tests observed:

```sh
# tag id -> name (needs the token)
curl -s -H "Authorization: Token $TOKEN" "https://$HOST/api/v0.2/tags/?limit=100"
# device -> tag ids, health, worker
curl -s "https://$HOST/api/v0.2/devices/?limit=300"
```

Tags seen in this lab include `display`, `has-bt`, `has-camera`, `camera`,
`cambridge-lab`, `hyderabad-lab`, `pvt`, `mesa-ci`, `allow-remote-access`,
plus per-person lab tags. The lab tags are worth carrying into the report:
comparing failure rates between sites is often more informative than
comparing them between boards.
