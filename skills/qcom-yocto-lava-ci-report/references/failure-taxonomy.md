# Classifying CI failures

How to turn a sweep into findings. The worked examples are from a meta-qcom
sweep of 19–27 August 2026 (12,658 LAVA jobs, 800 GitHub Actions runs); they
illustrate each rule and are not expected results.

## Rule zero: four buckets, never mixed

Every finished job falls in exactly one:

| Bucket | Definition | What it means |
|---|---|---|
| Green | `health == Complete`, no case with `result == fail` | Nothing to report |
| Test-case failure | `health == Complete`, ≥1 failing case | The verdicts are trustworthy |
| Dead | `health == Incomplete` | The job never finished; its verdicts are not trustworthy |
| Canceled | `health == Canceled` | Stopped by a person or a superseding push; not a reliability signal |

A dead job reports the cases it never reached as `fail`. Folding those into
per-case rates inflates every number, often several-fold: in the August sweep
`weston-simple-egl` looked like a 19% failure on one device type across all
jobs, and 1.5% once the dead jobs were excluded. Compute per-case rates over
Complete jobs only, and report dead jobs separately by cause. Canceled jobs
get a count in the method section and nothing more: they carry no verdicts
worth reading, and folding them into the dead bucket would pollute its cause
taxonomy with entries no owner can act on.

Bucket sizes are themselves a finding. 92.7% green, 2.4% case failures, 4.9%
dead says the harness loses more jobs than the platforms fail tests.

## Where the cause of a dead job lives

Not in the job record — `/api/v0.2/jobs/<id>/` has no error field. It is in
the `lava` suite of `/tests/`, in the case named `job`:

```json
{"name": "job", "result": "fail",
 "metadata": "definition: lava\ncase: job\nresult: fail\nerror_msg: \"...\"\nerror_type: Job\n"}
```

`error_type` values observed in practice are `Job`, `Test` and
`Infrastructure`. It is a useful first cut but too coarse to act on — most
timeouts are typed `Job` whether the cause is a kernel hang or a lab fault.
Classify on `error_msg`.

Other `lava`-suite cases with `result: fail` — `minimal-boot`,
`auto-login-action`, `login-action`, `kernel-messages`, `bootloader-commands`
— narrow down which action died.

## Job-level cause taxonomy

Match `error_msg` in this order; earlier patterns are more specific.

| Class | Match | Owner |
|---|---|---|
| Kernel panic | `Kernel panic` (note the sub-type, e.g. `Asynchronous SError`) | Kernel |
| Test-shell budget exceeded | `lava-test-shell timed out after (\d+) seconds` | Test framework + CI plumbing |
| Boot/login timeout | `(auto-login-action\|login-action) timed out\|Login timed out\|wait for prompt timed out` | Split further, see below |
| Artifact download | `kisscache\|Unable to get\|Unable to download\|Resource unavailable\|http-download timed out` | Lab |
| Flash failure | `deploy-flasher timed out\|wait-qdl-device\|Unable to flash` | Lab |
| Download post-processing | `Post-processing of downloads failed\|download-postprocess-docker` | Lab |
| Power control | `Unable to reboot\|ykushcmd` | Lab |
| Bad artifact | `rootfs_file missing from tarball` | CI plumbing |

Capture the numeric timeout from the message. `lava-test-shell timed out
after 300 seconds` on a suite that needs longer is a budget problem in
`lava-test-plans`, not a test problem — group these by (suite, budget, device
type) and the pattern is immediate.

August 2026 distribution of 616 dead jobs: 203 test-shell budget, 200
boot/login, 82 download, 78 kernel panic, 21 flash, 14 post-processing, 10
power, 8 other.

## Sub-classifying boot and login timeouts

The single largest class, and the one where the label hides four unrelated
problems. Fetch the console log for **all** of them — there are rarely more
than a few hundred — and classify on the `lvl: target` lines:

| Evidence in the log | Class | Owner |
|---|---|---|
| `doesn't exist or does not contain a /dev` | Rootfs not found, dropped to initramfs | Kernel / image |
| `Kernel panic` | Panic during boot | Kernel |
| `Reached target .*Login Prompts` or `Serial Getty` present | Booted, prompt never matched | CI plumbing / console noise |
| `Linux version` present, none of the above | systemd stalled before the prompt | Image |
| No `Linux version` at all | Board never booted | Lab |
| Only bootloader output (`Sahara`, `firehose`, `qdl`) | Never got past flash | Lab |

For the "systemd stalled" class, extract the stuck unit — the last match of:

```
A start job is running for\s*(?:…|\\u2026)?([^(]{2,60})\(
```

The ellipsis systemd truncates with is the raw character `…` in decoded text
but the six-character escape sequence `\u2026` in log lines read straight
off the JSON transport, so the pattern accepts both.

