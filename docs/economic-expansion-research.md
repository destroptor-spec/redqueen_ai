# Economic expansion — community tactics, and where Red Queen actually stands

Research pass on 2026-09-08, prompted by the finding that endgame commitment is
gated by income rather than by the endgame trigger.

## On sources

`reddit.com` is not accessible to this crawler (Anthropic's user agent is
blocked), so the Reddit subreddits could not be read directly. Neither
`forum.faforever.com`, `wiki.faforever.com`, `supcom.fandom.com` nor
`steamcommunity.com` served pages to the fetcher either — all returned 403/402
or a rate-limit page. What follows therefore comes from two sources:

1. **Search-result synthesis** over those same community pages (titles and URLs
   listed at the end), which does surface the substance of the threads.
2. **The game's own blueprints**, read directly out of
   `~/.faforever/gamedata/units.nx2` and `lua.nx2`. Every number in the payback
   table below is computed from the shipped blueprint, not quoted from a forum
   post — so the quantitative half of this document is first-party and exact.

Where community advice and blueprint arithmetic disagree, the arithmetic wins.

## What the community says

- **Never open with power or extractors — build a factory first.** Two power
  generators and two extractors make a land factory self-sustaining.
- **Reclaim is a real opening economy.** Wrecks return ~70% of build cost; about
  five medium rocks fund a T2 extractor. An engineer pulls that in seconds where
  a T1 extractor yields 120 mass/minute. Good build orders are written around
  where the reclaim is.
- **T1 extractor spam first, to the limit of map control**, then save for the
  first T2 and upgrade the rest.
- **Upgrade one extractor at a time**, and only when the military position is
  stable — an upgrading extractor runs at negative mass while it works.
- **Surround a T2 extractor with mass storage, then upgrade it to T3 immediately**
  rather than surrounding the next one.
- **Prefer extractor upgrades to mass fabricator farms** — cheaper and safer.
- **T1 engineers are the most cost-effective build power**; assist factories
  before building more of them. ~4 engineers double a factory's output. Practical
  ratios quoted are ~5 engineers per factory.
- **Build more power than you need** — energy stores poorly and everything needs
  it. Fabricators are power-hungry and belong checkerboarded with generators.
- **Adjacency is a percentage discount** that scales linearly with how many
  faces are filled: T1 pgen 25% at full adjacency, T2 50%, T3 75%, hydrocarbon
  50%; mass storage gives a producer +50%.
- On AI specifically, players observe that AIs *collect* mass adequately — going
  for most or all extractors and upgrading many — but **struggle to convert that
  economy into combat power**, and that humans keep build efficiency higher by
  avoiding mass stalls.

## The payback hierarchy, computed from the blueprints

| investment | mass | gain | payback |
| --- | --- | --- | --- |
| **New T1 extractor on an unclaimed point** | 36 | +2.0/s | **18 s** |
| 4 mass storage around a T3 extractor | 800 | +9.0/s | 89 s |
| T1 → T2 extractor upgrade | 900 | +4.0/s | 225 s |
| 4 mass storage around a T2 extractor | 800 | +3.0/s | 267 s |
| T2 → T3 extractor upgrade | 4600 | +12.0/s | 383 s |
| 4 mass storage around a T1 extractor | 800 | +1.0/s | 800 s |

Energy, as energy per second per mass invested: hydrocarbon **0.625**, T3 pgen
0.772, T2 pgen 0.417, T1 pgen 0.267.

Three conclusions follow, and the first dominates everything else:

1. **Claiming an unclaimed mass point is worth twelve of any other economic
   action.** 18 seconds against 225. Map control *is* the economy; this is why
   the community advice is "T1 spam to the limit of map control" and why the
   large-map expansion problem and the economy problem are the same problem.
2. **Storage adjacency is worth it on T3, marginal on T2, and a waste on T1.**
   The community rule "surround the T2, then upgrade it" is close but the
   arithmetic prefers "upgrade to T3 first, then surround".
3. **Hydrocarbons are 2.3× as mass-efficient as T1 power generators.** Where a
   map has them, they should be taken before pgen spam.

## What Red Queen already inherits

FAF's native builders, which Red Queen runs on top of, already cover the
economy: `AIEconomicBuilders.lua` has 23 builder groups and 133 builders
referencing `T1Resource` (×21), `T2Resource` (×4), `T3Resource` (×3),
`T1EnergyProduction` (×37), T2/T3 energy, `T1HydroCarbon` (×2), `MassStorage`
(×2), `EnergyStorage` (×6) and `T3MassCreation` (×2); `AIEconomyUpgradeBuilders.lua`
adds 58 upgrade builders.

