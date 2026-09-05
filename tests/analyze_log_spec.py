"""CLI regressions for failure occurrence accounting and attribution."""

import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ANALYZER = Path(__file__).resolve().parents[1] / "scripts" / "analyze-log.py"
START = "info: [RedQueen] started version=0.4.0"
DEFEAT = "info: GameResult 1 defeat"
DIRECT = "warning: Error running lua script: /mods/TheRedQueen/lua/AI/RedQueen/ProductionManager.lua:123: missing value"
FOREIGN = "warning: Error running lua script: /lua/platoon.lua:1555: missing value"
FRAME = r"warning: ...ds\theredqueen\lua\ai\redqueen\productionmanager.lua(1234): in function 'StartForwardBase'"


class AnalyzeLogSpec(unittest.TestCase):
    def analyze(self, *lines, startup=True):
        with tempfile.TemporaryDirectory(prefix="redqueen-analyzer-") as directory:
            path = Path(directory) / "game.log"
            content = ([START] if startup else []) + list(lines)
            path.write_text("\n".join(content) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ANALYZER), str(path)],
                capture_output=True, text=True, check=False,
            )
        self.assertEqual(result.stderr, "")
        return result

    def assert_totals(self, result, distinct, occurrences, attributed, foreign):
        self.assertIn(f"Failures: {distinct} distinct, {occurrences} occurrences", result.stdout)
        self.assertIn(f"Red Queen Lua failures: {attributed}\n", result.stdout)
        self.assertIn(f"Unattributed Lua failures: {foreign}\n", result.stdout)
        self.assertEqual(result.returncode, 1 if occurrences else 0)

    def test_clean_startup(self):
        result = self.analyze()
        self.assert_totals(result, 0, 0, 0, 0)
        self.assertIn("Post-defeat Lua failures: not checked", result.stdout)

    def test_missing_startup_still_fails(self):
        result = self.analyze(startup=False)
        self.assert_totals(result, 1, 1, 0, 0)
        self.assertIn("No Red Queen brain startup", result.stdout)

    def test_direct_failure_counted_once_after_defeat(self):
        result = self.analyze(DEFEAT, DIRECT)
        self.assert_totals(result, 1, 1, 1, 0)
        self.assertIn("Post-defeat Lua failures: 1 attributed, 0 in FAF code", result.stdout)

    def test_repeated_failure_across_defeat_is_one_distinct_defect(self):
        result = self.analyze(DIRECT, DEFEAT, DIRECT.replace("123", "456"), DIRECT)
        self.assert_totals(result, 1, 3, 3, 0)
        self.assertIn("Post-defeat Lua failures: 2 attributed, 0 in FAF code", result.stdout)

    def test_traceback_only_attribution_before_and_after_defeat(self):
        result = self.analyze(FOREIGN, FRAME, DEFEAT, FOREIGN, FRAME)
        self.assert_totals(result, 1, 2, 2, 0)
        self.assertIn("Post-defeat Lua failures: 1 attributed, 0 in FAF code", result.stdout)
        self.assertNotIn("Unattributed engine failures (advisory", result.stdout)

    def test_foreign_post_defeat_advisories_are_not_doubled(self):
        result = self.analyze(FOREIGN, DEFEAT, FOREIGN)
        self.assert_totals(result, 0, 0, 0, 2)
        self.assertIn("Post-defeat Lua failures: 0 attributed, 1 in FAF code", result.stdout)
        advisory = result.stdout.split("Unattributed engine failures (advisory, not gated):")[1]
        counts = re.findall(r"^\s+(\d+)x\s", advisory, re.MULTILINE)
        self.assertEqual(counts, ["2"])

    def test_interleaved_diagnostics_do_not_attribute_foreign_failure(self):
        result = self.analyze(DEFEAT, FOREIGN, "info: [RedQueen] state objective=Pressure")
        self.assert_totals(result, 0, 0, 0, 1)

    def test_next_failure_cannot_supply_traceback_attribution(self):
        result = self.analyze(DEFEAT, FOREIGN, FOREIGN, FRAME)
        self.assert_totals(result, 1, 1, 1, 1)
        self.assertIn("Post-defeat Lua failures: 1 attributed, 1 in FAF code", result.stdout)

    def test_scheduler_and_other_errors_keep_occurrence_counts(self):
        scheduler = "warning: [RedQueen][ERROR] scheduler task 'production' failed: missing value"
        result = self.analyze(scheduler, FRAME, scheduler, FRAME, "warning: [RedQueen][ERROR] broken contract")
        self.assert_totals(result, 2, 3, 0, 0)
        self.assertIn("Red Queen scheduler failures: 2", result.stdout)
        self.assertIn("in StartForwardBase", result.stdout)

    def test_desync_mentioned_in_lua_failure_is_one_occurrence(self):
        result = self.analyze(DIRECT + " desync")
        self.assert_totals(result, 1, 1, 1, 0)

    def test_standalone_desync_still_fails(self):
        result = self.analyze("warning: desync at beat 50")
        self.assert_totals(result, 1, 1, 0, 0)

    def test_unattributed_lua_desync_still_fails(self):
        result = self.analyze(FOREIGN + " desync")
        self.assert_totals(result, 1, 1, 0, 1)


if __name__ == "__main__":
    unittest.main()
