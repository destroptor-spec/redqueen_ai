#!/usr/bin/env python3
"""Watch a Red Queen match while it is still running.

Two rounds of spectating produced eight defects in an afternoon; a matrix of
twelve matches mostly reported that things had got worse without saying why.
The difference is that a spectator sees inventory and intent -- a commander
assisting a factory while the base browns out, a Tech 2 tier reached with no
Tech 2 point defence behind it -- and a win/loss column sees neither.

This reads the `watch` line the simulation now writes once a game minute and
turns it into the same observations, as they happen. Alarms fire on transition
and are the lines worth interrupting for; the periodic summary is context.

usage:
  watch-match.py <log> --follow      # tail a running match, alarms only
  watch-match.py <log> --timeline    # the whole match, one row per minute
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

WATCH = re.compile(
    r"\[RedQueen\]\[INFO\]\[army=(\d+)\] watch "
    r"t=(\d+) acu=(\w+)/(\d+)/(\d+) "
    r"def=pd(\d+)/(\d+)/(\d+),aa(\d+)/(\d+)/(\d+),tmd(\d+),sh(\d+)/(\d+)/(\d+),tml(\d+),arty(\d+) "
    r"mex=(\d+)/(\d+)/(\d+) eng=(\d+)/(\d+) "
    r"units=(\d+)/(\d+)/(\d+)/(\d+) enemy=(\d+)/(\d+)/(\d+)/(\d+) "
    r"store=([\d.]+)/([\d.]+)"
)
STATE = re.compile(
    r"\[RedQueen\]\[INFO\]\[army=(\d+)\] state objective=(\S+) primary=(\S+)/(\d+) "
    r"secondary=(\S+)/(\d+) pressure=(\w+)"
)
TIERS = re.compile(r"tiers=L(\d+),A(\d+),N(\d+)")
ENGINEER_TIERS = re.compile(r"engtier=(\d+)/(\d+)/(\d+)")
MEX_POINTS = re.compile(r" mex=(\d+)/(\d+) ")
ALERT = re.compile(r"alert=(\w+)/")
ECONOMY = re.compile(r" mass=([\d.]+) energy=([\d.]+) ")
RESULT = re.compile(r"(?i)GameResult\s+(\d+)\s+(victory|defeat|draw)")

# The leash the simulation itself uses (Constants.Policy.CommanderLeashRadius).
# Duplicated deliberately: a watcher that read the constant would go quiet the
# day the constant is widened, which is exactly the day it should complain.
COMMANDER_LEASH = 120
# Tier weights for a single "am I outgunned" number. Rough on purpose -- the
# figure only has to separate parity from a rout, which is what a spectator was
# doing by eye when they wrote "severely outgunned".
TIER_WEIGHT = (1.0, 3.0, 9.0, 40.0)


def clock(seconds: int) -> str:
    return f"{seconds // 60:02d}:{seconds % 60:02d}"


def strength(counts) -> float:
    return sum(weight * count for weight, count in zip(TIER_WEIGHT, counts))


class Army:
    """One Red Queen brain's running story."""

    def __init__(self, index: int) -> None:
        self.index = index
        self.samples: list[dict] = []
        self.fired: set[str] = set()
        self.tech2_reached_at: int | None = None
        self.objective: str | None = None

    # An alarm fires once. A condition that is true for twenty minutes is one
    # finding, not twenty, and a stream that repeats itself is one nobody reads.
    def once(self, key: str, message: str, out) -> None:
        if key in self.fired:
            return
        self.fired.add(key)
        print(message, file=out, flush=True)

    def observe(self, sample: dict, out, multi: bool) -> None:
        self.samples.append(sample)
        at = clock(sample["t"])
        tag = f"a{self.index} " if multi else ""

        if sample["tier_land"] >= 2 and self.tech2_reached_at is None:
            self.tech2_reached_at = sample["t"]
        # Tech 2 with nothing built behind it. Three minutes of grace: a tier is
        # reached the moment a factory finishes upgrading, and a defence cannot
        # exist the same second.
        # No Tech 2 engineer behind the tier. Every Tech 2 fortification
        # builder declares T2EngineerBuilder, so this alarm is upstream of the
        # missing defence below and says which of the two to go and look at.
        if (
            self.tech2_reached_at is not None
            and sample["t"] - self.tech2_reached_at >= 180
            and sample["eng_tiers"][1] + sample["eng_tiers"][2] == 0
        ):
            self.once(
                "t2-no-engineer",
                f"! {tag}{at} Tech 2 since {clock(self.tech2_reached_at)} and not one "
                f"Tech 2 engineer ({sample['eng_tiers'][0]} at Tech 1)",
                out,
            )
        if (
            self.tech2_reached_at is not None
            and sample["t"] - self.tech2_reached_at >= 180
            and sample["pd"][1] + sample["pd"][2] == 0
        ):
            self.once(
                "t2-no-pd",
                f"! {tag}{at} Tech 2 since {clock(self.tech2_reached_at)} and still no "
                f"Tech 2 point defence (pd {'/'.join(map(str, sample['pd']))})",
                out,
            )
        # A missile launcher before a defence was the first Tech 2 structure of
        # one observed match, under pressure, and it decided nothing.
        if sample["tml"] > 0 and sample["pd"][1] + sample["pd"][2] == 0:
            self.once(
                "tml-first",
                f"! {tag}{at} missile launcher built with no Tech 2 point defence anywhere",
                out,
            )
        # A Tech 3 extractor while Tech 1 extractors remain is the upgrade order
        # inverted -- the cheap doublings are still on the table.
        if sample["mex"][2] > 0 and sample["mex"][0] > 0:
            self.once(
                "mex-order",
                f"! {tag}{at} Tech 3 extractor with {sample['mex'][0]} still at Tech 1 "
                f"(mex {'/'.join(map(str, sample['mex']))})",
                out,
            )
        if sample["acu"] == "dead":
            self.once("acu-dead", f"! {tag}{at} commander is dead", out)
        elif sample["acu_distance"] > COMMANDER_LEASH:
            self.once(
                "acu-leash",
                f"! {tag}{at} commander {sample['acu_distance']}u from home "
                f"(leash {COMMANDER_LEASH}), {sample['acu']} at {sample['acu_health']}%",
                out,
            )
        if sample["acu_health"] and sample["acu_health"] < 50:
            self.once(
                "acu-hurt",
                f"! {tag}{at} commander at {sample['acu_health']}% health, "
                f"{sample['acu']} {sample['acu_distance']}u from home",
                out,
            )
        if sample["energy_stored"] < 0.05 and sample["t"] > 120:
            self.once(
                "brownout",
                f"! {tag}{at} energy storage at {sample['energy_stored']:.0%} "
                f"(commander {sample['acu']})",
                out,
            )
        if sample["idle_engineers"] >= 3:
            self.once(
                "idle-engineers",
                f"! {tag}{at} {sample['idle_engineers']} of {sample['engineers']} "
                "engineers idle",
                out,
            )
        theirs = strength(sample["enemy"])
        ours = strength(sample["units"])
        if theirs > 0 and ours / theirs < 0.5 and sample["t"] > 300:
            self.once(
                "outgunned",
                f"! {tag}{at} outgunned {ours:.0f} to {theirs:.0f} "
                f"(ours {'/'.join(map(str, sample['units']))}, "
                f"theirs {'/'.join(map(str, sample['enemy']))})",
                out,
            )
        # Map control, measured the way the user described it: not the count of
        # mass points but whether the count is going the wrong way, because an
        # extractor lost is production lost that buys the next one back slower.
        if len(self.samples) >= 4:
            window = [s["mex_total"] for s in self.samples[-4:]]
            if window[0] - window[-1] >= 3:
                self.once(
                    "losing-extractors",
                    f"! {tag}{at} extractors falling {window[0]} -> {window[-1]} "
                    "over three minutes",
                    out,
                )

    def note_objective(self, objective: str, pressure: str, out, multi: bool) -> None:
        tag = f"a{self.index} " if multi else ""
        at = clock(self.samples[-1]["t"]) if self.samples else "--:--"
        if objective != self.objective:
            previous = self.objective or "none"
            self.objective = objective
            print(f"  {tag}{at} objective {previous} -> {objective}", file=out, flush=True)
        if pressure == "yielded":
            self.once(
                "pressure-yielded",
                f"! {tag}{at} pressure yielded: the defence took the army",
                out,
            )

    def row(self, sample: dict) -> str:
        theirs = strength(sample["enemy"])
        ours = strength(sample["units"])
        ratio = (ours / theirs) if theirs else float("inf")
        return (
            f"{clock(sample['t'])} "
            f"{(sample.get('objective') or '-'):<14.14} "
            f"mass {sample.get('mass', 0):5.1f} "
            f"E{sample['energy_stored']:4.0%} "
            f"mex {sample['mex'][0]:2d}/{sample['mex'][1]:2d}/{sample['mex'][2]:2d} "
            f"eng {sample['engineers']:3d}({sample['idle_engineers']:2d} idle"
            f" {'/'.join(map(str, sample['eng_tiers']))}) "
            f"pd {sample['pd'][0]}/{sample['pd'][1]}/{sample['pd'][2]} "
            f"aa {sample['aa'][0]}/{sample['aa'][1]}/{sample['aa'][2]} "
            f"sh{'/'.join(str(v) for v in sample['shields'])} "
            f"acu {sample['acu']:<9.9} {sample['acu_distance']:3d}u {sample['acu_health']:3d}% "
            f"army {ours:5.0f} v {theirs:5.0f} ({ratio:4.2f})"
        )


