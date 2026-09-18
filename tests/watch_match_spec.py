"""The live watcher. Every alarm here was first spotted by eye on a screen."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WATCHER = Path(__file__).resolve().parents[1] / "scripts" / "watch-match.py"


def watch_line(t, **overrides):
    fields = dict(
        acu="assisting", distance=10, health=100,
        pd=(0, 0, 0), aa=(0, 0, 0), tmd=0, sh=0, tml=0, arty=0,
        mex=(4, 0, 0), idle=0, eng=8,
        units=(10, 0, 0, 0), enemy=(10, 0, 0, 0), stored=(0.5, 0.5),
    )
    fields.update(overrides)
    return (
        f"info: [RedQueen][INFO][army=2] watch t={t} "
        f"acu={fields['acu']}/{fields['distance']}/{fields['health']} "
        f"def=pd{'/'.join(map(str, fields['pd']))},aa{'/'.join(map(str, fields['aa']))},"
        f"tmd{fields['tmd']},sh{fields['sh']},tml{fields['tml']},arty{fields['arty']} "
        f"mex={'/'.join(map(str, fields['mex']))} eng={fields['idle']}/{fields['eng']} "
        f"units={'/'.join(map(str, fields['units']))} "
        f"enemy={'/'.join(map(str, fields['enemy']))} "
        f"store={fields['stored'][0]:.2f}/{fields['stored'][1]:.2f}"
    )


def state_line(objective="Pressure", tier_land=1, pressure="held", mass=10.0):
    return (
        f"info: [RedQueen][INFO][army=2] state objective={objective} "
        f"primary={objective}/4 secondary=none/0 pressure={pressure} claim=0/0 "
        f"eco=Balanced mass={mass:.1f} energy=100.0 factories=2/2 intel=0 "
        f"doctrine=Balanced focus=Army tiers=L{tier_land},A1,N1 mex=4/44 "
    )


class WatchMatchSpec(unittest.TestCase):
    def watch(self, *lines, timeline=False):
        with tempfile.TemporaryDirectory(prefix="redqueen-watcher-") as directory:
            path = Path(directory) / "game.log"
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            command = [sys.executable, str(WATCHER), str(path)]
            if timeline:
                command.append("--timeline")
            result = subprocess.run(command, capture_output=True, text=True, check=False)
        self.assertEqual(result.stderr, "", result.stderr)
        self.assertEqual(result.returncode, 0)
        return result.stdout

    def test_tech2_without_point_defence_is_reported(self):
        lines = []
        for minute in range(1, 8):
            lines.append(watch_line(minute * 60))
            lines.append(state_line(tier_land=2 if minute >= 2 else 1))
        output = self.watch(*lines)
        self.assertIn("still no Tech 2 point defence", output)

    def test_tech2_with_point_defence_is_silent(self):
        lines = []
        for minute in range(1, 8):
            lines.append(watch_line(minute * 60, pd=(2, 1, 0)))
            lines.append(state_line(tier_land=2 if minute >= 2 else 1))
        self.assertNotIn("point defence", self.watch(*lines))

    def test_tech3_point_defence_satisfies_the_tech2_alarm(self):
        """The alarm asks whether anything better than Tech 1 stands in the
        base. A base that skipped straight to Tech 3 has answered it."""
        lines = []
        for minute in range(1, 8):
            lines.append(watch_line(minute * 60, pd=(2, 0, 1)))
            lines.append(state_line(tier_land=3 if minute >= 2 else 1))
        self.assertNotIn("point defence", self.watch(*lines))

    def test_the_grace_period_covers_the_minute_a_tier_lands(self):
        """A tier is reached the second a factory finishes; a defence cannot
        already exist, and an alarm that fires there cries wolf every match."""
        lines = [watch_line(300), state_line(tier_land=2)]
        self.assertNotIn("point defence", self.watch(*lines))

    def test_commander_beyond_the_leash(self):
        output = self.watch(watch_line(600, distance=240, acu="attacking"), state_line())
        self.assertIn("commander 240u from home", output)

    def test_commander_death(self):
        output = self.watch(watch_line(600, acu="dead", health=0), state_line())
        self.assertIn("commander is dead", output)

    def test_tech3_extractor_while_tech1_remain(self):
        output = self.watch(watch_line(900, mex=(6, 2, 1)), state_line())
        self.assertIn("Tech 3 extractor with 6 still at Tech 1", output)

    def test_tech3_extractor_after_the_field_is_upgraded_is_silent(self):
        output = self.watch(watch_line(900, mex=(0, 5, 1)), state_line())
        self.assertNotIn("Tech 3 extractor", output)

    def test_idle_engineers(self):
        output = self.watch(watch_line(300, idle=4, eng=11), state_line())
        self.assertIn("4 of 11 engineers idle", output)

    def test_outgunned(self):
        output = self.watch(
            watch_line(600, units=(6, 0, 0, 0), enemy=(20, 2, 0, 0)), state_line())
        self.assertIn("outgunned", output)

    def test_parity_is_silent(self):
        output = self.watch(
            watch_line(600, units=(18, 0, 0, 0), enemy=(20, 0, 0, 0)), state_line())
        self.assertNotIn("outgunned", output)

    def test_extractors_falling(self):
        lines = []
        for minute, count in enumerate([12, 11, 9, 7], start=1):
            lines.append(watch_line(minute * 60, mex=(count, 0, 0)))
            lines.append(state_line())
        self.assertIn("extractors falling 12 -> 7", self.watch(*lines))

    def test_an_alarm_fires_once(self):
        lines = []
        for minute in range(1, 10):
            lines.append(watch_line(minute * 60, idle=5, eng=9))
            lines.append(state_line())
        self.assertEqual(self.watch(*lines).count("engineers idle"), 1)

    def test_objective_changes_are_narrated(self):
        output = self.watch(
            watch_line(60), state_line(objective="Raid"),
            watch_line(120), state_line(objective="Raid"),
            watch_line(180), state_line(objective="Defend"),
        )
        self.assertIn("objective none -> Raid", output)
        self.assertIn("objective Raid -> Defend", output)
        self.assertEqual(output.count("-> Raid"), 1)

    def test_pressure_yielded(self):
        output = self.watch(watch_line(600), state_line(pressure="yielded"))
        self.assertIn("pressure yielded", output)

    def test_a_watch_line_survives_a_missing_state_line(self):
        """The simulation writes the watch line first so a failure in the state
        line's fifty-field format cannot take the spectator's view with it."""
        output = self.watch(
            watch_line(600, acu="dead", health=0),
            watch_line(660, acu="idle", health=100),
            state_line(),
        )
        self.assertIn("commander is dead", output)

    def test_timeline_has_a_row_per_minute(self):
        lines = []
        for minute in range(1, 5):
            lines.append(watch_line(minute * 60))
            lines.append(state_line())
        rows = [row for row in self.watch(*lines, timeline=True).splitlines()
                if row.startswith("0")]
        self.assertEqual(len(rows), 4)
        self.assertIn("01:00", rows[0])

    def test_a_foreign_result_does_not_end_the_watch(self):
        """Opponents report first. A watcher that stopped on the first
        GameResult would go blind for the rest of the match -- including the
        minutes where a losing Red Queen is most worth watching."""
        with tempfile.TemporaryDirectory(prefix="redqueen-watcher-") as directory:
            path = Path(directory) / "game.log"
            path.write_text("\n".join([
                watch_line(60), state_line(),
                "debug: GpgNetSend\tGameResult\t3\tvictory 10",
                watch_line(120, acu="dead", health=0), state_line(),
            ]) + "\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(WATCHER), str(path), "--follow", "--timeout", "2"],
                capture_output=True, text=True, check=False, timeout=30)
        self.assertEqual(result.returncode, 0)
        self.assertIn("army 3 victory", result.stdout)
        self.assertIn("commander is dead", result.stdout)

    def test_the_result_is_reported(self):
        output = self.watch(watch_line(60), state_line(), "info: GameResult 2 defeat")
        self.assertIn("army 2 defeat", output)


if __name__ == "__main__":
    unittest.main()
