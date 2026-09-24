# Experimental classification — 2026-09-07

## The problem

One experimental completed across sixteen recorded matches, and the code had no
notion of what an experimental was *for*. Two separate causes.

**The ceiling — which was one, not two.** `DesiredExperimentals` was tied to the
concurrency slots:

```lua
demand.DesiredExperimentals = weights.Experimental >= min
    and (weights.Experimental >= 75 and demand.MajorProjectSlots or 1)
    or 0
```

`MajorProjectSlots` reached 2 only when `weights.Army < StrategicSecondProjectArmyMaximum`,
which is 70. Measured across twenty recorded matches, army weight peaked at
**100 in nineteen of them** and 85 in the twentieth — it never once dropped below
70 at a moment when the experimental gate was open. So the second slot was
unreachable in practice, the expression collapsed to `1`, and the endgame could
own exactly one experimental no matter how rich it became.

That is the whole of "one experimental across sixteen matches": not a tuning
value set too low, but a ceiling keyed on a condition that never held. The
replacement keys the fleet target on income and leaves army weight out of it.

**The blindness.** Two builders existed, `Red Queen Land Experimental` and
`Red Queen Naval Experimental`, separated only by map type. Neither asked what
the template key would actually build, nor whether the unit could reach anything.

## FAF's template keys cannot be trusted

`BuildingTemplates` maps a key to a blueprint per faction. Verified against
`lua/BuildingTemplates.lua` (faction blocks: UEF 16-299, Aeon 300-586, Cybran
587-872, Seraphim 873-1141) and the 606 blueprints in `units.nx2`:

| Faction | Key | Resolves to | Experimental? |
| --- | --- | --- | --- |
| UEF | `T4LandExperimental1` | `uel0401` Fatboy | yes |
| UEF | `T4SeaExperimental1` | `ues0401` Atlantis | yes |
| UEF | `T4Artillery` | `ueb2401` Mavor | yes |
| UEF | `T4SatelliteExperimental` | `xeb2402` Novax | yes |
| UEF | `T4AirExperimental1` | `uel0401` Fatboy | yes, but **an amphibious land unit under an air key** |
| Aeon | `T4LandExperimental1` | `ual0401` Galactic Colossus | yes |
| Aeon | `T4AirExperimental1` | `uaa0310` CZAR | yes |
| Aeon | `T4SeaExperimental1` | `uas0401` Tempest | yes |
| Aeon | `T3RapidArtillery` | `xab2307` Salvation | yes — **an experimental under a Tech 3 key** |
| Aeon | `T4EconExperimental` | `xab1401` Paragon | yes |
| Aeon | `T4Artillery` | `uab2302` Heavy Artillery | **no — Tech 3** |
| Cybran | `T4LandExperimental1` | `url0402` Monkeylord | yes |
| Cybran | `T4LandExperimental2` | `url0401` Scathis | yes |
| Cybran | `T4LandExperimental3` | `xrl0403` Megalith | yes |
| Cybran | `T4AirExperimental1` | `ura0401` Soul Ripper | yes |
| Cybran | `T4SeaExperimental1` | `urb0101` Land Factory | **no — Tech 1, 240 mass** |
| Cybran | `T4Artillery` | `urb2302` Heavy Artillery | **no — Tech 3** |
| Seraphim | `T4LandExperimental1` | `xsl0401` Ythotha | yes |
| Seraphim | `T4AirExperimental1` | `xsa0402` Ahwassa | yes |
| Seraphim | `T4Artillery` | `xsb2401` Yolona Oss | yes (a nuke silo, not a gun) |
| Seraphim | `T4SeaExperimental1` | `xsb0101` Land Factory | **no — Tech 1, 240 mass** |

Neither Cybran nor Seraphim has a naval experimental in Forged Alliance, so those
two are placeholders rather than mistakes in intent. The consequence for us was
not benign.

### The live bug this was hiding

`Red Queen Naval Experimental` ran only when `MapType == "Naval"`, and on a naval
map it was the *only* experimental builder that could run. As Cybran or Seraphim
it built `T4SeaExperimental1` — a **240-mass Tech 1 land factory** — placed near
a Naval Area marker by a Tech 3 engineer, and counted against the endgame project
budget as though it were an experimental.

Also note `T4LandExperimental2` aliases the same unit as `T4LandExperimental1`
for UEF, Aeon and Seraphim. Registering both keys would let one unit be started
twice under two names.

