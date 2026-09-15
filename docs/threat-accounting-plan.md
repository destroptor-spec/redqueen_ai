# Per-arm threat accounting

## Aim

Judge each arm of an attack against the defence that can actually answer it.
Today the numerator of every defence decision is split by arm — clusters carry
`Land`, `Naval` and `Air` separately — while the denominator is a single
undifferentiated sum. Every symptom below follows from that one mismatch.

This closes finding 8 in `docs/code-review-findings.md` and the residual left
deliberately at the `defenseLayer` call site in `StrategyDirector.lua` when
finding 5 was fixed.

## The two symptoms are one defect

Finding 5 was fixed by taking the water view only when the fleet is the main
body, and by matching the numerator to it. That removed the false alert, but it
did not make the comparison correct — it narrowed the cases where the
comparison is wrong. Two known gaps remain, and they are the same gap seen from
either side:

- When a fleet really is the main body, the air escorting it is excluded from
  the comparison entirely.
- `NavalDefenseThreat` credits an aircraft with `SubThreatLevel` alone, so the
  only aircraft that counts against ships is a torpedo bomber.

Neither can be fixed on its own. Including air in the naval comparison requires
a denominator that knows what our air can do to ships; fixing that denominator
without splitting the judgement just moves the error.

## What the engine actually says

Extracted from `~/.faforever/gamedata/units.nx2`. `caps` is
`FireTargetLayerCapsTable` for the unit's own layer.

| Unit | Surface | Sub | Air | caps (own layer) |
| --- | --- | --- | --- | --- |
| `UEA0103` T1 bomber | 2 | – | – | `Land\|Water\|Seabed` |
| `UEA0203` T2 gunship | 5 | – | – | `Air\|Land\|Water\|Seabed` |
| `UEA0204` torpedo bomber | – | 8 | – | `Seabed\|Sub\|Water` |
| `UEA0303` ASF | – | – | 50 | `Air\|Land\|Water` |
| `UEB2101` T1 point defence | 17 | – | – | `Land\|Water\|Seabed` |
| `UEB2104` T2 AA tower | – | – | 7 | `Air` |
| `UEL0201` T1 tank | 2 | – | – | `Land\|Water\|Seabed` |
| `UES0201` destroyer | 23 | 3 | 1 | `Land\|Water\|Seabed`, `Air`, `Seabed\|Sub\|Water` |

Three things follow directly:

- A gunship carries `SurfaceThreatLevel = 5` and its caps include `Water`, so it
  can attack ships — and `NavalDefenseThreat` scores it **0**, because it reads
  `SubThreatLevel` for anything with the `AIR` category. Same for the T1 bomber.
  Only `UEA0204`, whose damage is in `SubThreatLevel`, is ever counted.
- An AA tower's caps are `Air` and nothing else, and an ASF has no
  `SurfaceThreatLevel` at all. Neither can touch a tank or a ship. Both are
  nonetheless summed into the denominator on every non-water layer, because
  `BlueprintThreat` returns `Surface + Sub + Air` indiscriminately.
- Point defence carries `Water` in its caps, which is why the existing
  land-branch reachability test in `NavalDefenseThreat` is right and should be
  kept.

So the water path under-counts and the land path over-counts. Finding 5's
symptom surfaced on the water path only because the sum there collapses to
roughly zero, which is loud; on the land path the same error is quiet, and
suppresses alerts instead of inventing them.

## Target design

`GetOwnThreatNear` gains an arm-aware sibling rather than changing shape — see
the blast radius below. Proposed:

```
GetOwnThreatByArm(position, radius, target) -> { Surface = s, Air = a }
    Air     += AirThreatLevel
    Surface += SurfaceThreatLevel + SubThreatLevel, when the unit can engage
               a contact at `target`
```

The engine has already typed these figures by arm; the work is to stop summing
across them. The reachability test for `Surface` is the one
`NavalDefenseThreat` already performs — weapon caps for the unit's own layer
must include the contact's layer, and the contact must be in range. `Air` needs
no positional test: anti-air is answered where it stands.

