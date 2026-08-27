# Architecture

## Runtime flow

`RedQueenBrain` subclasses FAF's maintained adaptive brain. The base brain supplies compatible builder managers, platoon machinery, reclaim grids, and marker generation. The Red Queen adds deterministic directors on top:

1. `MatchContext` freezes teams, hostile armies, the distinct Assassination, Supremacy, or Annihilation mode, and the income multiplier.
2. `IncomeBonus` applies an army-specific production buff and maintains it across construction and unit transfers.
3. `WorldModel` classifies the map and turns resource markers into expansion clusters.
4. `IntelManager` samples from Red Queen observers, retains only confidence-decaying sightings, and scores exposed economic targets against observed local threats.
5. `EconomyManager` reports stalls, surplus, and sustainable production pressure.
6. `StrategyDirector` selects one scored objective, tracks combat momentum and recent land and air losses, acknowledges observed army concentrations at typed critical anchors, chooses a counter doctrine, and maintains evidence-driven weights for army pressure, tech, and endgame projects.
7. `ProductionManager` applies domain-local tier dominance, caps native factory construction to sustainable domain targets, assigns unallocated `ArmyPool` T1 engineers to assist high-tier factories, directly queues emergency point defense only at unmanaged anchors, and establishes safe forward bases toward active objectives. It installs Red Queen counter and fortification builders into FAF's managers, keeping a single native unit-queue owner.
8. `CombatManager` continuously organizes available land, air, naval, and amphibious reinforcements around the selected objective, keeps only a small offensive reserve, and maintains T3 mobile garrisons at forward bases. Defensive objectives carry independent reachable land, water, amphibious, and air positions. Observed enemy layers decide where each task force intercepts, never whether it defends at all: any layer with a reachable destination is ordered, falling back to the threatened anchor, so a single-layer attack such as a pure air raid cannot leave the ground army idle in the `ArmyPool`. Transports remain outside combat waves and available to native transport and airdrop plans.
9. `TeamCoordinator` shares claims, proposals, and support state without giving any army centralized control.
10. `PingManager` converts allied human pings into expiring weighted requests.

The scheduler runs modules in a fixed insertion order with staggered tick intervals. Strategic progression does not branch on elapsed match time or external state, preserving simulation determinism.

## Information contract

Enemy unit observations originate from active, identified army-specific intel blips returned for proximity candidates around a bounded rotating set of friendly observers. Hidden proximity results and unidentified radar contacts are ignored; observed positions and blueprints come from the verified blip rather than the underlying enemy unit. Records decay and expire, and aggregate enemy technology is recomputed from only the surviving records. Directors may use enemy starting positions because they are fixed scenario/lobby information, but they do not enumerate enemy-brain units, inspect enemy economy, or enable omni vision.

## Hybrid boundary

The Red Queen owns match interpretation, intel memory, strategy, production demand, team intent, ping handling, and task-force orders. FAF remains responsible for engine integration, navigation mesh generation, build placement primitives, platoon APIs, and baseline adaptive builders. Observed targets become raids immediately; otherwise publicly known and pathable enemy starts become `Pressure` objectives. Economy recovery changes construction priorities but never parks existing combat units. A narrow behavior hook prevents Red Queen commanders from entering FAF's proactive overcharge routine until an enhancement has completed. This makes the mod immediately playable while allowing individual fallback systems to be replaced incrementally.

## Counter doctrine

The strategy director keeps deterministic two-minute windows of friendly mobile-land and air losses. Heavy land losses against observed surface forces with weak anti-air activate a three-minute gunship-production bias. Only aircraft losses recorded after that doctrine begins count toward deciding that the response is trading badly, and the measurement restarts every loss window, so the thresholds mean "this many losses inside one window" rather than "this many for as long as the doctrine holds". A failed response is abandoned for a bounded recovery period, while dominant observed air threat activates a fighter bias. These are native high-priority FAF factory builders, so they respect tech availability, power state, buildability, and normal economy conditions.

An observed economic target with no more than six local anti-air threat is considered a transport-harassment opportunity immediately. The director requests a bounded number of transports through FAF's existing transport and ghetto-raid machinery and sends available air attack units to the same exposed position. It does not inspect unobserved defenses.

## Strategic investment director