(Counts corrected: a first pass read `--'T1Resource',` as a live entry and
reported 23 and 41. FAF's builder files carry a lot of commented-out build
orders — the *Easy* initial ACU builders have their extractors commented out
entirely — so any count over that source has to strip Lua comments first.)

Red Queen has **no code of its own** for storage, adjacency, reclaim,
hydrocarbons or fabricators — it modulates the native builders by priority. So
the question is never "does it do this at all" but "does the native default do
it well enough, and does Red Queen's priority work help or hinder".

## Where Red Queen actually stands (21-cell matrix, sizing payload)

Two of the community's headline levers turn out **not** to be gaps:

| measure | Red Queen | opponents |
| --- | --- | --- |
| reclaim as a share of mass income | **10.7%** | 9.5% |
| mass wasted (`massout.excess`) as a share of income | **0.4%** | — |

So the natives already reclaim competitively, and there is no stall-and-overflow
problem to fix. Total mass produced averages **1.24×** the opponents'.

The gap is elsewhere. Kills-per-mass-produced, Red Queen against the stock AI in
the same match, 1v1 cells only (both sides stop at the same moment):

| map type | conversion ratio |
| --- | --- |
| land 1v1s (isis, sentry, syrtis, sweepwing) | 0.56, 0.63, 0.63, 0.80, 0.82, 0.90, 0.92, 0.97 — **all below 1** |
| naval 1v1s (sludge) | 0.65, 0.67, 1.38, 1.72, 5.12 |
| median, all 14 | **0.91** |

**On land maps Red Queen turns each unit of mass into roughly 20% less
destruction than the AI it is fighting.** That is the same thing the community
says about AIs generally, measured on this one.

And it shows in where the wins are. Sorted by economy ratio, the 1v1 cells:

| economy ratio | outcome |
| --- | --- |
| 0.54, 0.79, 0.83 | defeat, defeat, defeat |
| 0.85, 0.86 | **victory, victory** (both naval) |
| 0.87, 0.89, 0.97, 1.02, 1.04, 1.12 | defeat ×6 |
| 1.60, 1.61, 1.75 | **victory ×3** |

Every cell in the 0.87–1.12 band is a defeat. Red Queen loses at economic
parity and wins at about 1.6×, which is what a conversion ratio below 1
predicts: it needs an economic edge to pay for a worse exchange rate.

**Caveat on the earlier, stronger-looking version of this.** Across all 21 cells
the split was 6W/4L when ahead on mass against 2W/9L when behind — but that is
confounded: in a team game Red Queen can die while its allies fight on, which
truncates its own cumulative production relative to enemies still playing. The
1v1 table above removes that confound and the relationship is real but much
weaker (3W/3L against 2W/6L, n=14). Cumulative totals cannot settle the causal
direction; the conversion ratio is the sounder measure.

## Options

All of these are open; the ordering is by measured leverage.

1. **Conversion, not income.** The land-map deficit is ~20% and it applies to
   every mass Red Queen already earns, including any new economy added. Nothing
   else on this list pays back until this does. It is also the least explored:
   candidates are army composition against observed enemy composition, build
   power allocation (assist versus more factories — natives may already be
   near-optimal), and whether mass is going into units that never reach a fight.
2. **Map control for cheap extractors.** 18-second payback makes this the best
   *economic* action available, and it is the same work as the large-map
   expansion the previous session was already pursuing — a forward base that
   holds is an economy, not just a position. Red Queen does not currently track
   how many mass points it holds against how many exist, which is a measurement
   gap worth closing first: without it there is no way to say whether expansion
   is failing for lack of trying or lack of holding.
3. **Hydrocarbon preference.** Cheap, contained, 2.3× the mass efficiency of T1
   pgens where the map has them. Small but nearly free.
4. **Storage adjacency on T3 extractors only.** 89-second payback, and it needs
   adjacency-aware placement Red Queen does not have today. Worth it only once
   T3 extractors exist in numbers — which on this matrix they mostly do not.
5. **Mass fabricators.** The community consensus and the arithmetic agree: worse
   than upgrades, power-hungry. Leave to the natives.

The honest recommendation is 1 and 2 together, with 2 measured first because it
is cheap to instrument and it tells us whether the expansion work already done
is delivering economy.

## Sources