`NavalDefenseThreat`'s aircraft branch becomes the same caps test the land
branch already uses, which is what makes a gunship count against ships and
keeps an ASF from doing so.

The alert judgement then runs three tests instead of one, and qualifies if any
of them does:

| Test | Contact | Defence |
| --- | --- | --- |
| surface arm | `Land + Naval` | `own.Surface` |
| air arm | `Air` | `own.Air` |
| combined arms | `Threat` | `own.Surface + own.Air` |

Each keeps its existing magnitude threshold and ratio floor.

## Why the combined test is not optional

Per-arm gating alone silently weakens combined-arms detection, and a naive
total-magnitude gate silently restores the bug finding 5 just fixed. Worked
against the current constants (`MassiveArmyThreat = 40`,
`MassiveArmyThreatRatio = 1.25`):

| Scenario | own | surface arm | air arm | combined | verdict |
| --- | --- | --- | --- | --- | --- |
| `Naval 6, Air 300` vs ASFs+AA | S 0, A 400 | 6 < 40 | 300/400 = 0.75 | 306/400 = 0.77 | no alert — correct, this is finding 5 |
| `Naval 200, Air 10` vs no ships | S 0, A 400 | 200/1 ≫ 1.25 | 10 < 40 | — | alert — correct |
| `Land 30, Air 30` vs thin cover | S 20, A 20 | 30 < 40 | 30 < 40 | 60/40 = 1.5 | alert — **only** the combined test catches this |
| `Air 300` vs no AA | S 200, A 0 | 0 | 300/1 ≫ 1.25 | 300/200 = 1.5 | alert — correct, and for the right reason |

The third row is the regression a per-arm-only design would introduce. The
first row is the one a total-magnitude design would reintroduce. Three tests
covers both.

## Blast radius

`GetOwnThreatNear` is **not** private to the alert. Production callers, all
passing two arguments and expecting a scalar:

- `StrategyDirector.lua:126` — committed threat
- `ProductionManager.lua:2115`, `:2293`, `:2631` — forward-base and engineer
  route escort strength
- `EngineerSurvival.lua:190` — route verdict escort
- `DefenseFixture.lua:56` — fixture reporting

Changing its return type would break all six. Keep the scalar exactly as it is
and add the arm-aware function beside it; migrating the escort callers is a
separate decision, since "is there enough of our army near this route" is a
different question from "can we answer this attack".

Downstream of the ratio:

- `Severity = math.max(1, ratio) * criticality` — with three tests, severity
  should take the ratio of whichever test qualified, highest first.
- `Severity` feeds the endgame tax at `StrategyDirector.lua:1199`
  (`DefenseAlertEndgameTaxPerSeverity`). A changed severity distribution changes
  endgame investment, which is a balance effect and needs a matrix, not a spec.

## Sequencing

Each step is separately observable, which is what makes the result attributable
if it is measured.

1. **Fix `NavalDefenseThreat`'s aircraft branch.** *(done, 2026-09-15)*
   Replaced the `SubThreatLevel` shortcut with a caps test. The caps lookup is
   keyed on the layer the unit *fires* from — `"Air"` for aircraft, since
   `PositionLayer` only ever returns `Land` or `Water` and would have read the
   wrong key — and the range check is applied only to units that shoot from
   where they stand, not to aircraft that fly to the fight. A gunship now counts
   its 5, a bomber its 2, a torpedo bomber its 8 as before; an interceptor still
   counts 0, because it carries no surface or sub damage even though its caps
   list Water, so no category exception was needed. Covered by
   `tests/strategy_director_spec.lua`, confirmed load-bearing by restoring the
   old shortcut.