## The classification

`lua/AI/RedQueen/Experimentals.lua` records, per faction, the template key, the
blueprint it is expected to resolve to, a role, and the navigation layer the unit
actually moves on. Roles are assigned from blueprint categories, not names:

| Role | Test | Needs |
| --- | --- | --- |
| `Assault` | moves, and can attack a ground target (`DIRECTFIRE`, `GROUNDATTACK` or `BOMBER`) | a route to the enemy **on its own layer** |
| `Siege` | `INDIRECTFIRE` artillery or a `NUKE` silo; static, or mobile but too slow to assault | range, not a route |
| `Support` | moves and fights but cannot engage ground | a force of its own layer to escort |
| `Economy` | no weapons (Paragon) | its own gate; not driven by the combat budget |
| `Intel` | orbital observation (Novax) | as above |

The layer is the half that has historically gone wrong. **Every assault
experimental in the game is `RULEUMT_Amphibious`, `RULEUMT_Air` or
`RULEUMT_SurfacingSub` — not one moves on the Land graph.** Gating a Galactic
Colossus on `CanPath("Land", ...)` asks about a graph it does not use, which is
the same defect that once left an entire hover army without orders.

Consequences worth naming:

- **UEF has no assault experimental.** Its land key is the Fatboy, mobile
  artillery, and its air key is that same unit. So UEF's endgame is siege and
  escort, and the catalog says so rather than leaving a gap that reads as an
  oversight.
- **Cybran is the only faction with three distinct land experimentals**, and the
  only one whose `T4LandExperimental2` is a different unit (Scathis) from
  `T4LandExperimental1`.
- **Aeon's experimental artillery is only reachable through `T3RapidArtillery`.**

### Keeping it honest

Both halves of every catalog entry — that a key resolves to a given blueprint,
and that the blueprint is an experimental — are facts about the game, so a FAF
update can falsify them silently. `scripts/check-experimental-catalog.py`
compares the catalog against extracted game files, including checking that each
recorded rejection is *still* a rejection:

```bash
scripts/check-experimental-catalog.py \
    --templates /path/to/lua/BuildingTemplates.lua \
    --units /path/to/extracted/units
```

It needs those game files, so it is not part of `validate.sh`; run it when
touching the catalog or after a FAF update. `scripts/validate_mod.py` covers what
can be checked without them: that no builder bypasses the catalog, that a
builder's gate and its `BuildStructures` name the same key, and that no rejected
blueprint has crept in as a catalog entry.

## Production

One builder per distinct template key, each with a static `BuildStructures` —
the global `Builders` table is shared across every army in one Lua state and must
never be mutated at runtime — and all of the faction, role and path decision in
a single parameterised condition, `ShouldBuildClassifiedExperimental(aiBrain,
template)`. Because the gate takes the same key the builder builds, the two
cannot disagree; a structural guard asserts that pairing.

A key absent from the catalog makes the builder inert, which is what retires the
Tech 1 land factory bug: no map-type test can tell a factory from an
experimental, but a catalog lookup can.

Assault builders sit above siege (930-927 against 926-924): a game-ender that
never arrives is worth less than a walker that does, and the siege pieces cost up
to 224775 mass.

Volume now scales with income instead of stopping at two. The target is anchored
on the affordability gate — one experimental at mass income 22, gaining one per
further 12 income, capped at 8 — and concurrency scales with it to a maximum of
3, because a target of six reached one at a time is a queue rather than a force.
The nuclear target deliberately keeps the readiness-derived allowance it was
measured with, so raising experimental concurrency does not silently raise it.

## Dispatch

Building them is half the requirement; they also have to be sent. Experimentals
were already gathered into the layer groups (`MOBILE`, not engineer/commander/
scout/transport) and already sort to the front of a wave, because
`SelectTaskForce` orders by blueprint threat.

What stopped them was the count minimum: `MinimumAttackUnits = 3`, so a lone
experimental was held as `insufficient-units`. That minimum exists to stop small
units being fed piecemeal into a formed army — it is not a judgement that applies
to a single unit with 27500 mass and 99999 hitpoints. An experimental now
satisfies the minimum on its own, while the commitment threat gate still decides
whether the wave can win, so a lone Monkeylord will take a weak position and
still be held back from a defended one.

## Attribution: why `JsonStats` alone cannot measure this

The first verification runs were unreadable, and the reason is worth recording.

