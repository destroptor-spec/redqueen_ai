# Naval weakness investigation — 2026-09-06

## Outcome

Red Queen lost a strict 1v1 to the stock Adaptive AI on `SCMP_037` (Sludge,
5 km, 93% water, 3 mass clusters) at 13:12 game time, with a mass kill/loss of
**0.49 against 1.49**. On the four land maps in the same series it won twice and
drew once.

The loss is not a naval combat-quality problem. Red Queen's warships were the
most effective units on the field:

| | built | lost | kills |
| --- | --- | --- | --- |
| Red Queen naval | 6 | **2** | **12** |
| Adaptive naval | 10 | 12 | 2 |

Nor is it a production-mix problem. The factory capacity policy allocated
correctly for a naval map, reaching `L1/1 A2/2 N3/4` — naval dominant, land
minimal.

What failed is **direction**. Across the whole match Red Queen issued exactly
two strategy objectives: `Pressure layer=Air` and `Defend layer=Land`. On a map
that is 93% water it never once issued a Water-layer objective, so its own
combat manager never dispatched a naval wave. The twelve kills came from FAF's
native platoon machinery operating independently. Meanwhile 60 land units were
built and 58 were lost for 28 kills, on a map where land forces cannot reach the
enemy.

Supporting counts for the same match, re-read from `/tmp/rq-sludge.log` with
`scripts/analyze-log.py`: **1 defence alert**, **2 commitment holds**, **0
forward bases started against 13 blocked**, naval tier reaching only N2.

> **Correction (2026-09-06).** An earlier revision of this document reported
> 0 alerts, 0 commitment holds and 14 blocked. Those figures came from
> `/tmp/rq-sludge2.log`, a 519-line aborted run, not from the 4797-line match
> that was actually lost. The single alert that did fire is more damning than
> silence would have been:
>
> ```
> defense alert started anchor=NavalBase layer=Land threat=40.2 friendly=29.4 ratio=1.37
> ```
>
> It fired on a **NavalBase** and selected **`layer=Land`** — defect 5 in
> action, sending land defenders against ships. And not one of the 13
> forward-base blocks names terrain: they are `objective-defend` (5),
> `negative-mass-trend` (3), `no-idle-engineer` (2), `low-mass-income` (2),
> `stall-risk` (1), `low-mass-storage` (1). Defect 4 is real in code but was
> never the binding constraint in this match.

## Verified defects

### 1. The local-threat defence hard-codes the land layer

`StrategyDirector.lua:1146`

```lua
elseif localThreat >= Constants.Policy.LocalDefenseThreat then
    objective = {
        Type = "Defend",
        Position = start,
        Layer = "Land",
```

Every defence that comes from local threat rather than from a defence alert is
a Land objective regardless of terrain. On a water map the only units that can
reach the threat are naval, and they are never ordered. This is the observed
`Defend layer=Land` on a 93% water map.

The alert-driven path immediately above it does this correctly — it carries
`DefenseLayers` and per-layer positions — so the fallback is the outlier, not
the design.

### 2. A water objective can never form

`StrategyDirector.lua:1193` selects `preferredLayer = "Water"` on a naval map,
which is right. Both routes out of that choice then fail:

```lua
local known = self.Intel:GetBestKnownTarget(start, preferredLayer)
if known and not self.World:CanPath(preferredLayer, start, known.Position) then
    known = nil
end
...
local position = self.World:GetClosestEnemyStart(start, preferredLayer)
```

`GetClosestEnemyStart` tests `CanPath("Water", origin, enemy.Position)`, and an
enemy start position is where a commander spawns — dry land. Water pathing to a
land coordinate fails by definition, so the test can never succeed. The same
applies to any known target that is a land structure.

The fallback then rewrites `preferredLayer = "Air"`, which is the observed
`Pressure layer=Air`.

This is not map-specific bad luck. It is unconditional: **no naval offensive
objective can be produced by this code path on any map.**

### 3. An air objective silences every surface force

`CombatManager.lua`, dispatch:

```lua
elseif destinationLayer == "Water" then   -- naval + amphibious
elseif destinationLayer ~= "Air" then     -- land + amphibious
```

When the objective layer is `Air`, neither branch runs. Only the air wave at the
top of the function is dispatched. Land, naval and amphibious units receive no
orders at all.

Defect 2 makes `Air` the standing fallback on naval maps, and defect 3 then
converts that fallback into total surface paralysis. Together they explain the
0 commitment holds: `SelectTaskForce` was never called for a surface layer, so
the tactical gate had nothing to gate.

### 4. Forward bases are impossible on water maps

`WorldModel.lua:225`, inside `SelectForwardBaseSite`:

```lua
and self:CanPath("Land", origin, candidate.Position)
```

Site selection requires a land route from the engineer to the candidate marker.
On a 93% water map the mass clusters sit on separate islands and no land route
exists, so no site is ever selectable. `GetObservedRouteThreat` at line 197 has
the same land-only assumption. Result: 14 blocked attempts, 0 started, with no
diagnostic naming terrain as the cause.

### 5. Aggregate threat is bucketed by weapon type, not movement layer

`IntelManager.lua:48`

```lua
Land = (defense.SurfaceThreatLevel or 0) + (defense.SubThreatLevel or 0),
Naval = defense.SubThreatLevel or 0,
```

