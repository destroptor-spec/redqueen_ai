# What the Adaptive AI does that Red Queen does not

Read from `lua.nx2` on 2026-09-25, prompted by the observation that Adaptive
spreads small platoons across the map and denies Red Queen's engineers access to
mass.

## Adaptive has a map-ownership model, and it is built from mass

`lua/AI/GridPresence.lua` maintains a grid over the map. Every pass it walks
**every Mass marker** and counts structures within radius 6:

```lua
local countHostile = TableGetn(GetUnitsAroundPoint(brain, cSTRUCTURE, position, 6, 'Enemy'))
local countAllied  = TableGetn(GetUnitsAroundPoint(brain, cSTRUCTURE, position, 6, 'Ally'))
```

Per cell, per pathing label, it then sets a status quo — `Allied` if allied
structures outnumber hostile, `Hostile` if the reverse, `Contested` if equal and
non-zero, `Unoccupied` if none — and **flood-fills** those known cells outward
until every reachable cell carries an inferred status.

Presence, for Adaptive, *is* extractor ownership propagated across the map.

## It hunts the deposits it does not own

`lua/AI/AIBuilders/AILandAttackBuilders.lua` carries builders named, literally:

| builder | priority | marker |
| --- | ---: | --- |
| **Mass Hunter Early Game** | 950 | `Mass` |
| **Mass Hunter Mid Game** | 950 | `Mass` |
| Start Location Attack | 1000 | `Start Location` |

They form `AIPlatoonAdaptiveRaidBehavior`, whose `Searching` state takes every
`Expansion Area` marker and keeps only those where

```lua
aiBrain.GridPresence:GetInferredStatus(expansion.position) ~= 'Allied'
```

falling back to `Mass` markers when no expansion qualifies. So each platoon
independently picks a deposit the AI does not already hold, and goes there.

The platoon is small by design — `StateMachinePlatoon` is
`{ DIRECTFIRE * LAND * MOBILE, 2, 15 }` plus `{ SCOUT, 1, 2 }`, so it forms with
**two units and a scout**.

Many small platoons, each aimed at a different unowned deposit, is exactly the
behaviour observed: the map gets covered and engineers cannot reach mass.

## What Red Queen does instead

Red Queen's offensive objective is **one army-wide aim point**:

```lua
candidate = self.World:GetClosestEnemyStart(start, layer)
...
return { Type = "Raid", Position = known.Position, ... }
```

A `Raid` targets a known enemy unit from intel; failing that, `Pressure` targets
the **enemy start**. Neither targets a mass deposit. Red Queen concentrates
force at the enemy, where the layered defence is, while Adaptive distributes
force across the economy.

This is consistent with everything measured this session:

- claim peaks at **45% of the map at minute 10** and never recovers — Red Queen
  has no objective that says "take that deposit";
- **69% of deposits lie outside every base radius**, so nothing defends them;
- the land exchange is poor because the army walks into defended ground;
- Red Queen is **mass-limited, not build-power-limited** — and the mass it is
  missing is on ground Adaptive is sitting on.

## The fair version of the same idea

Adaptive's `GetUnitsAroundPoint(..., 'Enemy')` enumerates enemy structures
regardless of what it has scouted. Red Queen's own rule forbids that: *"no
decision may read it, or Red Queen is playing with knowledge it has not
earned."*

The model can be built honestly from what Red Queen already has:

- **its own extractors** — known without question;
- **observed enemy structures** from `IntelManager`, which samples only what Red
  Queen's own units can see;
- everything else as **unknown**, which is a contestable state rather than a
  safe one.

That yields the same partition — mine / theirs / unknown — without seeing
through fog, and unknown deposits are precisely what a scout should be sent to
resolve.

## What would follow

1. A deposit-ownership map, reported in the state line, so the claim curve can
   be read against what is actually contested rather than merely unclaimed.
2. An objective type that aims at a **deposit** rather than at the enemy start,
   so combat power is spent where the economy is.
3. Escort: hold a deposit long enough for an engineer to arrive and build. The
   measured engineer story says the route guard is not what stops them and the
   engine's placement filter refuses nothing, so what is missing is that nobody
   clears or holds the ground.

None of this is built. It is a larger change than anything attempted this
session, and it should start with the measurement — the ownership map — before
any objective is rewired.
