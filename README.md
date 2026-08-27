# The Red Queen

The Red Queen is an adaptive skirmish AI for Supreme Commander: Forged Alliance Forever, delivered as a simulation mod. Release `V8` combines FAF's maintained Adaptive AI machinery with deterministic, observed-intel strategy for counterplay, tier-aware production, emergency defense, forward bases, coordinated combat, and allied support.

It appears in the lobby as `AI: The Red Queen` and supports the four standard FAF factions.

## Feature set

### Observed-intel strategy

- Samples active, identified visual, radar, sonar, and omni blips around a bounded rotating set of friendly observers.
- Ignores hidden proximity results and unidentified contacts instead of reading exact enemy state.
- Decays and expires sightings; aggregate enemy technology falls when advanced contacts become stale.
- Scores exposed economic targets against observed surface and anti-air threats.
- Evaluates every fresh enemy army cluster against friendly strength around its nearest owned base or commander.
- Chooses immediate raid, pressure, defense, reinforcement, investigation, and allied-support objectives without match-time unlock gates.
- Maintains live weights for army production, T2, T3, experimentals, and nuclear investment using economy, battlefield, map, and observed-enemy evidence.
- Favors experimentals against reachable fortifications and nuclear siege against unreachable high-value targets, while observed strategic missile defense suppresses nuclear investment.

### Counter-production and tier dominance

- Biases air production toward gunships after sustained land losses when observed anti-air is weak.
- Abandons a badly trading gunship response for a bounded recovery period instead of feeding the same counter indefinitely.
- Biases production toward fighters when observed enemy air threat dominates.
- Requests bounded transport harassment against exposed observed economy through FAF's native transport machinery.
- Evaluates land, air, and naval factory tiers independently.
- Stops lower-tier mainline production as soon as a higher-tier factory is available in that domain, while lower factories continue upgrading.
- Preserves lower-tier auxiliary roles only when no effective higher-tier equivalent exists, including mobile shields, transports, artillery, torpedo aircraft, and specialist air roles.
- Restores lower-tier production if higher-tier access is lost.
- Caps native factory construction to sustainable per-domain targets while leaving missing domains buildable, and shares those same targets with its own factory expansion, then assigns only unallocated `ArmyPool` T1 engineers to assist active high-tier factories.

### Army alerts and layered defense

- Recognizes massive relative enemy formations and smaller approaching armies during an unfavorable recent mass exchange.
- Keeps land and naval invasion threat distinct and scores typed commander, main-base, expansion, naval-base, and forward-base anchors by strategic criticality.
- Treats credible ACU attacks as absolute emergencies in Assassination and preserves separate Annihilation threat semantics.
- Measures defensive strength at the threatened base or commander rather than at the enemy formation.
- Redirects production toward immediate army needs and pauses new experimental or nuclear starts without canceling projects already underway.
- Gives local engineers high-priority point defense, anti-air, shields, tactical missiles, and strategic missile defense.
- Adds T1 point-defense fallback and direct commander-centered construction only when no registered builder manager covers the threatened position.
- Prefers UEF T3 sentries; factions without a T3 point-defense equivalent use T2 point defense backed by a larger T3 mobile garrison.
- Scopes engineer-tier fallback to the threatened base, so a remote T3 engineer cannot suppress eligible T2 defenses at an expansion.
- Gives land, naval, amphibious, and air defenders independent reachable destinations, and orders every layer that has one, so neither a shoreline base under land invasion nor a base under a pure air raid leaves an idle task force behind.

### Defended forward bases

- Selects defensive, expansion, and mass-cluster markers toward the active objective.
- Checks land pathing and observed route threat from the selected engineer's actual position and compares it with nearby escort strength.
- Requires positive economy trends, useful storage, no active defense alert, and a safe route before construction begins.
- Builds a tier-scaled package with a factory, radar, point defense, anti-air, shields, artillery, tactical missiles, and strategic missile defense where available. Strategic nuclear launchers remain rear-base investments.
- Maintains T3 mobile garrisons at viable forward bases; transports are excluded from combat waves and garrison duty so FAF's transport plans can use them.
- Revalidates established bases against their expansion manager and a live self-owned factory. Destroyed, captured, or unmanaged bases release their garrisons, map-cap slot, and marker claim.
- Allows a surviving engineer to rebuild a released destroyed-base marker without weakening engineer-origin pathing or route-safety checks.
- Scales the forward-base cap from one to three with map size.
- Reports bounded rejection reasons when a forward base cannot start.

