"""Unit tests for scripts/benchmark_report.py (offline, standard library only).

Run with: python3 -m unittest discover -s scripts/tests -v
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import benchmark_report as br  # noqa: E402


def metrics_json(clock_s=(0.0166, 0.0167, 0.0165), cpu_s=(0.0175,), memory_kb=(73000.0,)):
    """Cut-down `xcresulttool get test-results metrics` output."""
    return [
        {
            "testIdentifier": "PipelinePerformanceTests/test_decodeBusySlot_FT8()",
            "testRuns": [{
                "device": {"deviceName": "iPhone 16"},
                "metrics": [
                    {"displayName": "Clock Monotonic Time", "unitOfMeasurement": "s", "measurements": list(clock_s)},
                    {"displayName": "CPU Time", "unitOfMeasurement": "s", "measurements": list(cpu_s)},
                    {"displayName": "Memory Peak Physical", "unitOfMeasurement": "kB", "measurements": list(memory_kb)},
                    {"displayName": "Memory Physical", "unitOfMeasurement": "kB", "measurements": [32.0]},
                ],
            }],
        },
        {
            "testIdentifier": "PipelinePerformanceTests/test_decodeRecordedFixtures()",
            "testRuns": [{"metrics": []}],
        },
    ]


SUMMARY = {
    "devicesAndConfigurations": [{
        "device": {"modelName": "iPhone 16", "osVersion": "18.6", "platform": "iOS Simulator"},
    }],
}


def report(version="1.3.2", build="3", **metric_overrides):
    return br.extract(metrics_json(**metric_overrides), SUMMARY, version=version, build=build,
                      commit="abc", host_cpu="Apple M3", xcode="Xcode 26.6", date="2026-11-14T00:00:00Z")


class ExtractTests(unittest.TestCase):

    def test_takes_the_median_in_ms_and_kb(self):
        values = report()["tests"]["test_decodeBusySlot_FT8"]
        self.assertEqual(values, {"clock_ms": 16.6, "cpu_ms": 17.5, "memory_peak_kb": 73000.0})

    def test_skipped_tests_and_unknown_metrics_are_left_out(self):
        self.assertEqual(list(report()["tests"]), ["test_decodeBusySlot_FT8"])

    def test_records_the_machine(self):
        self.assertEqual(report()["machine"], {
            "host_cpu": "Apple M3", "xcode": "Xcode 26.6",
            "device": "iPhone 16", "os": "iOS Simulator 18.6",
        })

    def test_short_test_name(self):
        self.assertEqual(br.short_test_name("A/test_x()"), "test_x")
        self.assertEqual(br.short_test_name("test_y"), "test_y")


class CompareTests(unittest.TestCase):

    def test_twenty_five_percent_slower_decode_is_a_regression(self):
        before = report()
        now = report(version="1.3.3", build="1", clock_s=(0.0208,))
        _, regressions = br.compare(now, before, threshold=0.20)
        self.assertEqual(len(regressions), 1)
        self.assertIn("clock_ms", regressions[0])

    def test_small_absolute_change_is_noise_even_if_relative_is_large(self):
        # 2 ms -> 2.9 ms is +45% but under the 1 ms floor.
        before = report(clock_s=(0.002,))
        now = report(version="1.3.3", build="1", clock_s=(0.0029,))
        _, regressions = br.compare(now, before, threshold=0.20)
        self.assertEqual(regressions, [])

    def test_cpu_alone_never_blocks(self):
        before = report(cpu_s=(0.010,))
        now = report(version="1.3.3", build="1", cpu_s=(0.050,))
        lines, regressions = br.compare(now, before, threshold=0.20)
        self.assertEqual(regressions, [])
        self.assertTrue(any("cpu_ms" in line for line in lines))

    def test_memory_growth_past_floor_is_a_regression(self):
        before = report(memory_kb=(60_000.0,))
        now = report(version="1.3.3", build="1", memory_kb=(80_000.0,))
        _, regressions = br.compare(now, before, threshold=0.20)
        self.assertEqual(len(regressions), 1)
        self.assertIn("memory_peak_kb", regressions[0])

    def test_faster_is_never_a_regression(self):
        before = report()
        now = report(version="1.3.3", build="1", clock_s=(0.005,))
        self.assertEqual(br.compare(now, before, threshold=0.20)[1], [])

    def test_new_test_is_listed_without_comparison(self):
        before = report()
        before["tests"] = {}
        lines, regressions = br.compare(report(version="1.3.3"), before, threshold=0.20)
        self.assertEqual(regressions, [])
        self.assertTrue(any("new, nothing to compare" in line for line in lines))


class PreviousTests(unittest.TestCase):

    def test_picks_the_newest_earlier_report_on_the_same_machine(self):
        current = report(version="1.4.0", build="2")
        older = report(version="1.3.2", build="3")
        newer = report(version="1.3.10", build="1")
        later = report(version="1.4.0", build="5")
        other_machine = report(version="1.3.11", build="1")
        other_machine["machine"]["host_cpu"] = "Apple M1"
        self.assertIs(br.find_previous(current, [older, newer, later, other_machine]), newer)

    def test_none_when_nothing_matches(self):
        current = report()
        other = report(version="1.0.0")
        other["machine"]["os"] = "iOS Simulator 26.1"
        self.assertIsNone(br.find_previous(current, [other]))


class MainTests(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data):
        path = self.dir / name
        path.write_text(json.dumps(data))
        return path

    def extract_args(self, metrics, summary, version, build, out):
        return ["extract", "--metrics", str(metrics), "--summary", str(summary), "--version", version,
                "--build", build, "--commit", "abc", "--host-cpu", "Apple M3", "--xcode", "Xcode 26.6",
                "--out", str(out)]

    def test_extract_then_compare_exit_codes(self):
        summary = self.write("summary.json", SUMMARY)
        history = self.dir / "benchmarks"

        first = history / "1.3.2-3.json"
        metrics = self.write("metrics.json", metrics_json())
        self.assertEqual(br.main(self.extract_args(metrics, summary, "1.3.2", "3", first)), 0)
        self.assertTrue(first.exists())
        # First run on a machine: nothing to compare with.
        self.assertEqual(br.main(["compare", "--current", str(first), "--history", str(history)]), 0)

        second = history / "1.3.3-1.json"
        slow = self.write("slow-metrics.json", metrics_json(clock_s=(0.030,)))
        self.assertEqual(br.main(self.extract_args(slow, summary, "1.3.3", "1", second)), 0)
        self.assertEqual(br.main(["compare", "--current", str(second), "--history", str(history)]), 2)

    def test_extract_without_measurements_fails(self):
        metrics = self.write("metrics.json", [])
        summary = self.write("summary.json", SUMMARY)
        code = br.main(["extract", "--metrics", str(metrics), "--summary", str(summary), "--version", "1.0.0",
                        "--build", "1", "--commit", "x", "--host-cpu", "c", "--xcode", "x",
                        "--out", str(self.dir / "out.json")])
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
