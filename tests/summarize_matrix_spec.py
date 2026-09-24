"""Keep scouting isolation arms and their observed mechanisms distinguishable."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FLAGS = {
    "combined": "production=adaptive dispatch=on",
    "production-only": "production=adaptive dispatch=off",
    "dispatch-only": "production=binary dispatch=on",
}


class SummarizeMatrixSpec(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)

    def log(self, name, mode=None, requested=None, states=""):
        path = self.base / f"rq-m-{name}.log"
        prefix = "[RedQueen][INFO][army=2] "
        text = prefix + "started version=8 faction=2 victory=demoralization\n"
        if mode:
            text += prefix + f"scouting mode={mode} {FLAGS[mode]}\n"
        path.write_text(text + states)
        manifest = {"payload_sha256": "a" * 64, "map": "SCMP_037", "seed": 2071971}
        if requested:
            manifest["scouting_mode"] = requested
        Path(str(path) + ".manifest.json").write_text(json.dumps(manifest))
        return path

    def summarize(self, *logs):
        return subprocess.run(["python3", "scripts/summarize-matrix.py", *map(str, logs)],
                              cwd=ROOT, capture_output=True, text=True)

    def test_same_payload_separates_modes_and_keeps_legacy_unknown(self):
        logs = [self.log(mode, mode, mode) for mode in FLAGS]
        logs.append(self.log("legacy"))
        result = self.summarize(*logs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("payload aaaaaaaaaaaa"), 4)
        for mode in (*FLAGS, "unrecorded"):
            self.assertIn(f"scouting={mode}  (1 runs)", result.stdout)

    def test_manifest_runtime_disagreement_is_rejected(self):
        path = self.log("wrong", "combined", "production-only")
        result = self.summarize(path)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("differs from runtime", result.stderr)
        self.assertNotIn("record:", result.stdout)

    def test_missing_runtime_confirmation_is_explicit(self):
        result = self.summarize(self.log("unconfirmed", requested="dispatch-only"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("scouting=unverified:dispatch-only", result.stdout)

    def test_cumulative_orders_survive_quiet_samples_and_ignore_other_armies(self):
        states = (
            "[RedQueen][INFO][army=2] state scout=10/8/2 scoutorders=5/1 scouts=3 scoutfraction=0.154\n"
            "[RedQueen][INFO][army=3] state scout=10/10/99 scoutorders=99/99 scouts=99 scoutfraction=0.999\n"
            "[RedQueen][INFO][army=2] state scout=10/4/0 scoutorders=5/1 scouts=2 scoutfraction=0.102\n"
        )
        result = self.summarize(self.log("orders", "combined", "combined", states))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mean blind 60% (2 samples)", result.stdout)
        self.assertIn("orders through last sample: scout=5 fallback=1", result.stdout)
        self.assertIn("peak held 3, requested fraction 0.102-0.154", result.stdout)

    def test_legacy_pass_counts_are_not_presented_as_match_totals(self):
        states = "[RedQueen][INFO][army=2] state scout=10/8/2\n" * 2
        result = self.summarize(self.log("legacy", states=states))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cumulative orders unrecorded", result.stdout)
        self.assertNotIn("scout=4", result.stdout)

    def test_outcome_belongs_to_selected_army(self):
        for own_result, other_result in (("victory", "defeat"), ("defeat", "victory")):
            with self.subTest(own_result=own_result):
                states = (
                    f"[RedQueen][INFO][army=3] lifecycle game-result result={other_result}\n"
                    f"[RedQueen][INFO][army=2] lifecycle game-result result={own_result}\n"
                )
                result = self.summarize(self.log("team", states=states))
                self.assertEqual(result.returncode, 0, result.stderr)
                row = next(line for line in result.stdout.splitlines() if line.strip().startswith("team "))
                self.assertIn(own_result, row)
                self.assertNotIn(other_result, row)

    def test_other_army_result_leaves_selected_army_unfinished(self):
        states = "[RedQueen][INFO][army=3] lifecycle game-result result=defeat\n"
        result = self.summarize(self.log("team", states=states))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("(unfinished)", result.stdout)


if __name__ == "__main__":
    unittest.main()
