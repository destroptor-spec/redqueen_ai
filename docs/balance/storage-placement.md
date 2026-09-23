# Storage placement investigation, 2026-09-20

The user restored control payload
`24c0b34595dc28d08f1220b3a3b4db92f7262731b7d5b093e808397270d8dac5`.
The current Lua files match that fingerprint. The proposed builders and their
contracts remain in [storage-adjacency.patch](storage-adjacency.patch); that
patch has not been reapplied. The earlier gunship experiment and its 8W/4L
reference describe a different payload, not this current control.

## What the installed code establishes

Read directly from `/home/andreas/.faforever/gamedata/lua.nx2`:

- `lua/platoon.lua:2489–2506` selects own targets within the engineer manager's
  `AdjacencyDistance` and dispatches to `AIBuildAdjacency`.
- `lua/AI/aibuildstructures.lua:387–434` creates candidate positions using the
  target and storage `Physics.SkirtSizeX/Z`. For a 2x2 extractor and 2x2 storage,
  an extractor at `(100,120)` supplies storage centers `(100,118)`, `(100,122)`,
  `(102,120)` and `(98,120)`. Those are edge-touching candidates. All four
  factions' installed T2 extractor and mass-storage blueprints use 2x2 skirts
  with matching offsets.
- Candidates within eight units of the map border are excluded. Dead targets
  are skipped. Engine `FindPlaceToBuild` decides which candidate is buildable.
- **Lines 437–438 fall back to `AIExecuteBuildStructure` when adjacency fails.**
  That routine can queue an ordinary base/engineer-relative position without
  any extractor adjacency requirement. An empty local target list also reaches
  this fallback.

Thus `AdjacencyCategory` requests adjacency but does not require it. The saved
builder's army-wide cap of four storages per upgraded extractor neither checks
local skirt availability nor stops a builder at another base from falling back.
Its `storage=` count cannot distinguish useful adjacency from remote storage.
This is a concrete failure path, not proof that it explains a particular past
match: completed storage positions and actual adjacency were not supplied here.

## Offline check: user-reported pass

The new checker executes the installed native placement functions under LuaJIT,
using installed T2/T3 extractor and storage skirt dimensions for all four
factions. It models engine search/collision responses and checks both the clear
ring and the non-adjacent fallback for full rings, blocked sites, absent/dead
targets and map borders. It does not construct units or verify engine adjacency
callbacks. Archive fingerprints are printed with the result.

```bash
python3 scripts/check-native-adjacency.py \
    /home/andreas/.faforever/gamedata/lua.nx2 \
    /home/andreas/.faforever/gamedata/units.nx2
```

The user ran this checker and supplied the full passing output. Both T2 and T3
extractors for UEF, Aeon, Cybran and Seraphim produced four touching orders on
the clear ring. All eight cases produced a non-adjacent order at `(200,220)`
for each of: full ring, blocked sites, no local target, dead target and the
map-edge exclusion. Recorded archive fingerprints:

```text
lua.nx2   ac520415c718a69c28ce7fc92e41dd9650602874c18460f8e9ad9f97a83028f8
units.nx2 edf30919b56870bbcb4302f43a4afca9863becb0ab5284eea51b3ed92e1c5418
```

The user also reported `All Red Queen validation checks passed` for the control.
Neither result validates the new candidate below. No test was run by the agent,
following the user's instruction. The existing fast gate and whitespace check
can be run separately:

```bash
./scripts/validate.sh
git diff --check
```

## Unapplied mass-storage candidate

[storage-mass-only.patch](storage-mass-only.patch) is a new, separate candidate
against the current control. The original bundled patch is unchanged. The new
patch adds only the mass-storage builder, its placement module/hook, telemetry
and contracts; it does not include the earlier gunship gate, energy storage,
or sentry calibration changes.

The builder keeps the saved mass-storage priority `935` and instance count `2`.
Eligibility checks a completed own T2/T3 extractor and a free skirt position
within 60 units of the requesting base. It checks the local defense alert and
economy, then rechecks the engineer, manager, target, build capability and
route verdict when selected. Positions use only the verified 2x2/equal-offset
geometry; other footprints are refused. The hook is opt-in to this Red Queen
job and never calls the native fallback on refusal. Other jobs and brains
retain native placement.

