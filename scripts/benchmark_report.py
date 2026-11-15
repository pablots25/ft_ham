#!/usr/bin/env python3
"""Turns the PipelinePerformanceTests results into a benchmark file and
compares it with the previous release.

    extract  reads `xcresulttool get test-results metrics` and `... summary`
             JSON and writes benchmarks/<version>-<build>.json
    compare  compares one benchmark file with the newest earlier one taken on
             the same machine (host CPU, Xcode, simulator model and iOS)

Exit codes for compare: 0 no regression (or nothing to compare with),
2 regression past the threshold, 1 bad input.

Only the standard library is used, so it runs on the release Mac and in CI.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

# displayName in the xcresult -> (key in the benchmark file, factor to convert)
METRICS = {
    "Clock Monotonic Time": ("clock_ms", 1000.0),  # seconds -> ms
    "CPU Time": ("cpu_ms", 1000.0),                # seconds -> ms
    "Memory Peak Physical": ("memory_peak_kb", 1.0),
}

# A metric regresses when it grows by more than the relative threshold AND by
# more than this absolute amount. The floor keeps sub-millisecond noise on
# fast benchmarks from failing a release.
ABSOLUTE_FLOOR = {
    "clock_ms": 1.0,
    "cpu_ms": 1.0,
    "memory_peak_kb": 5 * 1024.0,
}

# Clock is what the operator feels. CPU is reported but never blocks: on a
# simulator it follows the host's load more than the code.
GATED_METRICS = ("clock_ms", "memory_peak_kb")


def short_test_name(identifier: str) -> str:
    """'PipelinePerformanceTests/test_decodeBusySlot_FT8()' -> 'test_decodeBusySlot_FT8'"""
    name = identifier.rsplit("/", 1)[-1]
    return name[:-2] if name.endswith("()") else name


def extract(metrics_json: list, summary_json: dict, *, version: str, build: str,
            commit: str, host_cpu: str, xcode: str, date: str | None = None) -> dict:
    tests: dict[str, dict[str, float]] = {}
    for test in metrics_json:
        values: dict[str, float] = {}
        for run in test.get("testRuns", []):
            for metric in run.get("metrics", []):
                mapped = METRICS.get(metric.get("displayName", ""))
                measurements = metric.get("measurements") or []
                if not mapped or not measurements:
                    continue
                key, factor = mapped
                values[key] = round(statistics.median(measurements) * factor, 3)
        if values:
            tests[short_test_name(test.get("testIdentifier", "?"))] = values

    device = {}
    configurations = summary_json.get("devicesAndConfigurations") or []
    if configurations:
        device = configurations[0].get("device", {})

    return {
        "version": version,
        "build": int(build),
        "commit": commit,
        "date": date or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "machine": {
            "host_cpu": host_cpu,
            "xcode": xcode,
            "device": device.get("modelName") or device.get("deviceName", "unknown"),
            "os": " ".join(filter(None, [device.get("platform"), device.get("osVersion")])) or "unknown",
        },
        "tests": dict(sorted(tests.items())),
    }


def version_key(report: dict) -> tuple:
    parts = tuple(int(p) for p in str(report.get("version", "0.0.0")).split(".") if p.isdigit())
    return parts + (int(report.get("build", 0)),)


def find_previous(current: dict, history: list[dict]) -> dict | None:
    """Newest report older than `current` taken on the same machine."""
    machine = current.get("machine")
    candidates = [
        r for r in history
        if r.get("machine") == machine and version_key(r) < version_key(current)
    ]
    return max(candidates, key=version_key, default=None)


def compare(current: dict, previous: dict, threshold: float) -> tuple[list[str], list[str]]:
    """Returns (table lines, regressions)."""
    lines = [f"{'test':38} {'metric':15} {'before':>10} {'now':>10} {'change':>8}"]
    regressions: list[str] = []
    for test, now_values in current.get("tests", {}).items():
        before_values = previous.get("tests", {}).get(test)
        if not before_values:
            lines.append(f"{test:38} (new, nothing to compare)")
            continue
        for key, now in now_values.items():
            before = before_values.get(key)
            if before is None:
                continue
            change = (now - before) / before if before else 0.0
            flag = ""
            if (key in GATED_METRICS and change > threshold
                    and now - before > ABSOLUTE_FLOOR.get(key, 0.0)):
                flag = "  REGRESSION"
                regressions.append(f"{test} {key}: {before:g} -> {now:g} ({change:+.0%})")
            lines.append(f"{test:38} {key:15} {before:10g} {now:10g} {change:+8.0%}{flag}")
    return lines, regressions


def load_history(directory: Path, exclude: Path | None) -> list[dict]:
    reports = []
    for path in sorted(directory.glob("*.json")):
        if exclude and path.resolve() == exclude.resolve():
            continue
        try:
            reports.append(json.loads(path.read_text()))
        except (OSError, ValueError):
            print(f"warning: skipping unreadable {path}", file=sys.stderr)
    return reports


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    ex = sub.add_parser("extract")
    ex.add_argument("--metrics", required=True, type=Path)
    ex.add_argument("--summary", required=True, type=Path)
    ex.add_argument("--version", required=True)
    ex.add_argument("--build", required=True)
    ex.add_argument("--commit", required=True)
    ex.add_argument("--host-cpu", required=True)
    ex.add_argument("--xcode", required=True)
    ex.add_argument("--out", required=True, type=Path)

    cmp_ = sub.add_parser("compare")
    cmp_.add_argument("--current", required=True, type=Path)
    cmp_.add_argument("--history", required=True, type=Path)
    cmp_.add_argument("--threshold", type=float, default=0.20,
                      help="relative growth that counts as a regression (default 0.20)")

    args = parser.parse_args(argv)

    if args.command == "extract":
        try:
            metrics_json = json.loads(args.metrics.read_text())
            summary_json = json.loads(args.summary.read_text())
        except (OSError, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        report = extract(metrics_json, summary_json, version=args.version, build=args.build,
                         commit=args.commit, host_cpu=args.host_cpu, xcode=args.xcode)
        if not report["tests"]:
            print("error: no performance measurements in the results", file=sys.stderr)
            return 1
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + "\n")
        print(f"Wrote {args.out}")
        return 0

    try:
        current = json.loads(args.current.read_text())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    previous = find_previous(current, load_history(args.history, exclude=args.current))
    if previous is None:
        print("No earlier benchmark on this machine. This run becomes the baseline.")
        return 0
    print(f"Comparing {current['version']} ({current['build']}) with "
          f"{previous['version']} ({previous['build']}), threshold {args.threshold:.0%}")
    lines, regressions = compare(current, previous, args.threshold)
    print("\n".join(lines))
    if regressions:
        print("\nRegressions:")
        print("\n".join(f"  {r}" for r in regressions))
        return 2
    print("\nNo regressions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