Units appearing repeatedly are the finding. In August: `/dev/tpm0` on one
device type, `/dev/tee0` on another, NetworkManager and ModemManager across
several, plus two units whose progress line read `no limit` — a systemd unit
with no `TimeoutStartSec` can stall a boot indefinitely.

## Harness artefacts that look like failures

Two effects make the raw verdicts wrong. Measure both before believing any
per-case rate, and report the measurement — it tells the reader how much of
the red is real.

### Spliced LAVA signals

The DUT's serial console carries both the test shell's stdout and kernel
printk. `printf` returns when the line reaches the tty buffer, not when the
UART has sent it, so a kernel message can land inside a signal:

```
<<<LAVA_SIGNAL_TESTCASE TEST_CASE_ID=cdsp_remoteproc RESU[   69.214080] Loaded X.509 cert 'wens: 61c0386…'
LT=PASS>>>
```

LAVA cannot parse that, and records a pass as a failure. Two detectors, both
over the `lvl: target` lines:

- A `LAVA_SIGNAL_TESTCASE` line containing a kernel timestamp
  `\[\s*\d+\.\d{6}\]` — direct proof.
- A case recorded `fail` whose clean
  `<<<LAVA_SIGNAL_TESTCASE TEST_CASE_ID=<case> RESULT=FAIL>>>` does not appear
  anywhere in the log — the broader measure, since the corruption may have
  destroyed the line entirely.

August 2026: 36 of 200 sampled jobs carried a spliced signal, and 62 of 287
recorded case failures (21.6%) had no clean `RESULT=FAIL`. Short tests that
finish while the kernel is still logging are the most exposed.

### Wall-clock steps

Boards without a usable RTC boot at an image build-time fallback (or the
epoch) and get stepped to real time when NTP reaches them, often mid-job.
Detect by collecting the dates from the test framework's own log prefixes:

```
\[(?:INFO|PASS|FAIL|WARN|ERROR)\] (\d{4}-\d{2}-\d{2})
```

More than one distinct date in a job means the clock stepped. Every interval
measured across that step — FPS, throughput, elapsed time, capture duration —
is meaningless. August 2026: 87 of 200 sampled jobs (43.5%).

## Interpreting skips

A `SKIP` is invisible in a pass/fail summary, which is what makes it worth a
section of its own. Compute the skip rate per case per **board**, not just per
device type:

| Pattern | Reading | Owner |
|---|---|---|
| 100% on a board, 0% on its siblings | Missing hardware on that board | Lab |
| 100% across an entire device-type pool | The suite has never run there at all | Lab / CI plumbing |
| Partial rate on a board that also passes | A detection race in the test | Test framework |
| 100% on boards that carry the tag the plan requires | The tag is a promise the lab is not keeping | Lab |

The last row is the highest-value check in the report and the one that needs
the LAVA token, since it requires resolving tag IDs to names. In August three
whole device types carried the `display` tag and skipped every graphics test.

Also check tag *coverage*: if only one board in a pool carries a tag, every
job for that suite funnels onto it, making it both a bottleneck and a single
point of failure for that subsystem's coverage.

## Separating lab faults from platform faults

Break every rate down per board as well as per device type. Nothing else
distinguishes them:

- Concentrated on one or two boards → lab. Name the boards, give both rates,
  and give a healthy sibling as the control.
- Spread evenly across a pool → platform. Name the device type and the kernel
  branch.
- Present on one kernel branch and absent on the other → kernel. Confirm by
  reading the `Linux version` banner from a sample of both outcomes rather
  than trusting the job name, which does not encode the kernel.

## Builds

Group failed GitHub Actions jobs by failing step, then by the first real
error line. Expect a heavy tail: in August, 230 of 269 failed build jobs were
one recipe failing one way.

Useful splits:

- **By config.** A failure present only in `debug` configs points at
  `DEBUG_BUILD = "1"` and its `-O0`, which breaks code relying on
  `always_inline`. A failure only in a catch-all config points at a recipe
  that only that config pulls in.
- **By workflow.** Post-merge and nightly matrices usually include configs
  that pull-request builds do not, which is how a repository can have healthy
  PR builds and a post-merge branch that has not built for a week.
- **By machine.** A rootfs failure on exactly one machine across every config
  is usually a package file conflict, visible in the dnf transaction error.

## The number that frames the report

Per-job pass rate is not the user-visible one. Take the jobs that carry a
`gh-workflow-run-id`, keep each run's highest `gh-workflow-run-attempt`, and
compute the fraction of runs where *every* job passed. With ~100 jobs per
run, a 93% per-job rate produces a near-zero clean rate — in August, one
clean run in 89.

Lead the report with both numbers together. It is what turns "CI is a bit
flaky" into "the signal carries no information", and it is what justifies
spending effort on harness artefacts rather than only on real defects.