- [Ladder 1v1 — Beginner, Intermediate and Advanced Topics, by arma473 (FAForever Forums)](https://forum.faforever.com/topic/766/ladder-1v1-beginner-intermediate-and-advanced-topics-by-arma473)
- [Efficiency in economy (FAForever Forums)](https://forums.faforever.com/viewtopic.php?f=62&t=13027)
- [How quickly should I upgrade mass extractors? (FAForever Forums)](https://forums.faforever.com/viewtopic.php?f=63&t=12981)
- [Beginner's Guide to Forged Alliance Forever (FAForever Wiki)](https://wiki.faforever.com/Play/Learning-SupCom/Beginners-Guide-to-Forged-Alliance)
- [Adjacency Bonus (FAForever Wiki)](https://wiki.faforever.com/en/Play/Learning/Adjacency-Bonus)
- [The Spura's Definitive Guide To Adjacency Bonuses (GameReplays.org)](https://www.gamereplays.org/community/?showtopic=165702)
- [Economy (Supreme Commander Wiki)](https://supcom.fandom.com/wiki/Economy)
- [Mass extractor (Supreme Commander Wiki)](https://supcom.fandom.com/wiki/Mass_extractor)
- [Mass fabricator (Supreme Commander Wiki)](https://supcom.fandom.com/wiki/Mass_fabricator)
- [For the Love of God Start Getting Reclaim (Steam guide)](https://steamcommunity.com/sharedfiles/filedetails/?id=1934428094)
- [SC:FA Strategy — The Incomplete Guide (Steam guide)](https://steamcommunity.com/sharedfiles/filedetails/?id=403039944)
- [Ideal Factory/Engie ratio (Steam discussion)](https://steamcommunity.com/app/9420/discussions/0/1368380934266794223/)
- [Best way to manage mass extractors upgrades (Steam discussion)](https://steamcommunity.com/app/9420/discussions/0/483367798500757373/)
- [Starting Build Orders (supcom.standardof.net)](https://supcom.standardof.net/supreme-commander/starting-build-orders/)
- [Sorian AI — isn't it supposed to be better? (FAForever Forums)](https://forum.faforever.com/topic/1652/sorian-ai-isn-t-it-supposed-to-be-better)
- First-party: `~/.faforever/gamedata/units.nx2` blueprints and
  `lua.nx2:lua/AI/AIBuilders/*.lua`

## Decisive: the economy matches, the exchange rate does not

Per-army mass accounting from the engine's own end-of-match stats settles which
of the two problems is real. `built` is mass produced into units, `lost` is mass
destroyed, `kills` is enemy mass destroyed; the exchange rate is kills over
losses.

| cell | mass built, RQ vs opponent | exchange, RQ vs opponent | result |
| --- | --- | --- | --- |
| `isis-aeon-s2` | 252k vs 250k | **0.54 vs 1.76** | defeat |
| `sweepwing-aeon-s2` | 104k vs 128k | **0.46 vs 1.95** | defeat |
| `syrtis-aeon-s2` | 277k vs 278k | 0.78 vs 1.05 | defeat |
| `sentry-uef-s1` | **104k vs 62k** | 1.01 vs 0.87 | victory |
| `sludge-cybran-s1` | **101k vs 46k** | 2.28 vs 0.38 | victory |

On the land cells it loses, Red Queen produces **the same total mass as the
stock AI and trades at roughly half the rate**. Where it wins, it wins by
building 1.6-2.2× the mass — overwhelming with production despite a mediocre
exchange. That is the same thing the economy-ratio table says (wins cluster at
1.6× income) seen from the combat side, and together they make the diagnosis
unambiguous: **income is not the constraint; the exchange rate is.**

### A concrete lead: tier composition and where the losses fall

Per-category counts, built / lost, for the same matches. Note that the engine's
third field in these records is *enemy units of that category destroyed*, not
kills by that category — misreading it inverts the story.

| cell | RQ Tech 1 | RQ Tech 2 | opponent Tech 1 | opponent Tech 2 |
| --- | --- | --- | --- | --- |
| `isis-aeon-s2` | 426 / 276 | 249 / **189 (76%)** | **964** / 714 | 109 / 33 (30%) |
| `sweepwing-aeon-s2` | 356 / 291 | 166 / **134 (81%)** | **652** / 431 | 106 / 17 (16%) |
| `syrtis-aeon-s2` | 539 / 388 | 207 / **125 (60%)** | **998** / 694 | 138 / 46 (33%) |

Two differences, consistently:

1. **The stock AI floods Tech 1** — 964, 652, 998 units against Red Queen's 426,
   356, 539 — while Red Queen fields two to three times as much Tech 2.
2. **Red Queen loses 60-81% of its Tech 2, the opponent 16-33% of its.**

So the higher-tier investment is not being converted; it dies at twice the rate
the opponent's does. That points at commitment quality for Tech 2 and Tech 3
rather than at the tier decision itself — a Tech 2 unit that dies at 76% is
being sent into fights it does not win, or arriving piecemeal, which is exactly
the failure the offensive commitment gate exists to prevent and which
`CombatManager.lua:265` already records as a past regression.

This is the primary line of work, and it is not an economy problem.

### The mechanism: the commitment gate attacks into the dark

`CombatManager:GetObjectiveThreat` reads `intel:GetThreatNear(objective.Position,
CommitmentThreatRadius, layer)` and nothing else. The commitment gate then holds
a wave only when `waveThreat < enemyThreat * CommitmentThreatRatio`.

`GetThreatNear` returns **0 for three different situations** — a place observed
and empty, a place never observed, and a place whose observations have expired.
`IntelManager` says so in its own comment, added when exactly this defect was
fixed for route safety:

> Route safety in particular was treating "we can see nothing there" as
> "nothing is there", which is at its most wrong exactly where the army has not
> looked.

`GetCoverageNear` was written for that fix and is used **only** in
`WorldModel`'s route safety. The commitment gate never consults it. So an
unobserved enemy position reads threat 0, `required` becomes 0, and any wave
meeting `MinimumAttackUnits` commits — into whatever is actually there.

That is a coherent mechanism for both headline numbers: an exchange rate around
half the opponent's, and Tech 2 losses of 60-81% against their 16-33%. Waves
attack positions they have not seen, and a defended position eats them.

**One caution, from this session's own record.** A presumed-threat brake was
added to *route* safety earlier, measured, and found harmful — it cost a forward
base start and 4.8 peak mass while saving no engineer, and was removed with a
guard against reinstating it. A brake on commitment could fail the same way by
holding waves that would have won. So the design has to be a *coverage-weighted
estimate* rather than a veto, and it has to be measured on the exchange rate
rather than assumed:

- Where coverage is high and threat is 0, "empty" is a real reading — commit.
- Where coverage is near zero, the destination is unknown, and the honest
  estimate is not 0. Scaling the requirement by how little is known, rather than
  blocking outright, keeps the wave moving while stopping the free pass.
- Scouting is the alternative answer to the same problem and may be cheaper:
  raising observation before committing removes the guesswork instead of
  modelling it.

Measurement: the exchange rate (`kills.mass / lost.mass`) against the opponent's
in the same match, plus Tech 2 loss share. Both are already in the per-army
stats, so no new instrumentation is needed.

## Scouting, measured

The commitment gate was left alone; only the information feeding it changed —
target ranking by ignorance, a single-unit fallback to look at the objective,
and scout production scaled by the share of wanted positions that are unseen
(previously 15% until any observation existed, then 7% forever).

| | record | mean K/L | 1v1 mean exchange |
| --- | --- | --- | --- |
| sizing payload | 8W/13L | 1.00 | 1.12 |
| + scouting | **11W/10L** | **1.11** | **1.35** |

On the 14 1v1 cells, where both sides stop at the same moment and the exchange
rate is cleanly comparable, the record went **5W to 9W with 4 flips up and 0
down**.

Every aggregate moves the same way, which is the first time in this
investigation that has happened. It is still **not established**:

- On all 21 cells the flips are 5 up, 2 down — a sign test gives p = 0.45. The
  1v1 subset's 4-0 gives p = 0.125. Suggestive, not significant.
- **Attribution between the two mechanisms is unresolved.** Dispatches per match
  were 0-5 in eleven of fourteen 1v1 cells (27 in one, `syrtis-aeon-s2`, whose
  exchange rate actually *fell* from 0.78 to 0.57 while it won). So the gain may
  come from the adaptive production — more scouts means more observers, since
  intel is gathered by sampling own units — rather than from directed dispatch.
  Blind share still sat at 30-77% of wanted positions.

The isolating experiment is one matrix per arm: adaptive production with
dispatch disabled, and dispatch with production returned to the old binary. That
would say which half is doing the work before either is built on further.

What this does settle is that the **commitment gate did not need a
presumed-threat floor to improve** — better information moved the exchange rate
on its own, which is the outcome the route-safety lesson would have predicted
and the reason the gate was deliberately left untouched.
