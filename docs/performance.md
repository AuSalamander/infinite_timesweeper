# Automated performance benchmarks

The benchmark runs the real Flame game and board renderer in **profile mode** on
Linux. It uses Flutter engine frame timings, not unit-test wall-clock timing, so
it includes UI/build and raster work under representative rendering load. Every
workload is measured in both **light and dark mode**; the theme is part of the
measurement contract.

```sh
./scripts/benchmark.sh
```

The script finds `fvm flutter` (or `flutter`), checks the Linux build/display
requirements, serializes benchmark runs with a machine-local lock, runs
unattended, and writes timestamped reports plus `build/performance/latest.json`.
Any previous `latest.json` is removed at run start, and `latest-status.json`
records running/passed/regressed/failed status, so a failed candidate cannot be
mistaken for a stale successful score. Keep the game window visible and avoid
other load during a run. The actual logical surface and device pixel ratio are
recorded in every report; DPR must be 1 and baseline comparisons reject a changed
surface. A display is required; the script fails clearly instead of silently
substituting a headless or simulated surface.

The benchmark is intentionally **manual**: there is no CI job. It needs a visible
Linux desktop and a reasonably stable GPU/driver. The normal test workflow runs
the Flutter unit tests and the Python performance-summary tests only; it does not
run the benchmark. Run the benchmark locally on a quiet machine for performance
decisions.

## Scenes and metrics

The versioned scene list is part of the measurement contract. There are five
workloads, each measured once per theme (10 scenes total):

- `zoomed_out_static_light` / `zoomed_out_static_dark`: zoom 0.1, tens of
  thousands of visible mixed-state tiles, including open-tile glow effects.
- `zoomed_out_pan_light` / `zoomed_out_pan_dark`: the same load while the camera
  moves a fixed distance per frame through the populated world.
- `text_cold_light` / `text_cold_dark`: zoom 0.5 (text visible), clearing
  generated chunks before every frame so each measured frame pays generation
  cost.
- `text_warm_light` / `text_warm_dark`: the same view retaining generated chunks
  across frames.
- `zoomed_out_timeouts_light` / `zoomed_out_timeouts_dark`: zoom 0.1, about
  174k stored tiles and pending exploded chunks. This intentionally includes lock
  rendering and the real 1 Hz scan of stored tiles; its tail latency is expected
  to contribute heavily to the score.

Each scene sets its brightness explicitly rather than inheriting the desktop
theme. Dark mode draws an additional per-tile border, so a theme change is a
workload change, not a free comparison.

Each scene discards at least 30 warm-up frames, measures at least 200 frames, and
flushes delayed timing reports. The cold scene clears chunk data after warm-up
and before every frame; it does not claim to exercise LRU eviction. Cold and warm
p95 values can be close because raster work dominates; use the scene-local cache
counters (and the cold/warm pair) to diagnose generation changes rather than
expecting a fixed gap. Reports include sample counts, visible and stored tile
counts, scene-local cache counters, camera distance, initial frame latency,
estimated FPS from build-start intervals, ratio of frames over a fixed 16.7 ms
budget, per-scene `brightness`, and p50/p95/p99 UI/build, raster, and total span
times in milliseconds. Build and raster work can overlap; `totalSpan` is
therefore used instead of adding them.

The lower-is-better `score` is the geometric mean of every scene's p95
`totalSpan` across all 10 scenes. Only compare reports with the same schema,
exact scene list, Flutter/Dart/engine version, surface, theme matrix,
warm-up/sample requirements, and per-scene zoom, brightness, and
visible/stored/open/flagged/exploded workload counts; the tooling enforces this.
Do not drop a slow scene to improve the score. Raw per-scene metrics remain
available for diagnosis.

## Visual reference screenshots

Every scene also captures a deterministic PNG after measurement. Screenshots are
fixed 800x600 crops centred on the camera, written under
`build/performance/screenshots/<stamp>/<scene>.png`, and compared with the
committed references in `test/reference/performance/`. The crop keeps the
captured world region comparable if the window manager changes the overall
window width or height.

The comparison decodes both images to RGBA and allows a channel delta of 8/255.
A scene is reported as a mismatch when more than 0.2% of pixels exceed that
channel tolerance, or when the image dimensions differ. References are tied to
the Linux environment (Flutter version, fonts, and GPU stack); they are not
portable across machines. Regenerate them on the same machine after intentional
visual changes:

```sh
PERF_UPDATE_REFERENCES=1 PERF_RUNS=1 ./scripts/benchmark.sh
```

That run writes `test/reference/performance/<scene>.png` plus
`test/reference/performance/manifest.json` (scene list, surface, SDK, screenshot
size, and git revision). Normal runs print one `VISUAL <scene> status=... diff=...`
line per scene and remain report-only by default. Set
`PERF_FAIL_ON_VISUAL_REGRESSION=1` to return exit status 2 for a mismatch, a
missing reference, or a capture error. The reference update and the visual gate
cannot be enabled in the same run.

Keep the benchmark window at a fixed size for the whole run. The harness records
the surface per scene and reports `stable=false` if the window manager resizes
the window; unstable runs still write diagnostics but their score must not be
compared with a baseline. The script prints a `SURFACE unstable` warning and
baseline comparisons reject the report.

Reference generation deliberately freezes the clock for the timeout scene and
fixes the camera position for the pan scene, so countdown text and viewport
coverage do not drift between runs. The screenshots are a regression aid, not a
replacement for reviewing intentional visual changes.

## Hill-climbing and baselines

Use three runs for decisions on a quiet machine; the summary takes the median
of each metric and of the overall score:

```sh
PERF_RUNS=3 ./scripts/benchmark.sh
cp build/performance/latest.json build/performance/baseline.json

# Make an optimization, then compare using the same machine and SDK.
PERF_RUNS=3 PERF_BASELINE=build/performance/baseline.json ./scripts/benchmark.sh
```

Comparisons are report-only by default. A regression exceeds both a 10% relative
tolerance and a 0.5 ms absolute floor. Set `PERF_FAIL_ON_REGRESSION=1` to return
exit status 2 when the score or any scene p95 regresses beyond that tolerance.
Regression gating requires `PERF_BASELINE` and at least three runs to avoid
judging single-run noise. There are deliberately no hardware-specific absolute
FPS gates.

Schema 2 adds the light/dark matrix and visual results. Baselines from schema 1
are rejected; regenerate the baseline after changing scenes, themes, or the
report schema. Multi-run reports include per-quantile run min/max values and each
run's score, plus the 1/5/15-minute load average at run start, so agents can
detect noisy or contended measurements rather than trusting a median blindly.

The final `PERF_RESULT` line is intended for automation and contains the report
path, run count, surface, aggregate score, surface stability, and overall visual
status. Individual `SCENARIO`, `VISUAL`, and `COMPARE` lines expose the
supporting measurements. Reports also contain the resolved Flutter/Dart/engine
versions and a dirty-aware git revision.