2. **Add `GetOwnThreatByArm`.** *(done, 2026-09-15)* Returns
   `{ Surface, Air }` for the same defenders `GetOwnThreatNear` reads, which is
   now one shared `DefendersNear` definition so the scalar and per-arm readings
   cannot drift. Surface damage is gated on the contact's **own** layer, via a
   generalised `CanStrike(blueprint, firingLayer, targetLayer, ...)`;
   `NavalDefenseThreat` is now a thin wrapper over `SurfaceDefenseThreat(unit,
   target, "Water")`, so every existing caller behaves exactly as before. Air
   carries no reach test. Still has no production caller — step 3 consumes it.
   Covered by `tests/strategy_director_spec.lua` and mutation-tested: hardcoding
   the contact layer to `Water`, or dropping the reach test, both fail the spec.
3. **Switch the alert to the three tests.** *(done, 2026-09-15)* The
   `defenseLayer` dominance rule and the `facing` numerator introduced by
   finding 5 are both gone: `GetOwnThreatByArm` takes the contact's own layer
   from `cluster.Position`, so the heuristic that picked a view is no longer
   needed. `massive`, `pressure` and `commanderEmergency` each ask `Qualifying`
   for the strongest arm clearing both its magnitude floor and that gate's ratio
   floor. `Severity` follows the arm that actually qualified, never a louder one
   that did not — a token air force over an anchor with no anti-air produces an
   enormous ratio and must not set the severity of a land attack. The alert now
   carries `QualifiedArm`, `FriendlySurface` and `FriendlyAir`; the trace line
   carries `arm=`, `surface=` and `antiair=`.

   The residual left at the finding 5 call site is closed: a fleet's escorting
   air is now judged on the air row rather than being dropped.

   Mutation-tested — removing the combined row loses the combined-arms case, and
   removing the per-arm magnitude floor lets the six-mass frigate alert again.
   Several existing alert specs stubbed the scalar `GetOwnThreatNear`, which the
   alert no longer consults; they were converted to stub `GetOwnThreatByArm`
   with equivalent intent rather than deleted.
4. **Report it.** `defenseLayer=` and `facing=` already reach the trace. Add the
   per-arm figures and which test qualified, and put the qualifying test in the
   periodic state line's `alert=` field — a figure a matrix has to read cannot
   live at `Logger.Debug`.

Steps 1 and 2 are safe to land together. Step 3 should land alone.

Steps 1 to 3 are complete as of 2026-09-15 and none has been measured in a
match. Step 4 is what makes that measurement possible: the per-arm figures
reach the trace, which is Debug and therefore absent from a behavioural run,
and `QualifiedArm` does not reach the periodic state line at all.

## Tests

Pure specs, in the style already used for findings 4 to 6:

- A gunship and a T1 bomber count against ships; an ASF does not; a torpedo
  bomber still does. Assert against the real blueprint shapes above, not
  invented ones.
- An AA tower and an ASF contribute to `Air` and not to `Surface`; point
  defence and a tank contribute to `Surface` and not to `Air`; a destroyer
  contributes to both.
- Each of the four scenarios in the table above, asserting the alert verdict
  **and** which test qualified.
- Every existing alert contract must still pass unchanged, or the change is
  wider than intended.

Runtime: a match on a naval or mixed map should show alerts naming the arm that
qualified, and should not show a massive alert against an air raid over a
defended base. `SCMP_037` (Sludge) and `SCMP_009` (Seton's Clutch) are the
venues where air and naval actually mix.

## Open questions

- **Threshold calibration.** The three tests reuse constants tuned against an
  undifferentiated denominator. Splitting the denominator will raise ratios on
  both arms, so the same thresholds will alert more readily. Whether they need
  raising is a matrix question; do not pre-tune them by guess.
- **Should the escort callers migrate?** A route escort probably wants surface
  strength when the route threat is surface. Deferred deliberately.
- **`EconomyThreatLevel` is excluded throughout** (a destroyer carries 46 of
  it). That is correct for a combat comparison and is noted only so the next
  reader does not "fix" it.

## Not covered

Finding 7 — the water-layer `CanPath` call at `StrategyDirector.lua:1647` that
asks for a route out of dry land — is adjacent but independent, and is not
addressed here. Finding 6's fix already routes around it by using
`GetNavalApproach`, which resolves both ends onto water.
