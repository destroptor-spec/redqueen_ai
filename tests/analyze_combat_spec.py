import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("combat", Path(__file__).parents[1] / "scripts/analyze-combat.py")
combat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(combat)


class CombatLogTests(unittest.TestCase):
    def test_army_filter_cumulative_losses_and_partial_detail(self):
        lines = """[army=2] state combatctl=directed:3/540/1/180 combatdetail=12/15 combatunkeyed=2
[army=3] state combatctl=directed:90/9999/90/9999 combatdetail=0/90
[army=2] combat-platoon units=3 idle=1 distance=20
[army=2] combat-production factories=L1:3/1/0/2,L2:1/1/0/0 units=xal0203:8/5/3
[army=2] state combatctl=directed:2/360/2/360 combatdetail=2/2
[army=2] combat-production factories=L1:3/0/1/2 units=xal0203:9/7/2
[army=2] combat-plans t=60 shown=2/5 plans=AttackForceAI:4/720/9/1620,RedQueenDirected:3/540/4/720
[army=2] combat-defence t=60 required=120 available=900 claimed=80 deficit=40 sent=2 arrived=1 arrivedmass=180 kinds=Defend:2/1/360/180
"""
        result = combat.summarize(lines, 2)
        self.assertEqual(result["state_samples"], 2)
        self.assertEqual(result["controllers"]["directed"]["lost_mass"], 360)
        self.assertEqual(result["controllers"]["directed"]["unit_samples"], 5)
        self.assertEqual(result["factories"]["L1"]["idle_samples"], 4)
        self.assertEqual(result["blueprints"]["xal0203"], {"completed": 9, "lost": 7, "held": 2})
        self.assertEqual(result["directed_detail"]["omitted_platoon_samples"], 3)
        # An unkeyed directed platoon is invisible in the detail lines, so the
        # count has to surface or the summary reads as complete when it is not.
        self.assertEqual(result["directed_detail"]["unkeyed_unit_samples"], 2)
        # Cumulative per-plan losses are a total, not something to sum.
        self.assertEqual(result["plans"]["AttackForceAI"]["lost_mass"], 1620)
        self.assertEqual(result["plans"]["RedQueenDirected"]["held_mass_samples"], 540)
        # Sent is an order; arrived is protection. Keep them apart.
        self.assertEqual(result["defence"]["sent"], 2)
        self.assertEqual(result["defence"]["arrived"], 1)
        self.assertEqual(result["defence"]["deficit"], 40)

    def test_legacy_logs_do_not_invent_measurements(self):
        result = combat.summarize("[army=2] state directed=200/300", 2)
        self.assertEqual(result["state_samples"], 0)
        self.assertEqual(result["controllers"], {})


if __name__ == "__main__":
    unittest.main()