Reservations follow the original queue entry, engineer, platoon and manager;
they prevent overlapping pending sites and release on cancellation, queue
replacement/consumption, reassignment, capture, death or base retirement.
Native code still owns construction and retries after the initial order. A
target may subsequently be destroyed, or engine construction may fail; this
candidate does not promise a lasting adjacency benefit merely from queueing.

Periodic diagnostics add:

```text
massstorage=<attempts>/<queued>/<refused>/<last-reason>
massstorageheld=<live>/<completed>/<completed-adjacent-to-own-upgraded-extractor>
```

The last count reads native `AdjacentUnits`, not proximity, and counts each
storage once. It is surviving inventory, not lifetime completions or measured
bonus income. Placement logs include the extractor id and queued coordinates.

To run the candidate's contracts without changing the active control, make a
local clone, copy the current working files into it, and apply the candidate
only there. The clone must have a valid Git `HEAD`: the launcher contracts
exercise `record-runtime.py`, which records the revision, status and diff.

```bash
(
    set -e
    rq_storage_check=$(mktemp -d /tmp/rq-storage-check.XXXXXX)
    git clone --no-hardlinks --quiet . "$rq_storage_check"
    rsync -a --delete --exclude='.git' --exclude='storage-candidate.tmp' ./ "$rq_storage_check/"
    git -C "$rq_storage_check" apply "$PWD/docs/balance/storage-mass-only.patch"
    cd "$rq_storage_check"
    ./scripts/validate.sh
    python3 scripts/check-hook-targets.py /home/andreas/.faforever/gamedata/lua.nx2
)
```

Run from the repository root. These commands execute contracts and inspect the
installed hook targets; they do not launch FAF. The first instructions omitted
the clone and excluded `.git` from the copy. The user then reported failures
for all three scouting-mode launcher/manifest cases. Source inspection found
that this copy has no `HEAD` for `record-runtime.py`; the corrected instructions
above retain the manifest's provenance checks. The corrected command has not
been run by the agent. The user subsequently reported both
`All Red Queen validation checks passed` and
`checked 9 captured symbols across hook/lua` from the corrected command.
Candidate contracts and hook-target inspection therefore have a user-reported
pass. Native construction and balance results remain unverified.

## Bounded native construction fixture

The prepared verifier creates another local candidate clone and validates it,
then launches one isolated Sentry Point session. Its runtime overlay loads the
candidate placement module and appends the candidate hook to the native
`aibuildstructures.lua` environment explicitly. The active mod and its symlink
remain on the control. The full candidate's builders and diagnostics are not
installed in that session.

The fixture owns the launcher's civilian human army. It supplies an engineer,
funding, a completed extractor and a small synthetic manager/platoon context.
Real native orders must construct one mass storage for each of four factions
at T2 and T3. Each case checks:

- The completed storage matches the queued location and touches the extractor's
  actual skirt.
- Native `AdjacentUnits` registers the relationship in both directions.
- `MassProdAdjMod` becomes `1.125`, and measured army-income gain is 12.5% of
  the income contributed by that extractor before storage.
- Destroying that storage removes the modifier and restores the measured
  income. This also checks that unrelated fixture income did not explain the
  increase.

The income check uses measured ratios, so it does not assume per-tick versus
per-second API units. Fixture buffers/power are spawned away from the extractor;
only the newly constructed storage counts as candidate output. This proves a
funded native construction mechanism if it passes, not ordinary builder
selection, engineer allocation, affordability, a complete four-storage ring,
or balance.

Run from the control checkout:

```bash
python3 scripts/verify-storage-placement.py \
    --output "$HOME/rq-evidence/storage-placement-1"
```

Use a new output directory on retries; evidence is never overwritten. `--slot 2`
selects `RQTest2.prefs` instead of the default slot 1. The verifier checks the
active symlink, control fingerprint, slot preferences, running games and memory
before launching. It has a ten-minute wall-clock limit and terminates only the
game bearing both `/redqueen` and this fixture's exact `/log`, never `/gpgnet`
games, wrappers or Wine services. It runs `analyze-log.py` before accepting the
result. All eight case records, the final PASS marker, unchanged payload/overlay
and no remaining owned game process are required for exit 0.

Evidence is retained under the output directory: `game.log`, its launch
manifest, `overlay/sources.json` with candidate module/hook and archive hashes,
`analysis.txt`, and `result.json`. The launch manifest intentionally identifies
the control; the sources file identifies the additional fixture and the exact
candidate code it executes. This is not input for `check-balance.py`.

**The verifier and fixture have not been run by the agent.** The user's earlier
contract pass predates these new fixture files. The verifier reruns validation
before its first game launch.

