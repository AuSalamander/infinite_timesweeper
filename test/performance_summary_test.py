import copy
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location(
    "performance_summary",
    Path(__file__).parents[1] / "scripts" / "performance_summary.py",
)
SUMMARY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUMMARY)


def visual(status="match", diff=0.0, pixels=0, max_delta=0):
    return {
        "status": status,
        "diffRatio": diff,
        "differentPixels": pixels,
        "maxChannelDelta": max_delta,
    }


def report():
    scene = {
        "brightness": "light",
        "zoom": 0.1,
        "visibleTiles": 50000,
        "storedTiles": 100000,
        "openTiles": 6000,
        "flaggedTiles": 3000,
        "explodedTiles": 0,
        "sampleCount": 200,
        "estimatedFps": 10,
        "over16_7msRatio": 1,
        "cacheHits": 0,
        "cacheMisses": 0,
        "cameraDistance": 0,
        "cameraStepPerFrame": 0,
        "initialFrameTotalSpanMs": 10,
        "uiBuildMs": {"p50": 2, "p95": 3, "p99": 4},
        "rasterMs": {"p50": 3, "p95": 4, "p99": 5},
        "totalSpanMs": {"p50": 8, "p95": 10, "p99": 12},
        "visual": visual(),
    }
    return {
        "schemaVersion": 2,
        "score": 10.0,
        "metadata": {
            "flutterVersion": "test-sdk",
            "surface": {"width": 900, "height": 600, "devicePixelRatio": 1},
            "surfaceStable": True,
            "surfaceChanges": [],
            "warmupFrames": 30,
            "minimumMeasuredFrames": 200,
        },
        "scenarios": [
            dict(
                scene,
                name=name,
                brightness="light" if name.endswith("_light") else "dark",
            )
            for name in SUMMARY.SCENARIOS
        ],
    }