The production demand maintains deterministic 0–100 weights for `Army`, `Tech2`, `Tech3`, `Experimental`, and `Nuke`. Economy headroom, storage, trends, relevant factory-tier coverage, local danger, recent losses, observed enemy tech, target reachability, and observed strategic defenses all contribute. A focus changes only when a challenger leads by a configured score margin, so the AI remains stable without using match-age unlocks.

Native builder priority functions convert eligible weights into live priorities while ordinary adaptive production consumes the remaining capacity. Genuine stalls or immediate base danger prevent new strategic starts but do not stop existing units from attacking. Reachable shields and static defenses raise experimental weight; fortified or unreachable high-value targets raise nuke weight, while observed strategic missile defense suppresses it. One expensive project is allowed normally and two only with exceptional safe economic headroom. Started projects are not canceled when weights change.

## Tier dominance and defensive pressure

Factory tier access is evaluated independently for land, air, and naval production. Once a live factory reaches a higher tier, lower-tier mainline builders in that domain receive zero priority immediately and remaining lower factories continue upgrading. A lower-tier support role stays eligible only when the faction has no effective version of that role at an available higher tier. This preserves mobile shields, transports, artillery, torpedo aircraft, and other genuinely unique support units without allowing obsolete tanks, fighters, or ships to consume late-game queues. Sustainable total and per-domain factory targets suppress construction only for satisfied domains; a missing domain remains buildable even when the total is already occupied by the wrong mix. Domain relevance comes from live production demand alone, so an off-demand factory that already exists cannot ratchet the sustainable total upward. Red Queen's own factory expansion consumes the same targets rather than deriving a second mix, so it can never build into a domain the capacity policy has capped. Only unallocated T1 engineers in `ArmyPool` may assist active high-tier factories, and reclaimed engineers are forgotten without clearing their native orders.

Fresh observed mobile combat contacts are clustered deterministically by movement layer, so a ship's surface weapons cannot make its formation look like a land army. Every distinct formation is compared with friendly threat around its nearest typed anchor: commander, main base, expansion, naval base, or forward base. Anchor assignment stays geometric, but distances are compared in bounded proximity bands so that co-located anchors are separated by strategic criticality rather than by sub-metre noise; a commander standing inside its own base therefore wins its own assignment. Commander criticality depends on the victory mode, so a credible Assassination attack on the ACU outranks a larger remote formation. A massive relative concentration starts a defense alert; an approaching force can trigger at a lower threshold when recent mass-exchange momentum is unfavorable. The alert redirects new investment to army production, pauses new strategic-project starts without canceling work already underway, releases factory assistants, and gives emergency point defense, AA, shields, tactical missiles, and strategic missile defense top engineer priority. T1 point defense is the early fallback, UEF T3 sentries are preferred when available, and factions without a T3 point-defense equivalent use T2 point defense plus a larger T3 mobile garrison. Registered local fortification builders own managed bases; the direct deterministic queue is reserved for a threatened commander or other anchor outside every registered manager.

Forward bases use land-pathable defensive, expansion, and mass-cluster markers. A base starts only when the economy has positive trends, useful storage, no defense alert, and an observed-intel route from the selected engineer's actual position whose threat is supportable by its nearby escort. Bounded diagnostics report whether construction is blocked by objectives, alerts, engineers, economy, cooldown, cap, or site safety. The package scales with engineer tier and includes a factory, radar, point defense, AA, shields and artillery when available. Established bases remain valid only while both their expansion manager and a live self-owned local factory exist; losing either releases the marker for replacement and removes the site from garrison use. Released destroyed-base markers may bypass the normal minimum distance from the selected engineer, while pathing and route-threat checks still originate at that engineer. T2 tactical missile launchers and T3 strategic missile defense may be placed forward; strategic nuclear launchers remain rear-base investments. The number of forward bases scales from one to three with map size.

## Supported contract

- Standard UEF, Aeon, Cybran, and Seraphim units.
- Standard skirmish games using Assassination, Supremacy, or Annihilation.
- 5, 10, 20, and 40 km maps; 80 km is best-effort.
- Human or AI enemies, allied humans, and allied Red Queens.
- No campaign, Nomads, arbitrary unit mods, chat commands, or AIx lobby variants in v1.
