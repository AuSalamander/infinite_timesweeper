#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
OUTPUT_DIR=${PERF_OUTPUT_DIR:-build/performance}
LOCK_ROOT=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
LOCK_DIR="$LOCK_ROOT/infinite-timesweeper-$(id -u)"
mkdir -p "$OUTPUT_DIR" "$LOCK_DIR"

# Serialize candidates across worktrees as well as within this checkout.
command -v flock >/dev/null 2>&1 || {
  echo "benchmark: required command not found: flock" >&2
  exit 1
}
exec 9>"$LOCK_DIR/benchmark.lock"
flock -n 9 || {
  echo "benchmark: another benchmark is already running" >&2
  exit 1
}

# Invalidate old results before any remaining preflight can fail. A crashed or
# invalid candidate must never look like a successful previous measurement.
rm -f "$OUTPUT_DIR/latest.json"
STATUS_FILE="$OUTPUT_DIR/latest-status.json"
printf '{"status":"running"}\n' >"$STATUS_FILE"
trap 'code=$?; if [[ $code -eq 0 ]]; then status=passed; elif [[ $code -eq 2 ]]; then status=regressed; else status=failed; fi; printf "{\"status\":\"%s\",\"exitCode\":%d}\n" "$status" "$code" >"$STATUS_FILE"' EXIT

if [[ -n "${FLUTTER:-}" ]]; then
  FLUTTER_CMD=("$FLUTTER")
elif command -v fvm >/dev/null 2>&1; then
  FLUTTER_CMD=(fvm flutter)
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_CMD=(flutter)
else
  echo "benchmark: Flutter not found (install it or set FLUTTER)" >&2
  exit 1
fi
for command_name in python3 cmake ninja pkg-config; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "benchmark: required command not found: $command_name" >&2
    exit 1
  }
done
pkg-config --exists gtk+-3.0 || {
  echo "benchmark: GTK 3 development files are required for the Linux runner" >&2
  exit 1
}
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "benchmark: a visible Linux display is required (DISPLAY/WAYLAND_DISPLAY unset)" >&2
  exit 1
fi

RUNS=${PERF_RUNS:-1}
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || {
  echo "benchmark: PERF_RUNS must be a positive integer" >&2
  exit 1
}
if [[ "${PERF_FAIL_ON_REGRESSION:-0}" == 1 && "$RUNS" -lt 3 ]]; then
  echo "benchmark: regression gating requires PERF_RUNS=3 or more" >&2
  exit 1
fi
if [[ "${PERF_FAIL_ON_REGRESSION:-0}" == 1 && -z "${PERF_BASELINE:-}" ]]; then
  echo "benchmark: PERF_FAIL_ON_REGRESSION=1 requires PERF_BASELINE" >&2
  exit 1
fi
if [[ -n "${PERF_BASELINE:-}" && ! -f "$PERF_BASELINE" ]]; then
  echo "benchmark: baseline not found: $PERF_BASELINE" >&2
  exit 1
fi

UPDATE_REFERENCES=${PERF_UPDATE_REFERENCES:-0}
[[ "$UPDATE_REFERENCES" =~ ^[01]$ ]] || {
  echo "benchmark: PERF_UPDATE_REFERENCES must be 0 or 1" >&2
  exit 1
}
if [[ "$UPDATE_REFERENCES" == 1 && "$RUNS" -ne 1 ]]; then
  echo "benchmark: reference updates require PERF_RUNS=1" >&2
  exit 1
fi
if [[ "$UPDATE_REFERENCES" == 1 && "${PERF_FAIL_ON_VISUAL_REGRESSION:-0}" == 1 ]]; then
  echo "benchmark: cannot update references and gate visual regressions in one run" >&2
  exit 1
fi

REFERENCE_DIR="$ROOT/test/reference/performance"
if [[ "$UPDATE_REFERENCES" == 0 && "${PERF_FAIL_ON_VISUAL_REGRESSION:-0}" == 1 ]]; then
  if ! compgen -G "$REFERENCE_DIR/*.png" >/dev/null; then
    echo "benchmark: no reference screenshots in $REFERENCE_DIR" >&2
    echo "benchmark: run PERF_UPDATE_REFERENCES=1 PERF_RUNS=1 first" >&2
    exit 1
  fi
fi

VERSION_JSON=$("${FLUTTER_CMD[@]}" --version --machine)
FLUTTER_VERSION=$(VERSION_JSON="$VERSION_JSON" python3 -c \
  'import json,os; v=json.loads(os.environ["VERSION_JSON"]); print("Flutter %s / Dart %s / engine %s" % (v["frameworkVersion"], v["dartSdkVersion"], v["engineRevision"]))')
GIT_REVISION=$(git describe --always --dirty)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
if [[ "$OUTPUT_DIR" = /* ]]; then
  SCREENSHOT_DIR="$OUTPUT_DIR/screenshots/$STAMP"
else
  SCREENSHOT_DIR="$ROOT/$OUTPUT_DIR/screenshots/$STAMP"
fi
UPDATE_DEFINE=false
if [[ "$UPDATE_REFERENCES" == 1 ]]; then
  UPDATE_DEFINE=true
  echo "benchmark: updating reference screenshots in $REFERENCE_DIR"
fi
REPORTS=()

for ((run=1; run<=RUNS; run++)); do
  if [[ "$OUTPUT_DIR" = /* ]]; then
    REPORT="$OUTPUT_DIR/${STAMP}-run${run}.json"
  else
    REPORT="$ROOT/$OUTPUT_DIR/${STAMP}-run${run}.json"
  fi
  REPORTS+=("$REPORT")
  LOAD_AVERAGE=$(cut -d' ' -f1-3 /proc/loadavg)
  echo "benchmark: profile run $run/$RUNS; keep the game window visible and idle"
  "${FLUTTER_CMD[@]}" drive --profile -d linux \
    --target=integration_test/performance_benchmark_test.dart \
    --driver=test_driver/performance_driver.dart \
    --dart-define="BENCH_OUT=$REPORT" \
    --dart-define="BENCH_FLUTTER_VERSION=$FLUTTER_VERSION" \
    --dart-define="BENCH_GIT_REVISION=$GIT_REVISION" \
    --dart-define="BENCH_LOAD_AVERAGE=$LOAD_AVERAGE" \
    --dart-define="BENCH_SCREENSHOT_DIR=$SCREENSHOT_DIR" \
    --dart-define="BENCH_REFERENCE_DIR=$REFERENCE_DIR" \
    --dart-define="BENCH_UPDATE_REFERENCE=$UPDATE_DEFINE"
done

SUMMARY_ARGS=(--output "$OUTPUT_DIR/latest.json")
if [[ -n "${PERF_BASELINE:-}" ]]; then
  SUMMARY_ARGS+=(--baseline "$PERF_BASELINE")
fi
if [[ "${PERF_FAIL_ON_REGRESSION:-0}" == 1 ]]; then
  SUMMARY_ARGS+=(--fail-on-regression)
fi
if [[ "${PERF_FAIL_ON_VISUAL_REGRESSION:-0}" == 1 ]]; then
  SUMMARY_ARGS+=(--fail-on-visual-regression)
fi
python3 scripts/performance_summary.py "${REPORTS[@]}" "${SUMMARY_ARGS[@]}"
