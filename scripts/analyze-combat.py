#!/usr/bin/env python3
"""Summarize bounded combat telemetry, after the normal match failure gate."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def summarize(text, army):
    controllers, factories, blueprints, plans = {}, {}, {}, {}
    # A claimed order is not protection; arrived against sent is the difference.
    # The share of our own combat mass that is in one fight at one time.
    conc = {"samples": 0, "largest_mass": 0, "total_mass": 0, "occupied_cells": 0}
    defence = {"samples": 0, "samples_with_force_sent": 0, "required": 0,
               "available": 0, "claimed": 0, "deficit": 0, "sent": 0, "arrived": 0}
    detail = {"samples": 0, "idle_unit_samples": 0, "unit_samples": 0,
              "near_target_samples": 0, "omitted_platoon_samples": 0,
              # A directed platoon carrying no id cannot appear in the detail
              # lines. Non-zero here means the detail undercounts the directed
              # force and the summary must not be read as complete.
              "unkeyed_unit_samples": 0}
    prefix = f"[army={army}]"
    samples, repeated_deaths = 0, 0
    for line in text.splitlines():
        if prefix not in line:
            continue
        if " state " in line and "combatctl=" in line:
            samples += 1
            value = line.split("combatctl=", 1)[1].split()[0]
            for entry in value.split(","):
                name, values = entry.split(":")
                count, mass, idle, lost = map(float, values.split("/"))
                c = controllers.setdefault(name, {"unit_samples": 0, "mass_samples": 0,
                                                  "idle_unit_samples": 0, "lost_mass": 0})
                c["unit_samples"] += count
                c["mass_samples"] += mass
                c["idle_unit_samples"] += idle
                c["lost_mass"] = lost
            match = re.search(r"combatdetail=(\d+)/(\d+)", line)
            if match:
                detail["omitted_platoon_samples"] += int(match[2]) - int(match[1])
            match = re.search(r"combatconc=([\d.]+)/([\d.]+)/(\d+)", line)
            if match:
                conc["samples"] += 1
                conc["largest_mass"] += float(match[1])
                conc["total_mass"] += float(match[2])
                conc["occupied_cells"] += int(match[3])
            match = re.search(r"combatunkeyed=(\d+)", line)
            if match:
                detail["unkeyed_unit_samples"] += int(match[1])
            match = re.search(r"combatdeathrepeats=(\d+)", line)
            if match:
                repeated_deaths = int(match[1])
        elif " combat-production " in line:
            for entry in re.search(r"factories=([^ ]*)", line)[1].split(","):
                if not entry:
                    continue
                name, values = entry.split(":")
                ready, building, upgrading, idle = map(int, values.split("/"))
                f = factories.setdefault(name, {"ready_samples": 0, "building_samples": 0,
                                               "upgrading_samples": 0, "idle_samples": 0})
                for key, value in zip(f, (ready, building, upgrading, idle)):
                    f[key] += value
            value = re.search(r"units=([^ ]*)", line)[1].strip()
            for entry in value.split(","):
                if entry:
                    name, values = entry.split(":")
                    built, lost, held = map(int, values.split("/"))
                    blueprints[name] = {"completed": built, "lost": lost, "held": held}
        elif " combat-plans " in line:
            for entry in re.search(r"plans=(.*)$", line)[1].strip().split(","):
                if not entry:
                    continue
                name, values = entry.rsplit(":", 1)
                held, held_mass, lost, lost_mass = map(float, values.split("/"))
                p = plans.setdefault(name, {"held_unit_samples": 0, "held_mass_samples": 0,
                                            "lost_units": 0, "lost_mass": 0})
                p["held_unit_samples"] += held
                p["held_mass_samples"] += held_mass
                # Cumulative, so the last sample is the total, not a sum.
                p["lost_units"] = lost
                p["lost_mass"] = lost_mass
        elif " combat-defence " in line:
            v = dict(re.findall(r"(\w+)=([\d.]+)", line))
            defence["samples"] += 1
            for key in ("required", "available", "claimed", "deficit", "sent", "arrived"):
                defence[key] += float(v.get(key, 0))
            if float(v.get("sent", 0)) > 0:
                defence["samples_with_force_sent"] += 1
        elif " combat-platoon " in line:
            values = dict(re.findall(r"(\w+)=([^ ]+)", line))
            detail["samples"] += 1
            detail["unit_samples"] += int(values["units"])
            detail["idle_unit_samples"] += int(values["idle"])
            if 0 <= float(values["distance"]) <= 35:
                detail["near_target_samples"] += 1
    return {"army": army, "state_samples": samples, "controllers": controllers,
            "repeated_death_callbacks": repeated_deaths,
            "factories": factories, "blueprints": blueprints, "plans": plans,
            "defence": defence, "concentration": conc, "directed_detail": detail}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--army", type=int, default=2)
    args = parser.parse_args()
    gate = subprocess.run(["python3", str(Path(__file__).with_name("analyze-log.py")), str(args.log)],
                          capture_output=True, text=True)
    if gate.returncode:
        raise SystemExit(gate.stdout + gate.stderr)
    result = summarize(args.log.read_text(errors="replace"), args.army)
    if not result["state_samples"]:
        raise SystemExit("No combat telemetry for the selected army")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