class PerformanceSummaryTest(unittest.TestCase):
    def test_aggregate_uses_medians_and_sums_actual_frame_count(self):
        reports = [report() for _ in range(3)]
        reports[0]["score"] = 8
        reports[2]["score"] = 14
        reports[2]["scenarios"][0]["totalSpanMs"]["p95"] = 14
        result = SUMMARY.aggregate(reports)
        self.assertEqual(result["runCount"], 3)
        self.assertEqual(result["score"], 10)
        self.assertEqual(result["scenarios"][0]["totalSpanMs"]["p95"], 10)
        self.assertEqual(result["scenarios"][0]["sampleCount"], 600)

    def test_aggregate_combines_visual_results(self):
        reports = [report() for _ in range(3)]
        reports[1]["scenarios"][0]["visual"] = visual("mismatch", 0.02, 50, 40)
        reports[2]["scenarios"][1]["visual"] = visual("missing", 1.0)
        result = SUMMARY.aggregate(reports)
        first = result["scenarios"][0]["visual"]
        self.assertEqual(first["status"], "mismatch")
        self.assertEqual(first["diffRatio"], 0.02)
        self.assertEqual(first["differentPixels"], 50)
        self.assertEqual(first["maxChannelDelta"], 40)
        self.assertEqual(result["scenarios"][1]["visual"]["status"], "missing")

    def test_visual_status_precedence(self):
        self.assertEqual(SUMMARY.visual_status([{"visual": visual()}] * 2), "match")
        self.assertEqual(
            SUMMARY.visual_status(
                [{"visual": visual("updated")}, {"visual": visual("updated")}]
            ),
            "updated",
        )
        self.assertEqual(
            SUMMARY.visual_status(
                [{"visual": visual("match")}, {"visual": visual("missing")}]
            ),
            "missing",
        )
        self.assertEqual(
            SUMMARY.visual_status(
                [{"visual": visual("missing")}, {"visual": visual("mismatch")}]
            ),
            "mismatch",
        )

    def test_comparison_rejects_changed_workload(self):
        current = report()
        for section, key in (("metadata", "warmupFrames"),
                             ("metadata", "minimumMeasuredFrames")):
            changed = copy.deepcopy(current)
            changed[section][key] += 1
            with self.assertRaises(ValueError):
                SUMMARY.compatible(changed, current)
        for key in ("zoom", "visibleTiles", "storedTiles", "openTiles",
                    "flaggedTiles", "explodedTiles", "cameraStepPerFrame"):
            changed = copy.deepcopy(current)
            changed["scenarios"][0][key] += 1
            with self.assertRaises(ValueError):
                SUMMARY.compatible(changed, current)
        changed = copy.deepcopy(current)
        changed["scenarios"][0]["brightness"] = "dark"
        with self.assertRaises(ValueError):
            SUMMARY.compatible(changed, current)
        unstable = copy.deepcopy(current)
        unstable["metadata"]["surfaceStable"] = False
        with self.assertRaisesRegex(ValueError, "surface changed"):
            SUMMARY.compatible(unstable, current)

    def test_regression_requires_relative_and_absolute_change(self):
        baseline = report()
        current = copy.deepcopy(baseline)
        current["scenarios"][0]["totalSpanMs"]["p95"] = 10.5
        rows = SUMMARY.compare(current, baseline, 0.10, 0.5)
        self.assertFalse(rows[0][3])
        current["scenarios"][0]["totalSpanMs"]["p95"] = 12
        rows = SUMMARY.compare(current, baseline, 0.10, 0.5)
        self.assertTrue(rows[0][3])
        self.assertEqual(rows[-1][0], "score")

    def test_load_rejects_partial_invalid_and_unversioned_reports(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            partial = report()
            partial["scenarios"].pop()
            path.write_text(json.dumps(partial))
            with self.assertRaisesRegex(ValueError, "exact scenario list"):
                SUMMARY.load(path)
            path.write_text(json.dumps(dict(report(), score="bad")))
            with self.assertRaisesRegex(ValueError, "invalid"):
                SUMMARY.load(path)
            path.write_text(json.dumps(dict(report(), schemaVersion=1)))
            with self.assertRaisesRegex(ValueError, "schemaVersion"):
                SUMMARY.load(path)
            no_visual = report()
            del no_visual["scenarios"][0]["visual"]
            path.write_text(json.dumps(no_visual))
            with self.assertRaisesRegex(ValueError, "visual result"):
                SUMMARY.load(path)
            no_brightness = report()
            del no_brightness["scenarios"][0]["brightness"]
            path.write_text(json.dumps(no_brightness))
            with self.assertRaisesRegex(ValueError, "brightness"):
                SUMMARY.load(path)

    def test_atomic_write_round_trip(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "nested" / "report.json"
            SUMMARY.atomic_write(path, report())
            self.assertEqual(SUMMARY.load(path)["score"], 10)
            self.assertFalse(path.with_suffix(".json.tmp").exists())

    def test_main_returns_two_for_regression_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            baseline = Path(directory) / "baseline.json"
            output = Path(directory) / "latest.json"
            baseline.write_text(json.dumps(report()))
            slower = report()
            slower["score"] = 20
            for scene in slower["scenarios"]:
                scene["totalSpanMs"]["p95"] = 20
            current = Path(directory) / "current.json"
            current.write_text(json.dumps(slower))
            argv = ["summary", str(current), "--output", str(output),
                    "--baseline", str(baseline), "--fail-on-regression"]
            with patch("sys.argv", argv), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(SUMMARY.main(), 2)
            self.assertTrue(output.exists())

    def test_main_returns_two_for_visual_regression_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "latest.json"
            current = Path(directory) / "current.json"

            mismatched = report()
            mismatched["scenarios"][0]["visual"] = visual("mismatch", 0.02, 50, 40)
            current.write_text(json.dumps(mismatched))
            argv = ["summary", str(current), "--output", str(output),
                    "--fail-on-visual-regression"]
            with patch("sys.argv", argv), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(SUMMARY.main(), 2)

            with patch("sys.argv", argv), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(SUMMARY.main(), 2)

            missing = report()
            missing["scenarios"][2]["visual"] = visual("missing", 1.0)
            current.write_text(json.dumps(missing))
            with patch("sys.argv", argv), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(SUMMARY.main(), 2)

            current.write_text(json.dumps(report()))
            with patch("sys.argv", argv), redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(SUMMARY.main(), 0)


if __name__ == "__main__":
    unittest.main()
