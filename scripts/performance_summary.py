#!/usr/bin/env python3
"""Aggregate benchmark runs, compare scores, and gate visual references."""

import argparse
import copy
import json
import math
import os
import statistics
import sys
from pathlib import Path


SCENARIOS = (
    "zoomed_out_static_light",
    "zoomed_out_pan_light",
    "text_cold_light",
    "text_warm_light",
    "zoomed_out_static_dark",
    "zoomed_out_pan_dark",
    "text_cold_dark",
    "text_warm_dark",
    "zoomed_out_timeouts_light",
    "zoomed_out_timeouts_dark",
)
VISUAL_STATUSES = {"match", "mismatch", "missing", "error", "updated"}


def load(path):
    with open(path, encoding="utf-8") as handle:
        report = json.load(handle)
    if report.get("schemaVersion") != 2:
        raise ValueError(f"{path}: unsupported schemaVersion")
    score = report.get("score")
    if (not report.get("scenarios") or not isinstance(score, (int, float))
            or isinstance(score, bool) or not math.isfinite(score) or score <= 0):
        raise ValueError(f"{path}: incomplete or invalid benchmark report")
    names = tuple(scene.get("name") for scene in report["scenarios"])
    if names != SCENARIOS:
        raise ValueError(f"{path}: expected exact scenario list {SCENARIOS}")
    for scene in report["scenarios"]:
        if scene.get("brightness") not in ("light", "dark"):
            raise ValueError(
                f"{path}: missing brightness for {scene.get('name')}")
        visual = scene.get("visual")
        if not isinstance(visual, dict) or visual.get("status") not in VISUAL_STATUSES:
            raise ValueError(
                f"{path}: missing or invalid visual result for {scene.get('name')}")
        diff = visual.get("diffRatio")
        if (isinstance(diff, bool) or not isinstance(diff, (int, float))
                or not math.isfinite(diff)):
            raise ValueError(
                f"{path}: invalid visual diff for {scene.get('name')}")
    if not isinstance(report["metadata"].get("surfaceStable"), bool):
        raise ValueError(f"{path}: missing surfaceStable flag")
    return report


def visual_status(scenes):
    statuses = [scene["visual"]["status"] for scene in scenes]
    if "mismatch" in statuses:
        return "mismatch"
    if "error" in statuses:
        return "error"
    if "missing" in statuses:
        return "missing"
    if statuses and all(status == "updated" for status in statuses):
        return "updated"
    return "match"


def aggregate_visual(samples):
    status = visual_status(samples)
    return {
        "status": status,
        "diffRatio": max(float(item["visual"].get("diffRatio", 0)) for item in samples),
        "differentPixels": max(
            int(item["visual"].get("differentPixels") or 0) for item in samples),
        "maxChannelDelta": max(
            int(item["visual"].get("maxChannelDelta") or 0) for item in samples),
    }


def aggregate(reports):
    result = copy.deepcopy(reports[0])
    result["runCount"] = len(reports)
    result["runScores"] = [report["score"] for report in reports]
    result["score"] = statistics.median(result["runScores"])
    result["metadata"]["scoreFormula"] = (
        "median of per-run geometric means of scenario p95 totalSpan milliseconds"
    )
    result["metadata"]["scenarioMetricAggregation"] = "median of per-run values"
    for index, scenario in enumerate(result["scenarios"]):
        samples = [report["scenarios"][index] for report in reports]
        scenario["sampleCount"] = sum(item["sampleCount"] for item in samples)
        for key in ("estimatedFps", "over16_7msRatio", "cacheHits", "cacheMisses",
                    "cameraDistance", "initialFrameTotalSpanMs"):
            scenario[key] = statistics.median(item[key] for item in samples)
        for metric in ("uiBuildMs", "rasterMs", "totalSpanMs"):
            for quantile in ("p50", "p95", "p99"):
                values = [item[metric][quantile] for item in samples]
                scenario[metric][quantile] = statistics.median(values)
                scenario[metric][quantile + "RunMin"] = min(values)
                scenario[metric][quantile + "RunMax"] = max(values)
        scenario["visual"] = aggregate_visual(samples)
    return result