## Conditions for another experiment

Storage delivery is a plausible repair, not a dead end established by the
bundled matrix. A storage-only candidate should require a live own upgraded
extractor with a free touching site, decline the job when none exists, and
avoid the ordinary-placement fallback. Concurrent builders must not reserve
the same site; ownership, completion and safety need rechecking before orders.
The native geometry can be reused; the fallback behavior is the part that
must change for this specific job. General native construction should retain
its existing behavior.

Before a balance matrix, a bounded in-game fixture still needs to build one
storage and record its completed position, extractor position/skirt,
`AdjacentUnits` relationship and production bonus. Offline geometry alone does
not establish that the engine accepts the order or applies the buff. Subsequent
mechanism telemetry must distinguish requested, placed, completed and actually
adjacent storage, including refusal/fallback reasons.

Keep mass storage, hydro energy storage and increased sentry targets as
separate treatments. The saved patch's ground-defense constants are already
back at the control values `4/12/12`; applying that patch would not reproduce
the raised-sentry treatment. Recover the exact raised values from its recorded
patch before a sentry-only comparison, and compare against matching control
maps, starts, factions and seeds. The bundled results cannot establish the
sentry change's independent cost. No new matches have been launched for this
investigation.

## Fixture run: passed, eight of eight

Run by the agent on 2026-09-20 from the control checkout. Evidence in
`~/rq-evidence/storage-placement-8`.

```
status: passed  stop: pass  cases: 8  wall: 57.2s
control_unchanged: True  overlay_unchanged: True  remaining_owned_pids: []
```

Every case: the completed storage sits where it was queued, native
`AdjacentUnits` registers the relationship, `MassProdAdjMod` is `1.125`, and
measured army income rises by exactly 12.5% of that extractor's contribution.
Destroying the storage restores the income.

| tier | income base | income gain | ratio |
| --- | ---: | ---: | ---: |
| T2 (`?b1202`, all four factions) | 0.6000 | 0.0750 | 12.5% |
| T3 (`?b1302`, all four factions) | 1.8000 | 0.2250 | 12.5% |

This establishes that the engine accepts the candidate's order and applies the
buff. It does not establish builder selection, engineer allocation,
affordability, a complete four-storage ring, or balance.

### What the first four runs cost, and why

The fixture needed three repairs before it could reach its own cases. None of
them touched the candidate, `MassStorage.lua` or the hook.

1. **`FindSite` could not say why it refused.** It reported only "no clear
   fixture site". Adding a breakdown -- `tried/ring-blocked/aux-blocked` and the
   first failing offset -- turned an opaque failure into a one-run diagnosis.
2. **The fixture's own equipment was pinned to the extractor site.** Buffers at
   `+20`/`+24` and power at `(+20,+20)` were required to be buildable at fixed
   offsets, which refused 43 of 49 candidate sites on Sentry Point; the
   adjacency ring itself was never the blocker. Those units are spawned with
   `CreateUnitHPR`, not built, so they only need valid ground away from the
   ring. They are now searched independently across six directions.
3. **The match outlived the fixture only on a large map.** Eight cases need
   about 17 game minutes. Sentry Point resolved at 16:39 and Fields of Isis
   similarly, so cases 7-8 raced the end of the match and produced three
   different symptoms across three runs -- an unrecorded refusal, an
   `engineer-unavailable` refusal, and the sim stopping before the diagnostic
   printed. The verifier now takes `--map` (default `SCMP_018`); Crossfire
   Canal (`SCMP_024`, 20 km) gives the headroom and all eight pass there.

The Seraphim refusal was therefore a fixture-lifetime artifact, not a faction or
geometry gap: cases 1-6 reported clean engineer state
(`dead=nil army=1/1 manager-match=true platoon=true retreating=false queue=0`)
immediately before each call.

**Suggested candidate change, not made here.** `engineer-unavailable` collapses
five distinct preconditions into one reason string, which cost two runs to
diagnose. Splitting it in `Record` would let the candidate name the failing
precondition in an ordinary match, where no fixture diagnostics exist.

### Still unverified

Balance. The storage-only matrix that lost four of six wins ran with
*non-adjacent* storage, so it measured the fallback, not this candidate. A
matrix against the `combat-holdcontrol` 6W/2L control is the first real test of
the idea.

## Tuning the mass-storage candidate: priority, timing, and what it settled