A destroyer's main guns are `SurfaceThreatLevel`, so they are counted as *land*
threat, and `Naval` holds only the anti-submarine component. A surface fleet
with no torpedoes registers zero naval threat.

Scope of the damage is narrower than it first appears, and the V7 layer-bucketing
fix is intact where it matters most: `GetObservedArmyClusters` re-buckets by
`observation.Layer`, so defence-alert layer selection is correct. The defect
affects the aggregate `self.Threat` table only — which feeds doctrine selection
and `UpdateDemand`. It is real but lower severity than 1 through 4.

### Defect 6 — hover units are routed on the wrong navigation graph

This was missed entirely by the first pass, and on the tested faction it is the
largest single effect.

Red Queen played **Aeon** (`started version=V8 faction=2`). Enumerating all 606
blueprints in `units.nx2`, on Aeon the T1 tank (Aurora `UAL0201`), T1 AA, T1
scout, T2 Blaze, T2 mobile shield and **all three engineer tiers** are `HOVER`.
Cybran has **zero** hover units; UEF has one.

`CombatManager.lua` mapped `AMPHIBIOUS or HOVER` to a single `"Amphibious"`
group, and `IssueObjective` path-gates that group with
`CanPath("Amphibious", ...)`. The two grids are not the same
(`lua/sim/NavGenerator.lua`):

```lua
-- Hover:       nonBlockingTerrainType and (depth >= 1 or nonBlockingTerrainAngle)
-- Amphibious:  depth <= 25 and nonBlockingTerrainType and nonBlockingTerrainAngle
```

Hover treats deep water as explicitly pathable; amphibious blocks it past
`MaxWaterDepthAmphibious = 25`. On 93% deep water the amphibious grid fragments
into islands, so Aeon's entire early army and every engineer were gated on a
graph none of them use and received no orders. That is the real explanation for
**60 land units built and 58 lost** — better than "land forces cannot reach the
enemy", because hover units could have.

The fix is faction-safe: the engine aliases the hover grid to the land grid on
maps without water, so it is a no-op on land maps and on Cybran.

### Not established

The single defence alert fired late and on the wrong layer, despite up to 118
live observations. The anchor
enumeration is correct — a manager whose position is on water is classified
`NavalBase`. Whether no cluster ever reached `MassiveArmyThreat = 40` at the
required ratio in a 13-minute match, or whether something suppressed the alert,
is **not determined**. It should be measured before it is fixed.

## Plan

Ordered by blast radius. The first three are one coherent change: naval forces
must be given a destination they can reach.

### 1. Give water objectives a reachable destination

An enemy base is a land coordinate; a fleet's objective must be the water near
it, not the base itself. Select naval destinations from water-reachable
positions instead of testing land coordinates:

- Prefer `Naval Area` markers near the enemy start, which FAF's own naval
  builders already use, filtered by `CanPath("Water", start, marker)`. These are
  **already generated** before our first `Rebuild` —
  `AdaptiveBrain.OnBeginSession` calls `GenerateNavalAreaMarkers()` — so they
  only need reading, not generating.
- Failing that, project the enemy start onto the nearest water position that is
  water-reachable from our own naval base, and use that.
- Keep `GetClosestEnemyStart` land-only, and stop asking it water questions.

Acceptance: a contract proves that on a water map with a land enemy start, a
Water-layer objective is produced with a water-reachable position, and that the
Air fallback is taken only when no water route exists at all.

### 2. Never leave a surface layer without orders

Change the dispatch so layer selection is additive rather than exclusive. An
air objective should still send surface forces to the best surface destination
they can reach; if none exists, they should be explicitly staged rather than
silently idle.

Acceptance: a contract proves that an `Air` objective still issues orders to
available naval and land groups, and that a group with no reachable destination
is reported rather than dropped.

### 3. Derive the defence layer from terrain and threat

Replace the hard-coded `Layer = "Land"` in the local-threat fallback with the
same treatment the alert path already uses: compute `DefenseLayers` and per-layer
positions from the anchor's terrain and the observed threat composition.

Acceptance: a contract proves a local-threat defence on a water anchor produces
a Water layer, and that a mixed anchor produces both.

### 4. Make forward-base siting layer-aware

Site selection and route threat must path in the domain the engineer actually
moves through. On a water map that means amphibious or naval-reachable sites, or
transport-delivered ones. Where a map genuinely offers no reachable site, report
that once as a terrain blocker rather than retrying every cycle — 14 identical
blocked attempts with no cause named is a diagnostic failure in itself.

Acceptance: a contract proves site selection uses a layer matching the engineer,
and that an unreachable-terrain outcome is reported distinctly from an economy
or engineer blocker.

### 5. Bucket aggregate threat by movement layer

Apply the same rule `GetObservedArmyClusters` already uses: classify a unit's
threat by where it moves, not by which weapon it carries. Keep `SubThreatLevel`
meaningful for anti-submarine decisions by tracking it separately rather than
overloading `Naval`.

Acceptance: a contract proves a surface warship with no torpedoes contributes
naval threat, not land threat.

## Verification

The behavioural test is a repeat 1v1 on Sludge plus a second naval map, judged
on whether Water-layer objectives appear at all, whether commitment holds become
non-zero, and whether the mass kill/loss moves off 0.49. `./scripts/validate.sh`
covers the contracts. Note that defect 2 is unconditional, so its fix is also
worth re-checking on a mixed map such as Crossfire Canal, where naval objectives
should now become available alongside land ones.