A Cybran match reported one Monkeylord built and `slots=5`, while Red Queen's own
experimental weight never reached its threshold of 35. Those five major projects
came from FAF's native builders — `MajorProjectSlots` is raised to
`ExperimentalsUnderConstruction + NukesUnderConstruction` to account for work
already in flight, whoever started it. The engine's end-of-match per-blueprint
counts record what the *army* built, not what Red Queen's builders chose, so
"one experimental built" was not evidence about this code in either direction.

The state line therefore carries `exp=<role>:<blueprint>/<owned>/<target>`,
computed from the classification each diagnostics cycle. It answers what Red
Queen itself would field, whether the layer check admits it, how many are owned
and what the fleet target is. Its contract drives `Diagnostics:Update` because
`string.format` raises when the argument count does not match the format, so a
field added without its argument breaks every match and no syntax check sees it.

### First measurements

| Run | Peak mass | `exp=` reached | Fielded | Result |
| --- | --- | --- | --- | --- |
| Fields of Isis, 8675309, Cybran | 57.8 | `Assault:url0402/1/4` | Monkeylord x1 | victory 1.33 |
| Fields of Isis, 8675309, Aeon | 29.5 | `Assault:ual0401/0/1` | none | defeat 0.52 |

Both resolve the right unit for their faction, and both are `RULEUMT_Amphibious`
— `CanAct` returning them proves the amphibious route check succeeds on this map,
which is the layer gating working in game rather than only in contract.

Two things follow. **The fleet target does scale**: Cybran reached 4, where the
old expression was permanently 1. **But the ramp is too coarse at mid income**:
Aeon peaked at 29.5 mass, which yields `1 + floor((29.5 - 22) / 12) = 1` — no
improvement over the old ceiling. `ExperimentalMassIncomePerUnit = 12` only
starts to bite above about 34, and the observed band on these maps is 29 to 58.

Also note Aeon lost this seed where the pre-change payload won it (1.03 against
0.52), reproduced identically across two payloads that differ only in
diagnostics — which confirms the instrumentation is behaviour-neutral, and
leaves the regression itself unexplained. One seed cannot separate a systematic
worsening from divergence: registering five more builders in the shared table
reorders builder evaluation, so the match diverges early whatever the merit of
the change.

## A/B: the volume increase was the regression

Aeon lost ground on every comparison after the first version of this work, so
volume was isolated by holding the classification and path gating fixed and
reverting only the stock target to one.

| Aeon, seed 8675309 | Before this work | Stock 8 / concurrency 3 | Volume reverted to 1 |
| --- | --- | --- | --- |
| Syrtis Major | victory 1.12 | victory 0.75 | victory **1.34** |
| Fields of Isis | victory 1.03 | defeat 0.52 | defeat 0.52 |

**Syrtis Major settles it.** Reverting volume restored the result and beat the
original baseline — 1.34 against 1.12 — while still fielding a CZAR. So the
classification is not the problem; starting three projects of 20000 to 48000
mass at once, at the moment the AI is under pressure, is.

**Fields of Isis is a different failure.** It reads 0.52 in *both* arms, and it
built no experimental in either: its peak mass of 29.5 left the target at 1 and
nothing was completed. Since the endgame path barely ran there, the loss cannot
be the volume, and the remaining difference is that the endgame group went from
two builders to nine. Which builder an idle engineer picks changes the whole
match from early on, so a 1.03 becoming 0.52 is within what builder-list
reordering can do. That is sensitivity, not a defect with a line number, and it
is the reason a single seed can never settle a change of this shape.

## Volume is a flow, not a stock

The stock model was the wrong shape twice over, and the intent is simpler than
either version: **one or two experimentals always in production** once the
economy carries them, with the game-enders and utility experimentals in the mix
alongside the on-grid force.

A stock target both over-commits and under-commits. It starts everything at once
while the count is low, and then stops production dead once the count is met —
neither is "constant production". So concurrency is now the only brake, and the
owned count is *added into* the target instead of capping it:

```lua
demand.DesiredExperimentals = (forces.Experimentals or 0) + concurrent
```

`concurrent` is 1, rising to `ExperimentalConcurrentMaximum` (2) at
`ExperimentalSecondProjectMassIncome` (40) — the point where two at once is
affordable rather than merely desirable.

### Making "alongside" real

