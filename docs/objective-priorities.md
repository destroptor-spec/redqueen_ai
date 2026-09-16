# Objectives, and the order they should be chosen in

## Why this exists

Scouting was investigated to exhaustion and is not where the large-map weakness
lives. Production sizing turned out to be dead code; wiring it bought one
LandLarge win, cost a Naval win and dropped K/L in eleven of twelve cells.
Observer sampling was refuted arithmetically. Directed dispatch is already
net-useful.

What the same runs show plainly is economy, and specifically economy that is
built and then lost:

| cell | profile | extractors | churn | result |
| --- | --- | --- | --- | --- |
| Fields of Isis 8675309 | LandLarge | 24 built / 24 lost | **1.00** | defeat |
| Fields of Isis 31337 | LandLarge | 21 / 14 | 0.67 | defeat |
| Syrtis Major 31337 | LandLarge | 33 / 15 | 0.45 | **victory** |
| Syrtis Major 8675309 | LandLarge | 22 / 5 | 0.23 | defeat |
| Sentry Point 31337 | LandSmall | 24 / 3 | **0.12** | victory |

Churn tracks the result better than any scouting figure in this series. Peak
capture is 39-56% of map extractors on LandLarge against 58% on LandSmall, so
Red Queen both claims less of a bigger map and keeps less of what it claims.

Nothing in the objective system defends that economy. There is no objective for
covering our own expansion, and none for denying the enemy's.

## What exists today

Objectives are chosen by a **first-match if-chain in code order**, not by
sorting on priority. `Priority` rides on the objective and is read by
`CanInterrupt` and by team coordination, but it does not decide which objective
is selected. Anything described as a priority order below is therefore a
proposal about selection, not a description of it.

| order | type | priority | trigger |
| --- | --- | --- | --- |
| 1 | `Defend` (alert) | 140 | a qualifying cluster at a protected anchor |
| 2 | `Defend` (local) | 120 | `LocalDefenseThreat` near home |
| 3 | `Attack` (ping) | own, escalating to 120 | an ally or human ping |
| 4 | `Support` | 82 | an ally support request |
| 5 | `JointAttack` | ally + 5 | team coordination |
| 6 | `Raid` | 75 | best scored observed target |
| 7 | `Pressure` | 60 | fallback, a naval approach or enemy start |
| 8 | `Stage` | 0 | nothing else applies |

`Reinforce` and `Investigate` are each constructed once. **`Assault`, `Recover`
and `Supremacy` are referenced but never constructed** — dead branches. One of
them is not harmless: `demand.Artillery = objective.Type == "Assault" and 0.18
or 0.10` can never take its high branch, so artillery demand is pinned at 0.10
for the whole match.

## The enemy base is a fact, not an observation

Every intel record decays after `IntelLifetimeSeconds` (180). A base position
should not. Where the enemy spawned is either known from the lobby or learned
once, and it never stops being true.

- `ScenarioInfo.Options.TeamSpawn` is `fixed`, or one of the `*_reveal`
  variants: every player sees the start positions, so Red Queen may use
  `GetArmyStartPos` directly — which is what `WorldModel` already does.
- `random`, `balanced` or `balanced_flex` without reveal: a human does not know
  who spawned where. Red Queen currently reads the starts anyway. It should
  instead treat enemy starts as unknown until something of ours observes a
  structure there, then record that position **permanently**.

Either way the result is the same standing fact: a known enemy base, never
re-scouted, never expired. Attack objectives default there, and `Pressure`
stops being a generic waypoint at a naval approach.

## Proposed order

Selection becomes a ranked choice over candidate objectives rather than an
if-chain. Ties break on the existing rule: higher priority first, then earlier
`CreatedTick`.

| priority | objective | status | trigger |
| --- | --- | --- | --- |
| 160 | **Commander emergency** | partial, inside `Defend`/`Critical` | ACU credibly threatened; outranks everything under Assassination |
| 140 | **Base defence** | exists | qualifying cluster at a protected anchor |
| 120 | **Ally ping** | exists | explicit human or ally request, already escalating |
| 115 | **Cover expansion** | **missing** | our own extractors or engineers under observed threat outside the base |
| 110 | **Local defence** | exists | `LocalDefenseThreat` near home, still gated by `CanInterrupt` |
| 82 | **Support ally** | exists | ally support request |
| 80 | **Joint attack** | exists | team coordination |
| 78 | **Deny expansion** | **missing** | observed enemy engineer or extractor outside their base |
| 75 | **Raid** | exists | best scored observed target |
| 70 | **Secure expansion** | **missing** | an unclaimed cluster on our side with a safe route, needing escort |
| 60 | **Pressure enemy base** | exists, needs the standing fact | the remembered enemy spawn, not a waypoint |
| 40 | **Investigate** | vestigial | a high-value area nothing has seen, or an unexplained loss |
| 0 | **Stage** | exists | nothing else applies |

Three of these do not exist, and they are the three that concern economy.
`Cover expansion` is placed above local defence deliberately: an extractor line
being eaten is a larger loss than a couple of raiders near the base, and the
churn figures say that is what is actually happening.

## What to build first

1. **The standing enemy-base fact**, gated on `TeamSpawn`. Small, testable
   without a match, and it makes every attack objective terminate somewhere real
   instead of at a fallback waypoint. It also removes enemy starts from the
   scouting candidate set, which is the one remaining scouting hypothesis.
2. **`Cover expansion`**, because churn of 1.00 on Fields of Isis says the
   economy is being built and handed straight back. It reuses the garrison
   machinery that already covers forward bases.
3. **`Deny expansion`**, the mirror, once the enemy base is a fact and anything
   outside it is by definition an expansion.

Ranked selection should land with the first of these, since adding objectives to
an if-chain silently orders them by where they were pasted.

Nothing here is measured. Each is a hypothesis with a stated trigger, and the
churn column is the figure to judge them by.