Four arms, the same eight large-land cases, one sample each.

| arm | record | notes |
| --- | --- | --- |
| control (no storage) | **6W/2L** | payload `24c0b34595dc` |
| control, re-run | **6W/2L** | 8/8 cells agree, K/L identical to 2 dp |
| storage, no timing gate, priority 935 | 2W/6L | adjacency worked; 34/34 storages adjacent |
| + maturity gate (`MassIncome >= 10`) | 4W/4L | one gain |
| + priority 900 (below Engineer T2 at 917) | 4W/4L | different cells |

**The matrix is deterministic.** The control re-run reproduced every cell exactly,
so a single sample per cell is conclusive for that exact map, seed, faction and
payload. Differences between arms are causal, not variance. What a single sample
cannot do is generalise to unseen seeds.

That matters for reading the two tuned arms. They post the same record but win
different cells:

| case | gate@935 | prio@900 |
| --- | --- | --- |
| Isis 2071971 Aeon | victory | defeat |
| Isis 424242 Aeon | victory | defeat |
| Isis 8675309 Cybran | defeat | victory |
| Syrtis 2071971 Aeon | defeat | victory |
| Syrtis 424242 Aeon | defeat | victory |
| Syrtis 8675309 Sera | victory | defeat |
| **Syrtis 8675309 UEF** | **victory** | **victory** |
| Isis 8675309 UEF | defeat | defeat |

Seven of the eight cells are won by *some* configuration, and a single-step
priority change flips half of them. A deterministic simulation is still
chaotic: a small timing change cascades into a different match. Searching
priority space against eight fixed seeds would therefore be fitting the seeds,
not improving the policy.

**What is robust.** Storage without a timing gate is clearly harmful, 2W/6L.
With one it costs two cells net at both priorities tried. And Syrtis 8675309
UEF turns from defeat into victory in *both* tuned arms -- K/L 0.64 against 1.46
and 1.41 -- the only cell where the two arms agree on a change. Both UEF cells
lose at control on both maps, so storage helping the weakest faction is the one
hypothesis here worth testing on its own seeds rather than these.

**Not adopted.** The candidate is preserved in `storage-tuned.patch` and
`storage-tuned.tmp/`; the control tree is unchanged at `24c0b34595dc`.
Adjacency delivery is proven and is not the open question. Whether +12.5% per
extractor is worth the engineer time is, and on these eight cases the answer is
no by two cells.

### Note on the gate

`validate_mod.py` now skips any path with a `.tmp` component. A candidate
staged under `docs/balance/` imports modules the control tree lacks, which
failed the control's own gate while every clone-based run passed, because the
clone rsync already excluded it. Preserved candidate files belong in a `.tmp`
directory for the same reason.

# The 24-cell baseline, and what three candidates did against it

The eight-cell set used earlier was a biased subsample. Widened to 2 large land
maps x 4 factions x 3 seeds.

```
              2071971            424242           8675309
-- Fields of Isis
  UEF        defe  0.60        defe  0.64        defe  0.64
  Aeon       vict  1.35        vict  1.19        defe  0.42
  Cybran     defe  0.93        vict  2.67        vict  1.99
  Sera       vict  1.41        defe  0.92        defe  0.54
-- Syrtis Major
  UEF        vict  3.51        defe  0.45        defe  0.64
  Aeon       vict  2.98        vict  2.52        defe  0.59
  Cybran     vict  2.23        vict  1.77        defe  0.96
  Sera       vict  1.34        vict  2.32        vict  1.58
```

**Baseline 13W/11L**, not the 6W/2L the eight-cell set reported.

**Mass K/L predicts the outcome perfectly: 24 of 24.** No victory below 1.0, no
defeat above it. Winning is trading above parity, so that is the target and the
measure.

Seed 8675309 is 2W/6L across both maps and made up half the old set, which is
why everything looked harder than it is. Isis is 5W/7L against Syrtis 8W/4L.
UEF is 1W/5L against 3W/2L to 4W/2L for the others.

## Re-aim hysteresis, all factions: 12W/10L -> 7W/15L

`ObjectiveAttack` re-aimed whenever the objective crossed an 8-unit bucket, and
every re-aim issues `Stop()` before a fresh move. Measured: the aim point
changed in 40-68% of consecutive samples while platoons were within 35 of their
target in 0-2.8%. Replacing the bucket with 40-unit hysteresis cost **seven
cells of twelve** and took mean K/L from 1.44 to 0.88.

