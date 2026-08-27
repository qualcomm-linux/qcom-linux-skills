# The report

One self-contained HTML file. It is read by three audiences who each stop at a
different depth: a maintainer wanting the headline, a developer wanting the
evidence for one finding, and a lab administrator wanting their list. Order the
sections so each of them can stop early.

## Sections

### 1. Headline and funnel

Open with the volume analysed and the window, then the numbers that frame
everything else: per-job clean rate **and** per-change clean rate, side by
side. Add the build workflows' pass rates and the queue p90 — the last one
usually rules out capacity, which is worth stating with a number rather than
leaving as an assumption.

Follow with the funnel: build → boot → pre-merge suites → case verdicts →
check result, each stage carrying how many jobs it loses. This is the one place
a numbered sequence is honest, because the stages really are ordered and a
loss at one stage hides everything downstream.

### 2. Jobs that never reported

The dead-job taxonomy as a table: cause, count, share, where it concentrates.
Then a short block per major cause with the evidence — a trimmed console
excerpt, the affected boards or device types, and the rate. Mark each with a
severity and an owner.

Keep the excerpts short. Six lines of a panic trace with the interesting frames
kept and the register dump dropped reads; forty lines does not.

### 3. Test-case failures: real versus artefact

Lead with the artefact measurement, because it changes how the rest of the
section is read: how many recorded failures had no clean signal, and how many
jobs showed a wall-clock step. Show one spliced signal verbatim — it is
immediately convincing and hard to describe in prose.

Then the failures that survive that filter, as a table: case, device type,
failures, runs, rate, and which boards they concentrate on. Say for each
whether it looks like a test bug or a platform bug, and why.

### 4. Coverage lost to skips

The section a pass/fail dashboard cannot produce. Skip rates per case per
board, split into the deterministic (missing hardware, tag mismatches) and the
intermittent (detection races). Name the device types with no coverage at all.
If a tag is only on one board in a pool, say so — it is a bottleneck and a
single point of failure.

### 5. Builds

Failed build jobs grouped by cause, with the dominant one first and its error
excerpt. Say which configs, machines and workflows each affects, and whether
pull-request builds see it.

### 6. Follow-up, by owner

Four blocks — test framework, kernel and image, CI plumbing, lab
administrators. Each item is one line of what to do plus the measurement that
justifies it and the boards or configs it applies to. Order within a block by
how much red the item removes.

This section is the deliverable for the lab administrators, so it must stand
alone: someone forwarded only this block should still be able to act on it
without reading the rest.

### 7. Method

Window, endpoints swept, sample sizes, and what was excluded and why —
especially that per-case rates exclude dead jobs. Name anything not collected,
such as builds when `gh` was unavailable. A reader who disagrees with a number
should be able to re-derive it.

## HTML skeleton

Adapt rather than copy. The parts that matter are the three theme states, the
tables scrolling inside their own container, and severity encoded in form as
well as in words.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CI report — meta-qcom, 19–27 Aug 2026</title>
<style>
/* Light palette on bare :root, so the un-stamped default resolves. */
:root {
  --ground:#eaeef2; --surface:#fbfcfd; --ink:#151b22; --muted:#5d6b78;
  --rule:#d3dbe2; --accent:#0c6c78;
  --pass:#2c7a51; --warn:#8f6410; --crit:#a2352c;
}
/* Only redefine tokens; guard so an explicit light choice still wins. */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --ground:#0e1317; --surface:#151c22; --ink:#e4eaef; --muted:#94a3b0;
    --rule:#27333c; --accent:#43b6c1;
    --pass:#57b184; --warn:#d5a54e; --crit:#e2765f;
  }
}
/* Same overrides again, so an explicit dark choice wins on a light host. */
:root[data-theme="dark"] {
  --ground:#0e1317; --surface:#151c22; --ink:#e4eaef; --muted:#94a3b0;
  --rule:#27333c; --accent:#43b6c1;
  --pass:#57b184; --warn:#d5a54e; --crit:#e2765f;
}

body { margin:0; background:var(--ground); color:var(--ink);
       font-family:system-ui,-apple-system,"Segoe UI",sans-serif; line-height:1.6; }
.wrap { max-width:1140px; margin:0 auto; padding:0 28px; }
.prose { max-width:70ch; }

/* Stat strip: the headline numbers, semantic colour, no decoration. */
.stats { display:grid; grid-template-columns:repeat(auto-fit,minmax(196px,1fr));
         gap:1px; background:var(--rule); border:1px solid var(--rule); }
.stat { background:var(--surface); padding:20px; }
.stat .n { font-size:2.1rem; font-weight:700; font-variant-numeric:tabular-nums; }
.stat .n.bad { color:var(--crit); } .stat .n.ok { color:var(--pass); }
.stat .k { font-size:11px; letter-spacing:.09em; text-transform:uppercase; color:var(--muted); }

/* Wide tables scroll in their own container; the page never scrolls sideways. */
.tw { overflow-x:auto; border:1px solid var(--rule); background:var(--surface); }
table { width:100%; border-collapse:collapse; font-size:13.5px; }
th, td { padding:9px 16px; border-bottom:1px solid var(--rule); text-align:left; vertical-align:top; }
td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }

/* Findings: severity as a left stripe plus a pill, not colour alone. */
.finding { background:var(--surface); border:1px solid var(--rule);
           border-left:4px solid var(--muted); padding:20px 22px; }
.finding.crit { border-left-color:var(--crit); }
.finding.high { border-left-color:var(--warn); }
.pill { font-size:10.5px; font-weight:600; letter-spacing:.09em; text-transform:uppercase;
        padding:3px 8px; border:1px solid var(--rule); }

pre { background:#0a0e11; color:#c6d4da; padding:14px 16px; overflow-x:auto;
      font-size:12.3px; line-height:1.6; }
@media (prefers-reduced-motion:reduce) { * { animation:none !important; transition:none !important; } }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>CI report — meta-qcom</h1>
    <p class="prose">19–27 August 2026 · 12,658 LAVA jobs · 800 GitHub Actions runs</p>
  </header>

  <section>
    <div class="stats">
      <div class="stat"><span class="n ok">92.7%</span><span class="k">per-job clean</span></div>
      <div class="stat"><span class="n bad">1 / 89</span><span class="k">clean PR test runs</span></div>
    </div>
  </section>

  <section>
    <div class="tw"><table>
      <thead><tr><th>Cause</th><th class="num">Jobs</th><th>Concentrated in</th></tr></thead>
      <tbody><tr><td>Test-shell budget exceeded</td><td class="num">203</td><td>bt, display-gfx</td></tr></tbody>
    </table></div>
  </section>
</div>
</body>
</html>
```

## Writing rules

- **Every claim carries its measurement.** "Bluetooth is flaky" is not a
  finding. "43 of 198 runs on two named boards, and nowhere else" is.
- **Say where a failure is not.** A rate with no control is unreadable; the
  healthy sibling board is what makes the finding actionable.
- **Distinguish "no failures found" from "not examined."** They look identical
  to a reader and mean opposite things.
- **Percentages always alongside their counts.** 25% of four is noise.
- **Name boards, device types, configs and kernel branches exactly**, so an
  owner can look them up without asking.
- **No recommendation without a number.** If a suggestion has no measurement
  behind it, it belongs in a conversation, not in the report.