A second slot alone would just start a second assault walker, so each role has
its own in-flight allowance of one (`Experimentals.RoleAllowance`). The second
slot therefore goes to something *different* from the first: a game-ender, an
escort, or a utility piece. In-flight work is classified by blueprint through
`RoleForBlueprint`, because the engine reports progress by blueprint rather than
by the template key it was requested under.

Utility experimentals are now built rather than merely classified. Both are
gated on `ExperimentalUtilityMassIncome` (45) — well past the combat gate of 22 —
because a Paragon is 250200 mass and only defensible when income would otherwise
idle, and a Novax at 32000 answers an intel problem rather than a force one. Role
ranking is Assault 0, Support 6, Siege 12, Economy 18, Intel 24, expressed as
priority penalties so the ordering survives the 1000 cap.

## Known inconsistency: catalog order is not honoured by production

The Syrtis Major run reported `exp=Assault:ual0401` — the Galactic Colossus —
and fielded a **CZAR** instead.

Both are Aeon assault entries, so `ExperimentalRolePenalty` gives them the same
priority, and FAF then picks whichever equal-priority builder its sorted builder
list reaches first. `SelectForRole` walks the catalog in declaration order and so
reports the Colossus; the production side has no such preference. The comment in
`Experimentals.lua` claiming "order within a faction is the selection order" is
therefore true of the read API and false of production.

Two ways to close it, and the second is better: report every reachable option
rather than the first, or give each entry a small priority offset by its index so
the declared order actually decides. The second makes the catalog's ordering
mean something, which is what the module already claims.

Until then, treat the `exp=` field as "what the classification admits", not "what
will be built".

## Not done

- **Economy and intel experimentals are classified but not built.** The Paragon
  and the Novax need their own gates; driving them from a combat budget would be
  wrong.
- **`HasReachableTarget` still tests only Land or Water.**
  `IntelManager.lua` picks `observation.Layer == "Water" and "Water" or "Land"`,
  so a target reachable only amphibiously counts as unreachable when the
  experimental weight is computed. The per-candidate gate in the builder is
  correct; this input to the weight is not yet.
- **No support-role escort logic beyond a fleet count.** An Atlantis is gated on
  owning at least four mobile naval units, which is a proxy for "there is a fleet
  here", not for "the fleet is going somewhere it needs cover".

## Why experimentals still were not being built (measured 2026-09-08)

A full 21-cell matrix on the corrected payload built **2 experimentals across
21 complete matches** (baseline: 9, of which 6 came from one unstable cell). The
classification, the path gating and the concurrency slots were all working — the
army simply never asked for one.

The cause is in `UpdateStrategicFocus`. The experimental weight is

    experimental = 10 + readiness * 30      -- max 40, threshold 35

so it clears the commitment threshold only at `readiness >= 0.83`. And
`GetEconomicReadiness` measures **headroom** — income minus what is already
requested — plus storage and trend. An army that spends what it earns therefore
reads as unready however rich it is.

Measured across 809 state samples from that matrix:

| readiness | value |
| --- | --- |
| median | **0.22** |
| p90 | 0.52 |
| max | 0.85 |
| share at or above 0.83 | **7%** |

And per cell, how often the weight crossed 35 against how many experimentals
were built:

| cell | samples | crossings | built |
| --- | --- | --- | --- |
| `isis-aeon-s3` | 47 | 13 | 1 |
| `crossfire-aeon-s1` | 98 | 5 | 0 |
| `setons-cybran-3v3` | 43 | 1 | 0 |
| `syrtis-aeon-s2` | 45 | 1 | 0 |

The one cell that crossed repeatedly is the one cell that finished a project. A
27,500-mass unit cannot be built inside a handful of momentary crossings.

**Fix.** `GetEconomicWealth` — income above the endgame gate, 0 at the gate and
1 at `EndgameWealthMultiple` times it — now adds up to 30 to both the
experimental and the nuclear weight. So a rich army commits whether or not its
income is idle, which is what "scale with economy, no time-bound triggers" has
to mean in practice: readiness alone says *commit when you have spare capacity*,
and an army at war never has spare capacity.

One definition serves both the weights and the defence-alert relief, and it is
keyed on income and never on elapsed time.

Note what this does *not* claim. The win/loss swing on that matrix (12W/9L to
9W/12L) is not significant — a sign test on the 7 flips gives p = 0.45, and
establishment was flat at 28% against 25%. The endgame figure is the one signal
that was directional, and it is the one this change addresses.
