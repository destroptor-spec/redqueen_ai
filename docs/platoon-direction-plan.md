# Directing native platoons

Working document. Nothing below is measured unless it says so.

## Why

Red Queen's strategy layer does not reach its army. Measured across twelve
cells: its own dispatch orders units on **two or three passes in an entire
match**, and one naval cell wins having dispatched nothing at all. The fighting
is done by FAF's platoon AI, which runs continuous loops — `HuntAI` re-targets
every seventeen seconds, `AttackForceAI` re-picks its enemy as the game moves.

So the objective system — slots, weights, allocation, the commitment gate — has
been computing intent and discarding it. The 7W/5L the tree scores is native's
record with Red Queen's economy attached.

## The seam

Established from FAF's source, not assumed:

- A builder definition may carry `PlatoonAIFunction`, and `PlatoonFormManager`
  forks whatever it names: `hndl:ForkAIThread(import(aiFunc[1])[aiFunc[2]])`.
- `ForkAIThread` passes **the platoon as `self`**, so a plan living in a mod
  file has every `Platoon` method — `GatherUnits`, `AggressiveMoveToLocation`,
  the retreat and stuck-detection helpers. Nothing is reimplemented.
- The brain carries `RedQueenModules` (`RedQueenBrain.lua:122`), which builder
  code already reads. A plan re-reads the objective each pass, so a change
  reaches a running platoon on its next iteration with no push mechanism.
- Red Queen already registers builders into this manager;
  `RedQueenTechUpgradeBuilders` lives there.

**Native forms and fights. Red Queen says where.**

## Build order

Each step states what it must show. A step that does not show it is not built
on top of — it is gated off and recorded, the way formation ownership was.

1. **One directed platoon.** A single land combat form builder whose plan
   gathers, reads `PrimaryObjective`, and aggressive-moves to it in a loop.
   *Must show:* platoons form under the plan and are seen moving to the
   objective; no scheduler failures; the matrix is no worse than 7W/5L.

2. **Objective following.** The plan re-aims when the objective changes.
   *Must show:* logged objective changes produce logged re-aims within a
   plan cycle, and the matrix is no worse.

3. **Layer coverage.** Air, naval and amphibious plans.
   *Must show:* directed platoons on each layer the map supports.

4. **Preservation.** The plan uses native's retreat helpers when losing.
   *Must show:* K/L improves against step 3 on the same cells. This is the
   step with a real chance of moving the record rather than the mechanism.

5. **Only then**, revisit whether native's undirected combat builders should be
   suppressed — additive first, measured second.

## Measurement

The twelve-cell matrix at `scripts/run-matrix.sh`, one cell at a time, compared
against a baseline **measured on the same tree the same day**. The recorded
table in `variety-matrix.md` disagrees cell-for-cell with what `0a9c707`
actually scores, which invented three regressions that were never real.

Every log goes through `scripts/analyze-log.py` before any figure is quoted: it
gates on scheduler failures, and 177 of them once sat unnoticed in a run whose
result had already been reported.

New telemetry needed at step 1: directed platoons formed, plan passes, and the
objective each plan is pursuing.

## Known dead ends

Recorded so they are not retried.

- **`SetPlatoonData` steering.** `HuntAI` ignores platoon data entirely and
  attacks the closest enemy; `AttackForceAI` reads it only for `MaxPlatoonSize`
  and `UseFormation`. Data cannot aim a native plan.
- **Suppressing native combat formation.** Cost four cells (3W/9L against
  7W/5L). Nothing was wrong with native forming platoons; nothing told them
  where to go.
- **Ownership plus Red Queen's own dispatch.** 3W/9L. Adding gathered waves on
  top changed which cells were lost, not how many — also 3W/9L.
- Both are gated behind `Constants.Policy.FormationOwnership`, which is off.

## What this does not claim

Directing platoons is not obviously enough to convert defeats. The three
LandLarge cells lose at the session anchor too, and no change this session moved
them. This work makes the objective system *live*, which is the precondition for
judging it at all — not a win rate on its own.


## Correction: InstanceCount was not the cap

The commit that raised the directed builder's `InstanceCount` from 2 to 12 says
"the cap was InstanceCount". A verification run says otherwise, and the claim is
withdrawn.

`directed=N/M` is a cumulative count of platoons ever formed, not platoons
alive. A probe taken *before* the change already reached 7 formations in two
minutes with `InstanceCount = 2`, because platoons die and the builder forms
again. The cap was never reached.

What actually limits formation is the pool. In the verification run the census
reads `army=14/1/1`, `15/0/0`, `14/1/0` — between zero and six units free at any
moment against fourteen owned, and the template needs three to form. In the live
match it was `36/6/6`: six free, enough for two platoons of three, and two
platoons is what formed.

**And the census cannot attribute that gap.** `owned - pooled` counts every unit
in any platoon, Red Queen's directed ones included, so "native holds thirty" was
not a measurement — it was an assumption wearing one. Separating Red Queen's own
platoons from native's needs a count the census does not yet take.

The `InstanceCount = 12` change is harmless and matches native's own counts, so
it stays. It is not expected to move anything, and the claim that it was "the
first fix that plausibly changes a result" was wrong.