def compatible(current, baseline):
    if current["schemaVersion"] != baseline["schemaVersion"]:
        raise ValueError("baseline schema differs")
    if not current["metadata"]["surfaceStable"]:
        raise ValueError("current report surface changed during the run")
    if not baseline["metadata"]["surfaceStable"]:
        raise ValueError("baseline surface changed during its run")
    if current["metadata"]["flutterVersion"] != baseline["metadata"]["flutterVersion"]:
        raise ValueError("baseline was produced by a different Flutter/Dart version")
    if current["metadata"]["surface"] != baseline["metadata"]["surface"]:
        raise ValueError("baseline surface differs")
    names = lambda report: [scene["name"] for scene in report["scenarios"]]
    if names(current) != names(baseline):
        raise ValueError("baseline scenario list differs")
    for key in ("warmupFrames", "minimumMeasuredFrames"):
        if current["metadata"].get(key) != baseline["metadata"].get(key):
            raise ValueError(f"baseline {key} differs")
    for current_scene, baseline_scene in zip(current["scenarios"], baseline["scenarios"]):
        for key in ("zoom", "brightness", "visibleTiles", "storedTiles",
                    "openTiles", "flaggedTiles", "explodedTiles",
                    "cameraStepPerFrame"):
            if current_scene.get(key) != baseline_scene.get(key):
                raise ValueError(f"baseline {current_scene['name']} {key} differs")


def regressed(current, baseline, tolerance, floor):
    return current - baseline > max(floor, baseline * tolerance)


def compare(current, baseline, tolerance, floor):
    compatible(current, baseline)
    rows = []
    current_scenes = {scene["name"]: scene for scene in current["scenarios"]}
    baseline_scenes = {scene["name"]: scene for scene in baseline["scenarios"]}
    for name, scene in current_scenes.items():
        old = baseline_scenes[name]["totalSpanMs"]["p95"]
        new = scene["totalSpanMs"]["p95"]
        if old <= 0:
            raise ValueError(f"baseline {name} p95 must be positive")
        rows.append((f"scene:{name}", old, new, regressed(new, old, tolerance, floor)))
    old = baseline["score"]
    new = current["score"]
    rows.append(("score", old, new, regressed(new, old, tolerance, floor)))
    return rows


def atomic_write(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")
    os.replace(temporary, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--tolerance", type=float, default=0.10)
    parser.add_argument("--floor-ms", type=float, default=0.5)
    parser.add_argument("--fail-on-regression", action="store_true")
    parser.add_argument("--fail-on-visual-regression", action="store_true")
    args = parser.parse_args()

    reports = [load(path) for path in args.reports]
    for report in reports[1:]:
        compatible(reports[0], report)
    current = aggregate(reports)
    atomic_write(args.output, current)

    surface = current["metadata"]["surface"]
    for scene in current["scenarios"]:
        total = scene["totalSpanMs"]
        print(
            "SCENARIO {name} samples={sampleCount} "
            "ui_p95={uiBuildMs[p95]:.3f}ms raster_p95={rasterMs[p95]:.3f}ms "
            "total_p50={totalSpanMs[p50]:.3f}ms total_p95={totalSpanMs[p95]:.3f}ms "
            "total_p99={totalSpanMs[p99]:.3f}ms fps={estimatedFps:.1f} "
            "over16.7ms={over16_7msRatio:.1%}".format(**scene)
        )
    for scene in current["scenarios"]:
        visual = scene["visual"]
        print(
            f"VISUAL {scene['name']} status={visual['status']} "
            f"diff={visual['diffRatio']:.3%} "
            f"pixels={visual.get('differentPixels', 0)} "
            f"max_channel_delta={visual.get('maxChannelDelta', 0)}"
        )
    overall_visual = visual_status(current["scenarios"])
    print(
        f"PERF_RESULT path={args.output.absolute()} runs={current['runCount']} "
        f"surface={surface['width']:g}x{surface['height']:g}@"
        f"{surface['devicePixelRatio']:g} score_ms={current['score']:.3f} "
        f"stable={str(current['metadata']['surfaceStable']).lower()} "
        f"visual={overall_visual}"
    )
    if not current["metadata"]["surfaceStable"]:
        changes = current["metadata"].get("surfaceChanges", [])
        print(
            "SURFACE unstable: " + ("; ".join(changes) if changes else "surface changed"),
            file=sys.stderr,
        )

    failed = False
    if args.baseline:
        rows = compare(current, load(args.baseline), args.tolerance, args.floor_ms)
        for name, old, new, is_regression in rows:
            change = (new / old - 1) * 100
            status = "REGRESSION" if is_regression else "ok"
            print(f"COMPARE {name} baseline_ms={old:.3f} current_ms={new:.3f} "
                  f"change={change:+.1f}% {status}")
            failed |= is_regression and args.fail_on_regression
    if args.fail_on_visual_regression:
        for scene in current["scenarios"]:
            if scene["visual"]["status"] in ("mismatch", "missing", "error"):
                print(
                    f"VISUAL_REGRESSION {scene['name']} "
                    f"status={scene['visual']['status']}",
                    file=sys.stderr,
                )
                failed = True
    return 2 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, ZeroDivisionError, KeyError,
            json.JSONDecodeError) as error:
        print(f"performance summary: {error}", file=sys.stderr)
        sys.exit(1)
