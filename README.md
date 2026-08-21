# The Red Queen

The Red Queen is an adaptive skirmish AI for Supreme Commander: Forged Alliance Forever. It combines FAF's maintained adaptive-AI machinery with an original strategic layer for intel-led counterplay, map denial, production scaling, coordinated combat, and allied support.

## Current behavior

- Appears in the lobby as `AI: The Red Queen`.
- Supports the four standard FAF factions.
- Classifies land, mixed, island, and naval maps from 5–40 km.
- Uses only observed enemy units plus publicly known starting positions.
- Tracks sightings with decaying confidence and adjusts its production demand.
- Scores observed economic targets against nearby surface and anti-air threat, favoring exposed weaknesses.
- Switches air factories toward gunships after sustained land losses when observed anti-air is weak, or toward fighters when enemy air threat dominates.
- Requests transport harassment against exposed economy and continuously sends small reinforcement waves toward active objectives.
- Scores army pressure, T2, T3, experimentals, and nukes from live economy, battlefield, map, and observed-enemy evidence rather than match timers.
- Keeps attacking while dynamically weighting strategic investment; reachable fortifications favor experimentals, while unreachable high-value targets without observed missile defense favor nukes.
- Coordinates expansion claims and attacks with allied Red Queens.
- Proactively transfers surplus resources to allies in economic distress.
- Treats allied attack, move, and alert pings as weighted requests.
- Supports Assassination and Supremacy strategy goals.
- Retains FAF's adaptive builders as its low-level construction fallback while its own directors control objectives, counter-production priorities, and reinforcement pressure.

## Scaling rule

At match start each Red Queen computes:

```text
army deficit      = max(0, hostile armies - allied-side armies)
income multiplier = 1 + 0.10 * army deficit
```

The allied-side count includes the Red Queen itself. Civilian and neutral armies are excluded. The result is locked for the entire match and has no artificial cap. Only mass and energy production change; build rate, intel range, and combat statistics remain untouched.

Examples:

| Match | Multiplier |
| --- | ---: |
| 1v1 | 1.0x |
| 1v2 | 1.1x |
| 1v3 | 1.2x |
| 2v3 | 1.1x |

## Install for development

The game-facing directory name must be `TheRedQueen`, because FAF imports mod files by that path.

```bash
./scripts/install-dev.sh "/path/to/Supreme Commander Forged Alliance/mods"
```

Enable **The Red Queen** in the FAF lobby's mod manager, then select it from an AI slot. See [docs/testing.md](docs/testing.md) for the match matrix and log checks.

## Validate

```bash
./scripts/validate.sh
```

The validator checks the mod contract, compiles every Lua source with LuaJIT, and exercises the pure scaling formula.

## Status

This repository is the first playable implementation. The architecture and core behaviors are present; the stated 1000–1300 strength target still requires replay-driven tuning and human beta results rather than being assumed from code alone.