def parse_watch(match: re.Match) -> dict:
    def number(index: int) -> int:
        return int(match.group(index))

    return {
        "army": number(1),
        "t": number(2),
        "acu": match.group(3),
        "acu_distance": number(4),
        "acu_health": number(5),
        "pd": (number(6), number(7), number(8)),
        "aa": (number(9), number(10), number(11)),
        "tmd": number(12),
        # Shields carry a tier split, as point defence and anti-air already do:
        # a Tech 2 shield is not the Tech 3 one the need asked for.
        "shields": (number(13), number(14), number(15)),
        "shields_total": number(13) + number(14) + number(15),
        "tml": number(16),
        "artillery": number(17),
        "mex": (number(18), number(19), number(20)),
        "mex_total": number(18) + number(19) + number(20),
        "idle_engineers": number(21),
        "engineers": number(22),
        "units": (number(23), number(24), number(25), number(26)),
        "enemy": (number(27), number(28), number(29), number(30)),
        "mass_stored": float(match.group(31)),
        "energy_stored": float(match.group(32)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--follow", action="store_true", help="tail a running match")
    parser.add_argument("--timeline", action="store_true", help="one row per game minute")
    parser.add_argument(
        "--summary-every", type=int, default=5,
        help="game minutes between context lines while following (0 disables)")
    parser.add_argument(
        "--timeout", type=int, default=0,
        help="stop following after this many seconds with no new line (0 waits forever)")
    arguments = parser.parse_args()

    out = sys.stdout
    armies: dict[int, Army] = {}
    pending: dict[int, dict] = {}
    last_summary: dict[int, int] = {}
    finished = False

    def flush(index: int) -> None:
        """Evaluate a watch line whose state line never arrived.

        The simulation writes the watch line first precisely so that a failure
        in the state line's fifty-field format cannot take the spectator's view
        with it. Defaulting the two fields the state line contributes keeps the
        rest.
        """
        sample = pending.pop(index, None)
        if sample is None:
            return
        sample.setdefault("tier_land", 1)
        sample.setdefault("mass", 0.0)
        sample.setdefault("eng_tiers", (sample["engineers"], 0, 0))
        armies[index].observe(sample, out, len(armies) > 1)

    def handle(line: str) -> None:
        nonlocal finished
        watch = WATCH.search(line)
        if watch:
            sample = parse_watch(watch)
            index = sample["army"]
            armies.setdefault(index, Army(index))
            flush(index)
            pending[index] = sample
            return
        state = STATE.search(line)
        if state:
            index = int(state.group(1))
            army = armies.get(index)
            sample = pending.pop(index, None)
            if not army or not sample:
                return
            multi = len(armies) > 1
            primary, secondary = state.group(3), state.group(5)
            objective = primary if secondary == "none" else f"{primary}+{secondary}"
            sample["objective"] = objective
            tiers = TIERS.search(line)
            sample["tier_land"] = int(tiers.group(1)) if tiers else 1
            engineers = ENGINEER_TIERS.search(line)
            sample["eng_tiers"] = (
                tuple(int(engineers.group(index)) for index in (1, 2, 3))
                if engineers else (sample["engineers"], 0, 0)
            )
            points = MEX_POINTS.search(line)
            sample["mass_points"] = int(points.group(2)) if points else 0
            economy = ECONOMY.search(line)
            sample["mass"] = float(economy.group(1)) if economy else 0.0
            army.observe(sample, out, multi)
            army.note_objective(objective, state.group(7), out, multi)
            if arguments.timeline:
                print(army.row(sample), file=out, flush=True)
            elif arguments.summary_every and (
                sample["t"] - last_summary.get(index, -10 ** 9)
                >= arguments.summary_every * 60
            ):
                last_summary[index] = sample["t"]
                print("  " + army.row(sample), file=out, flush=True)
            return
        result = RESULT.search(line)
        if result:
            index = int(result.group(1))
            print(f"= army {index} {result.group(2)}", file=out, flush=True)
            # Every army reports, and the opponents usually report first. Only a
            # result for a brain we were actually watching ends the watch.
            finished = index in armies

    if not arguments.follow:
        for line in arguments.log.read_text(encoding="utf-8", errors="replace").splitlines():
            handle(line)
        return 0

    # Follow. The log may not exist yet when the watcher is armed alongside the
    # launch, which is the normal case and not an error.
    while not arguments.log.exists():
        time.sleep(1)
    with arguments.log.open("r", encoding="utf-8", errors="replace") as handle_file:
        idle_since = time.time()
        while True:
            line = handle_file.readline()
            if line:
                idle_since = time.time()
                handle(line)
                if finished:
                    return 0
                continue
            if arguments.timeout and time.time() - idle_since > arguments.timeout:
                print("= log went quiet", file=out, flush=True)
                return 0
            time.sleep(0.5)


if __name__ == "__main__":
    raise SystemExit(main())
