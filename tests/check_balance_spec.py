"""A changed score must not hide a lost win or invalid comparison evidence."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("balance", ROOT / "scripts/check-balance.py")
balance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(balance)


class BalanceSpec(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)

    def log(self, name="match", result="victory", extra="", seed=123):
        path = self.folder / (name + ".log")
        prefix = "info: [RedQueen][INFO][army=2] "
        lines = [
            "income contract allies=1 enemies=1 deficit=0 income=1.00",
            "match-contract army=2 name=ARMY_2 faction=2 side=ally start=10.0,20.0 income=1.00",
            "match-contract army=3 name=ARMY_3 faction=3 side=enemy start=90.0,80.0",
            "started version=V9 faction=2 victory=Assassination",
            "scouting mode=combined production=adaptive dispatch=on",
            "lifecycle game-result result=" + result,
        ]
        general = {"built": {"mass": 100}, "kills": {"mass": 80}, "lost": {"mass": 70}}
        rows = [{"type": "Human", "faction": 1, "name": "unused", "general": general, "units": {}},
                {"type": "AI", "faction": 2, "name": "own", "general": general, "units": {}},
                {"type": "AI", "faction": 3, "name": "opponent", "general": general, "units": {}}]
        path.write_text("\r\n".join(prefix + line for line in lines)
                        + '\r\ninfo: GameEnded\r\ninfo: ' + json.dumps({"stats": rows}) + "\n" + extra)
        files = {"mod_info.lua": "a" * 64}
        manifest = {"payload_sha256": balance.digest(files), "files": files, "map": "SCMP_015", "seed": seed,
                    "red_queen_faction": "2", "opponent_faction": "3", "difficulty": "44",
                    "mixed": "1", "fixed_runtime": "1", "scouting_mode": "combined"}
        Path(str(path) + ".manifest.json").write_text(json.dumps(manifest))
        runtime = Path(str(path) + ".runtime")
        runtime.mkdir(exist_ok=True)
        (runtime / "sources.json").write_text(json.dumps({"native_archive_sha256": "b" * 64}))
        return path

    def test_real_reader_and_cli_preserve_win_and_parse_line_endings(self):
        path = self.log()
        row = balance.read_match(path)
        self.assertEqual(row["settings"]["starts"], ["10.0,20.0", "90.0,80.0"])
        reference = self.folder / "reference.json"
        reference.write_text(json.dumps({"format": 1, "cases": [row]}))
        result = subprocess.run(["python3", "scripts/check-balance.py", "--reference", str(reference), str(path)],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lost wins=0", result.stdout)

    def test_equal_total_cannot_hide_lost_winning_case(self):
        old = [balance.read_match(self.log("a", seed=123)), balance.read_match(self.log("b", result="defeat", seed=456))]
        new = copy.deepcopy(old)
        new[0]["result"], new[1]["result"] = "defeat", "victory"
        report = balance.compare({"format": 1, "cases": old}, new)
        self.assertEqual(report["lost_wins"], ["SCMP_015/123/2-3"])
        self.assertEqual(report["gained_wins"], ["SCMP_015/456/2-3"])

    def test_invalid_coverage_and_settings_never_pass(self):
        old = balance.read_match(self.log())
        reference = {"format": 1, "cases": [old]}
        for rows in ([], [old, old]):
            with self.subTest(rows=len(rows)), self.assertRaises(ValueError):
                balance.compare(reference, rows)
        for key, value in (("income", "1.20"), ("starts", ["wrong", "starts"]), ("seed", 456),
                           ("native_lua_sha256", "c" * 64)):
            new = copy.deepcopy(old)
            new["settings"][key] = value
            with self.subTest(setting=key), self.assertRaises(ValueError):
                balance.compare(reference, [new])

    def test_mixed_candidate_payloads_rejected(self):
        old = [balance.read_match(self.log("a", seed=123)), balance.read_match(self.log("b", seed=456))]
        new = copy.deepcopy(old)
        new[1]["payload_sha256"] = "b" * 64
        with self.assertRaisesRegex(ValueError, "mixed candidate"):
            balance.compare({"format": 1, "cases": old}, new)

    def test_invalid_cli_run_replaces_stale_success_report(self):
        path = self.log()
        reference = self.folder / "reference.json"
        reference.write_text(json.dumps({"format": 1, "cases": [balance.read_match(path)]}))
        path.write_text(path.read_text().replace("GameEnded", "StillPlaying"))
        output = self.folder / "report.json"
        output.write_text('{"status":"passed"}')
        run = subprocess.run(["python3", "scripts/check-balance.py", "--reference", str(reference),
                              "--output", str(output), str(path)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(run.returncode, 2)
        self.assertEqual(json.loads(output.read_text())["status"], "invalid")

    def test_incomplete_wrong_contract_or_broken_match_rejected(self):
        replacements = [("GameEnded", "StillPlaying"), ('{"stats"', '{"missing"'),
                        ("income=1.00", "income=1.20"), ("faction=3 side=enemy", "faction=4 side=enemy"),
                        ("[army=2] lifecycle game-result", "[army=3] lifecycle game-result")]
        for before, after in replacements:
            with self.subTest(before=before):
                path = self.log()
                path.write_text(path.read_text().replace(before, after))
                with self.assertRaises(ValueError):
                    balance.read_match(path)
        path = self.log(extra="[RedQueen][ERROR][army=2] scheduler task 'production' failed: error\n")
        with self.assertRaisesRegex(ValueError, "analyzer failed"):
            balance.read_match(path)


if __name__ == "__main__":
    unittest.main()