Frequent re-aiming is not a defect. It is how a platoon follows a moving battle,
and suppressing it commits the army to a stale target. The diagnosis was right
and the remedy was backwards.

Hysteresis also only cut churn from 61.9% to 53.7%, so most re-aiming is the
objective genuinely moving, not drift. That is objective churn upstream in
`StrategyDirector`, not a platoon-plan defect.

## The same, scoped to UEF: 13W/11L -> 14W/10L, and still not adopted

Scope verified clean: **zero** non-UEF cells moved, K/L identical to two
decimals on all sixteen.

| UEF cell | base | scoped |
| --- | ---: | ---: |
| Syrtis 2071971 | victory 3.51 | **defeat 0.91** |
| Syrtis 424242 | defeat 0.45 | victory 1.07 |
| Syrtis 8675309 | defeat 0.64 | victory 1.66 |
| Isis, all three | defeat 0.60/0.64/0.64 | defeat 0.63/0.51/0.49 |

Plus one on the record, but **mean UEF K/L falls 1.08 to 0.88** and overall
mean K/L falls 1.42 to 1.37: two cells just
under parity are nudged over while the best UEF cell in the baseline is
destroyed. The record improves as the discriminator worsens, which is the
signature of fitting the win column. Not adopted.

It is also map-dependent -- it helps UEF on Syrtis and hurts on Isis -- which
kills the "UEF is slow, protect its approach" story. Unit speed does not vary by
map. Whatever this is, it is terrain, not faction.

## Standing conclusions

- Judge candidates on mean K/L as well as the record. The record alone has now
  misled twice.
- Every change this session that *replaced* Red Queen's combat behaviour lost
  cells. The one shipped win removed an economic blocker instead.
- Candidates preserved: `reaim-hysteresis.patch`, `uef-reaim-hysteresis.patch`,
  `storage-tuned.patch`, `storage-mass-only.patch`, `airland-gunship-gate.patch`.

# Mirror matchups: the faction comparison was an artifact

Every cell of the 24-cell baseline used opponent faction 3. So Cybran's six
cells were **mirrors** and the other eighteen were cross-matchups against a
Cybran opponent -- and Cybran topped the table. The faction ranking that came
out of it was partly a property of the test design.

A mirror cancels faction balance: both sides hold the same units, costs and
tech, so the only asymmetry left is Red Queen against the stock Adaptive AI.
Eighteen new mirror cells for UEF, Aeon and Seraphim, reusing the existing
Cybran mirrors.

| faction | cross (vs Cybran) | mirror (vs self) |
| --- | --- | --- |
| UEF | 1W/5L, K/L 1.08 | 1W/5L, **0.97** |
| Aeon | **4W/2L, 1.51** | **1W/5L, 0.61** |
| Cybran | -- | **4W/2L, 1.76** |
| Seraphim | **4W/2L, 1.35** | **1W/5L, 0.85** |
| overall | 9W/9L, 1.31 | **7W/17L, 1.05** |

**Red Queen outplays the stock AI only when both play Cybran. On UEF, Aeon and
Seraphim it is outplayed 1W/5L each.**

Two claims from earlier in this investigation are withdrawn:

- *"UEF is the weak faction, 1W/5L against 3W/2L to 4W/2L for the others."*
  False. Under mirrors every faction except Cybran is 1W/5L, and UEF's mean K/L
  (0.97) is the **best** of the three, ahead of Seraphim (0.85) and Aeon (0.61).
  UEF only looked weak because Aeon and Seraphim were being flattered by a
  Cybran opponent.
- *"Cybran is our strongest faction."* Cybran is the only faction whose baseline
  cells were already mirrors, so it was the only one measured on equal footing.
  Its 4W/2L is real -- and it is the outlier, not the rule.

Everything downstream of the faction comparison goes with them: the UEF-scoped
re-aim candidate targeted a faction that is not the outlier, and the UEF air
template gap was investigated because UEF looked uniquely bad.

Composition and exchange-rate analysis of these mirrors is in
[faction-composition.md](faction-composition.md), including the telemetry
contamination that limits plan-level attribution.

**Consequence for the method.** A baseline with a fixed opponent measures the
opponent as much as the candidate. Mirrors are the right default for judging
Red Queen's play; a fixed cross-matchup is for measuring a specific matchup and
should be labelled as such. The 13W/11L figure describes Red Queen against a
Cybran-playing stock AI, not Red Queen in general.