### Continuous combat and team play

- Retains FAF's Adaptive AI builder managers, navigation, placement, reclaim, and platoon machinery while Red Queen directors control strategy, production demand, and task-force objectives.
- Continuously sends available land, air, naval, and amphibious reinforcements toward the current objective while retaining only a small offensive reserve.
- Leaves transports available for native transport and airdrop behavior instead of order-locking them into ordinary air waves.
- Keeps commanders out of FAF's proactive overcharge routine until an enhancement has completed.
- Coordinates expansion claims, attack proposals, and support state with allied Red Queens without centralizing control.
- Proactively transfers surplus mass or energy to allies in economic distress.
- Treats allied attack, move, and alert pings as expiring weighted requests.
- Supports Assassination, Supremacy, and Annihilation strategy goals.

## Income scaling

Each Red Queen locks an income-only multiplier at match start:

```text
army deficit      = max(0, hostile armies - allied-side armies)
income multiplier = 1 + 0.10 * army deficit
```

The allied-side count includes the Red Queen itself. Civilian and neutral armies are excluded. The multiplier has no artificial cap and does not change when an army is defeated. Only mass and energy production are affected; build rate, intel range, and combat statistics remain unchanged.

| Match | Multiplier |
| --- | ---: |
| 1v1 | 1.0x |
| 1v2 | 1.1x |
| 1v3 | 1.2x |
| 2v3 | 1.1x |

## Supported scope

- UEF, Aeon, Cybran, and Seraphim standard units.
- Assassination, Supremacy, and Annihilation skirmishes.
- 5, 10, 20, and 40 km maps; 80 km maps are best-effort.
- Land, mixed, island, naval, and generated maps.
- Human or AI enemies, allied humans, and allied Red Queens.

Campaigns, Nomads, arbitrary unit mods, chat commands, and AIx lobby variants are outside the current supported contract.

## Development installation

FAF imports this mod through the absolute path `/mods/TheRedQueen/`, so the active game directory must be a symbolic link named `TheRedQueen` that resolves to this checkout.

```bash
./scripts/install-dev.sh "/path/to/Supreme Commander Forged Alliance/mods"
test -L "/path/to/Supreme Commander Forged Alliance/mods/TheRedQueen"
readlink -f "/path/to/Supreme Commander Forged Alliance/mods/TheRedQueen"
```

Enable **The Red Queen** in the FAF lobby mod manager, then select `AI: The Red Queen` in an AI slot.

## Validation

Run the required fast gate after every change:

```bash
./scripts/validate.sh
```

It validates metadata, registration and structural contracts, compiles every Lua source with LuaJIT, and runs the formula, commander-safety, combat, counter-builder, economy, fortification, income, intel, production, strategy, and world-model contract suites.

Runtime changes also require an installed in-game smoke test and log analysis:

```bash
FAF_WRAPPER=/path/to/launchwrapper \
FAF_EXE=/path/to/ForgedAlliance.exe \
FAF_PREFS=RedQueenSmoke.prefs \
./scripts/run-smoke.sh SCMP_007 /tmp/the-red-queen-smoke.log

./scripts/analyze-log.py /tmp/the-red-queen-smoke.log
```

The command-line smoke proves initialization and catches startup or scheduler failures; it does not prove midgame decisions, full-match balance, multiplayer synchronization, or target playing strength. See [docs/testing.md](docs/testing.md) for preferences setup, behavioral checks, and the broader faction, terrain, team, victory, duration, and performance matrix.

## Project status

The Red Queen is a playable development release with contract coverage for its core strategic behavior. Release `V8` passes the fast gate and a command-line startup smoke; its layered defensive dispatch, counter-doctrine recovery, and anchor criticality have contract coverage but no runtime evidence yet, because a short smoke never reaches a defense alert. Its stated 1000–1300 strength target still requires replay-driven tuning and human beta evidence and is not inferred from source validation or startup smoke results.
