#!/usr/bin/env bash
# scripts/benchmark.sh
# Runs the decode and message-processing benchmarks for a release and compares
# them with the previous release measured on the same machine.
#
# The results are written to benchmarks/<version>-<build>.json in this repo.
# Commit that file with the release so the next one has something to compare
# against. Numbers are only compared when the host CPU, Xcode version,
# simulator model and iOS version all match.
#
# Usage:
#   scripts/benchmark.sh <version> <build> [options]
#
# Options:
#   --project-root <dir>  Checkout holding ft8_ham.xcodeproj (default: this repo)
#   --simulator <udid>    Simulator to run on (default: $FTHAM_BENCH_SIMULATOR or the
#                         project's default simulator from AGENTS.md)
#   --threshold <ratio>   Growth that counts as a regression (default: 0.20 = 20%)
#   --report-only         Print regressions but exit 0 (for noisy CI runners)
#
# Exit codes: 0 no regression, 2 regression, 1 error.
#
# Example:
#   scripts/benchmark.sh 1.3.2 3 --project-root ../ft_ham-release-b3

set -euo pipefail

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

VERSION="${1:-}"
BUILD="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || usage
shift 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

PROJECT_ROOT="$REPO"
SIMULATOR="${FTHAM_BENCH_SIMULATOR:-186863B5-23F5-41F4-99C1-65794D33C739}"
THRESHOLD="0.20"
REPORT_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --simulator) SIMULATOR="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --report-only) REPORT_ONLY=true; shift ;;
    *) usage ;;
  esac
done

TEST_CLASS="PipelinePerformanceTests"
TEST_FILE="$PROJECT_ROOT/ft8_hamTests/Performance/$TEST_CLASS.swift"
HISTORY="$REPO/benchmarks"
OUT="$HISTORY/$VERSION-$BUILD.json"

fail() { echo "Error: $*" >&2; exit 1; }

[[ -d "$PROJECT_ROOT/ft8_ham.xcodeproj" ]] || fail "$PROJECT_ROOT/ft8_ham.xcodeproj not found"
if [[ ! -f "$TEST_FILE" ]]; then
  echo "Skipping benchmarks: $TEST_CLASS is not in this commit."
  exit 0
fi

work="$(mktemp -d -t ftham-bench)"
trap 'rm -rf "$work"' EXIT
bundle="$work/bench.xcresult"

echo "Running $TEST_CLASS on simulator $SIMULATOR (build output in a log, shown on failure)"
if ! xcodebuild test \
  -project "$PROJECT_ROOT/ft8_ham.xcodeproj" \
  -scheme ft8_ham \
  -destination "id=$SIMULATOR" \
  -only-testing:"ft8_hamTests/$TEST_CLASS" \
  -resultBundlePath "$bundle" \
  -quiet > "$work/xcodebuild.log" 2>&1; then
  tail -n 60 "$work/xcodebuild.log" >&2
  fail "benchmark tests failed (last 60 lines of the xcodebuild log above)"
fi
grep -E "^Test case '$TEST_CLASS" "$work/xcodebuild.log" || true

xcrun xcresulttool get test-results metrics --path "$bundle" > "$work/metrics.json"
xcrun xcresulttool get test-results summary --path "$bundle" > "$work/summary.json"

commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
host_cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
xcode="$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')"

python3 -I "$SCRIPT_DIR/benchmark_report.py" extract \
  --metrics "$work/metrics.json" \
  --summary "$work/summary.json" \
  --version "$VERSION" --build "$BUILD" \
  --commit "$commit" --host-cpu "$host_cpu" --xcode "$xcode" \
  --out "$OUT"

status=0
python3 -I "$SCRIPT_DIR/benchmark_report.py" compare \
  --current "$OUT" --history "$HISTORY" --threshold "$THRESHOLD" || status=$?

if [[ $status -eq 2 ]] && $REPORT_ONLY; then
  echo "Report only: not failing on the regression."
  exit 0
fi
exit "$status"
