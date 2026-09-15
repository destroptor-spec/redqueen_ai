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

    def test_alert_arm_and_dispatch_are_reported(self):
        """The state line's per-arm and per-layer figures must reach the report.

        Defence is judged per arm, so an alert count cannot say which reading
        moved; and a fleet given no destination receives no order at all, which
        no outcome figure shows. Both are emitted by Diagnostics and parsed
        here, so this pins the two sides together.
        """
        state = (
            "info: [RedQueen][INFO][army=2] state objective=Raid eco=Stable "
            "mass=5.0 energy=50.0 factories=3/4 intel=2 doctrine=None focus=Army "
            "weights=A=60,T2=10,T3=5,X=20,N=0 ready=0.50 slots=1 reason=none "
            "landloss=0/0 airloss=0/0 airdrop=None "
            "alert=yes/210.0/2.50/{arm}/84/400 momentum=0/0/no tiers=L2,A1,N1 "
            "forward=0/no/none exp=None/0/0 eng=1/7/2 cover=2/9 engpolicy=3/18 "
            "mex=1/24 scout=10/6/0 scoutorders=11/4 scouts=1 scoutfraction=0.128 "
            "dispatch=L{land},A3,W{water},M2,H1"
        )
        result = self.analyze(
            state.format(arm="surface", land=12, water=0),
            state.format(arm="combined", land=4, water=7),
        )
        self.assertIn("Alert samples by qualifying arm: combined 1, surface 1", result.stdout)
        self.assertIn("Peak units dispatched per layer: L12, A3, W7, M2, H1", result.stdout)

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

    def test_native_invalid_location_after_defeat_is_advisory(self):
        """A defeated army's manager teardown is FAF's, not ours.

        All 11 of these in the 21-cell matrix named a native location after a
        defeat, with a traceback wholly inside adaptive-ai.lua.
        """
        result = self.analyze(
            DEFEAT,
            "warning: *AI WARNING: FactoryCapCheck - Invalid location - MAIN",
            r"warning: ...gamedata\lua.nx2\lua\aibrains\adaptive-ai.lua(498): in function `GetManagerCount'",
        )
        self.assert_totals(result, 0, 0, 0, 0)
        self.assertIn("Invalid manager locations: 0 attributed, 1 in FAF code", result.stdout)
        self.assertIn("invalid manager location - MAIN", result.stdout)

    def test_own_site_invalid_location_still_fails_after_defeat(self):
        """A leaked builder for one of our retired sites is our defect."""
        result = self.analyze(
            DEFEAT,
            "warning: *AI WARNING: FactoryCapCheck - Invalid location - RQFB_2_1",
        )
        self.assertIn("Invalid manager locations: 1 attributed, 0 in FAF code", result.stdout)
        self.assertIn("invalid manager location - RQFB_2_1", result.stdout)
        self.assertEqual(result.returncode, 1)

    def test_traceback_attributes_invalid_location_at_native_name(self):
        """Our frame is evidence even when the location name is FAF's."""
        result = self.analyze(
            "warning: *AI WARNING: FactoryCapCheck - Invalid location - MAIN",
            FRAME,
        )
        self.assertIn("Invalid manager locations: 1 attributed, 0 in FAF code", result.stdout)
        self.assertEqual(result.returncode, 1)

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
