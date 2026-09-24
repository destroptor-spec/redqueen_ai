#!/usr/bin/env python3
"""Summarize passive production observations without inferring skipped eligibility."""
import argparse
from collections import Counter, defaultdict
from pathlib import Path
import re
import shlex


def parse_events(text):
    events = []
    for number, line in enumerate(text.splitlines(), 1):
        if "production trace tick=" not in line:
            continue
        army = re.search(r"\[army=(\d+)\]", line)
        fields = {}
        key = None
        for item in shlex.split(line.split("production trace ", 1)[1]):
            if "=" in item:
                key, value = item.split("=", 1)
                fields[key] = value
            elif key is not None:
                # Legacy traces left manager names such as Large Expansion
                # Area 1 unquoted. Retain the full value when reading them.
                fields[key] += " " + item
            else:
                raise ValueError(f"Malformed trace at line {number}")
        fields["army"] = army.group(1) if army else "?"
        fields["line"] = number
        fields["tick"] = int(fields["tick"])
        events.append(fields)
    return events


def placement_event(event, state):
    return event["event"] == state or (
        event["event"] == "placement" and event.get("state") == state
    )


def summarize(events):
    result = []
    for army in sorted({event["army"] for event in events}):
        own = [event for event in events if event["army"] == army]
        counts = Counter(event["event"] for event in own)
        result.append(f"Army {army}: " + ", ".join(f"{name}={count}" for name, count in sorted(counts.items())))
        aggregates = Counter()
        for event in own:
            if event["event"] == "aggregate":
                aggregates[event["subsystem"], event["state"]] += int(event["count"])
        result.append("Decision totals: " + repr(dict(aggregates)))
        incomplete = any(event["event"] == "overflow" or event.get("coverage") == "incomplete" for event in own)
        result.append("Trace coverage: " + ("INCOMPLETE (overflow)" if incomplete else "no reported overflow"))
        outcomes = {(e["subsystem"], e["lifetime"]): "unknown" for e in own if e["event"] == "construction-start"}
        for event in own:
            if event["event"] == "construction-outcome":
                outcomes[event["subsystem"], event["lifetime"]] = event["outcome"]
        result.append("Construction outcomes: " + repr(dict(Counter((key[0], outcome) for key, outcome in outcomes.items()))))
        result.append("Request attempts: " + str(sum(e["event"] == "expansion" for e in own)))
        result.append("Accepted requests: " + str(sum(e["event"] == "expansion" and e.get("accepted") == "true" for e in own)))
        capacities = [event for event in own if event["event"] == "capacity"]
        if capacities:
            peak = max(capacities, key=lambda event: int(event["target"]) - int(event["live"]))
            result.append(f"Largest sampled capacity gap: {peak['live']}/{peak['target']} at {peak['tick'] / 10:.0f}s (line {peak['line']})")
        selected = Counter(event.get("selected") for event in own if event["event"] == "selection" and event.get("domain") != "Any")
        result.append("Factory selections: " + "; ".join(f"{name}: {count}" for name, count in selected.most_common()))
        completed = [event for event in own if placement_event(event, "completed")]
        result.append(f"Observed completions: engineers={sum(e['engineer'] == 'true' for e in completed)}, factories={sum(e['factory'] == 'true' for e in completed)} (callbacks include upgrades; not net capacity)")
        engineers = defaultdict(list)
        lifetimes = defaultdict(lambda: 1)
        for event in own:
            if placement_event(event, "lost"):
                lifetimes[event["unit"]] += 1
            elif event["event"] == "engineer":
                engineers[event["unit"], lifetimes[event["unit"]]].append(event)
        for (unit, lifetime), samples in sorted(engineers.items()):
            owners = Counter((sample["manager"], sample["plan"], sample["builder"]) for sample in samples)
            result.append(f"Engineer {unit} lifetime {lifetime}: {len(samples)} snapshots; owners=" + repr(dict(owners)))
            last = samples[-1]
            result.append(f"  last line {last['line']} at {last['tick'] / 10:.0f}s: states={last['states']!r} flags={last['flags']!r} queue={last['queue']!r}")
        requests = Counter(event["status"] for event in own if event["event"] == "request-state")
        result.append("Request transitions: " + repr(dict(requests)))
        last_requests = {event["request"]: event["status"] for event in own
                         if event["event"] == "request-state" and "request" in event}
        result.append("Last observed request states: " + repr(dict(Counter(last_requests.values()))))
    return "\n".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    text = args.log.read_text(encoding="utf-8", errors="replace")
    if "production trace unavailable" in text:
        parser.error("the trace reported an observation failure; coverage is incomplete")
    events = parse_events(text)
    if not events:
        parser.error("no production trace events found")
    print(summarize(events))


if __name__ == "__main__":
    main()
