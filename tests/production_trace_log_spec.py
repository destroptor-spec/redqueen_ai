import importlib.util
from pathlib import Path
import subprocess
import unittest

spec = importlib.util.spec_from_file_location(
    "production_trace", Path(__file__).resolve().parents[1] / "scripts" / "analyze-production-trace.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TraceLogSpec(unittest.TestCase):
    def test_current_producer_callbacks_and_reused_ids(self):
        output = subprocess.check_output(
            ["luajit", "tests/fixtures/production_trace_events.lua"],
            cwd=Path(__file__).resolve().parents[1], text=True,
        )
        summary = module.summarize(module.parse_events(output))
        self.assertIn("Observed completions: engineers=2, factories=1", summary)
        self.assertIn("Engineer 10 lifetime 1: 1 snapshots", summary)
        self.assertIn("Engineer 10 lifetime 2: 1 snapshots", summary)

    def test_quoted_fields_and_unevaluated_candidates(self):
        events = module.parse_events(
            'info: [RedQueen][INFO][army=2] production trace tick=200 event=selection '
            'domain=Land unit=10 selected="T2 Land Attack" '
            'candidates="Engineer:800:param=unevaluated:status=unevaluated"\n'
            'info: [RedQueen][INFO][army=2] production trace tick=300 event=capacity live=1 target=11\n'
        )
        self.assertEqual(events[0]["selected"], "T2 Land Attack")
        self.assertIn("status=unevaluated", events[0]["candidates"])
        self.assertIn("1/11 at 30s (line 2)", module.summarize(events))
        self.assertIn("T2 Land Attack: 1", module.summarize(events))

    def test_completions_are_separate_from_requests_and_per_army(self):
        events = module.parse_events(
            'info: [RedQueen][INFO][army=2] production trace tick=1 event=expansion accepted=true\n'
            'info: [RedQueen][INFO][army=2] production trace tick=2 event=request-state status=queue-absent\n'
            'info: [RedQueen][INFO][army=3] production trace tick=3 event=completed engineer=true factory=false\n'
        )
        summary = module.summarize(events)
        self.assertIn("Observed completions: engineers=0, factories=0", summary)
        self.assertIn("Observed completions: engineers=1, factories=0", summary)
        self.assertEqual(len(events), 3)

    def test_reused_entity_ids_do_not_merge_engineer_lifetimes(self):
        prefix = 'info: [RedQueen][INFO][army=2] production trace '
        events = module.parse_events(
            prefix + 'tick=100 event=engineer unit=10 manager=MAIN plan=EngineerBuildAI builder=Power states=Building flags=x queue=1\n'
            + prefix + 'tick=200 event=lost unit=10\n'
            + prefix + 'tick=300 event=completed unit=10 engineer=true factory=false\n'
            + prefix + 'tick=400 event=engineer unit=10 manager=MAIN plan=StateMachineAI builder=Reclaim states=Moving flags=y queue=0\n'
            + prefix + 'tick=500 event=request-state request=1 status=queued\n'
            + prefix + 'tick=600 event=request-state request=1 status=queue-absent\n'
        )
        summary = module.summarize(events)
        self.assertIn("Engineer 10 lifetime 1: 1 snapshots", summary)
        self.assertIn("Engineer 10 lifetime 2: 1 snapshots", summary)
        self.assertIn("callbacks include upgrades; not net capacity", summary)
        self.assertIn("Last observed request states: {'queue-absent': 1}", summary)

    def test_lifetimes_unknown_outcomes_and_aggregates(self):
        prefix = 'info: [RedQueen][INFO][army=2] production trace '
        events = module.parse_events(
            prefix + 'tick=1 event=construction-start subsystem=projects unit=10 lifetime=1\n'
            + prefix + 'tick=2 event=construction-outcome subsystem=projects unit=10 lifetime=1 outcome=destroyed\n'
            + prefix + 'tick=3 event=construction-start subsystem=projects unit=10 lifetime=2\n'
            + prefix + 'tick=300 event=aggregate subsystem=commitment state=held:strength count=7\n'
            + prefix + 'tick=600 event=aggregate subsystem=commitment state=held:strength count=5\n'
            + prefix + 'tick=600 event=overflow subsystem=projects count=1 coverage=incomplete\n'
        )
        summary = module.summarize(events)
        self.assertIn("('projects', 'destroyed'): 1", summary)
        self.assertIn("('projects', 'unknown'): 1", summary)
        self.assertIn("('commitment', 'held:strength'): 12", summary)
        self.assertIn('INCOMPLETE', summary)


if __name__ == "__main__":
    unittest.main()
