# Testing The Red Queen

## Fast checks

Run `./scripts/validate.sh` after every change. It validates metadata and registration paths, checks required source contracts, compiles the Lua sources with LuaJIT, and runs formula tests.

After an in-game run, summarize the log with:

```bash
./scripts/analyze-log.py "/path/to/game.log"
```

The analyzer fails on Red Queen errors and on engine Lua errors attributed to this mod by their source or traceback. Engine Lua errors it cannot attribute are reported as `Unattributed Lua failures` and do not fail the gate, including after defeat. Post-defeat counts are subsets of these totals: each occurrence is counted once. If it prints `Post-defeat Lua failures: not checked`, the log carried no recognizable defeat marker and the task-leak check did not run.

## In-game smoke test

Two prerequisites fail silently, so check both before reading any result.

- **The version bump changes the UID.** FAF keys mods by UID, so a bumped release
  is a different mod to the game: the previous lobby enable does not carry over,
  and a `RedQueenSmoke.prefs` still naming the old UID launches without the mod
  at all. The run then looks healthy while testing nothing.
- **Nothing else in `mods/` may declare The Red Queen.** A leftover
  `TheRedQueen.copy-*` directory beside the symlink registers as a second entry
  under its own UID. Move stale copies out of `mods/` entirely rather than
  relying on the UID differing.

1. Install the development symlink with `scripts/install-dev.sh`, then confirm
   `readlink -f` resolves to this checkout and that `mods/` holds no other Red
   Queen directory.
2. Enable **The Red Queen** in the lobby mod manager, re-ticking it after any
   version bump.
3. Start a 5 km 1v1 with fog of war enabled.
4. Confirm the lobby lists `AI: The Red Queen` and the game log contains `[RedQueen] started` without warnings or stack traces.
5. Repeat a 1v2 and confirm the startup log reports `deficit=1 income=1.10`.
6. In a non-stalled 1v1, confirm the first post-opening fallback is `objective=Pressure`, not repeated `Stage`/`Recover` oscillation.

For an isolated command-line check, make a copy of `Game.prefs` in FAF's preferences directory, name it `RedQueenSmoke.prefs`, and set its `active_mods` entry to:

```lua
active_mods = {
    ['7f4a8d2e-2d63-4e71-9c51-5ed0ee000008'] = true
}
```

FAF resolves `/prefs` names inside that directory, so pass the filename rather than an absolute path:

```bash
FAF_WRAPPER=/path/to/launchwrapper \
FAF_EXE=/path/to/ForgedAlliance.exe \
FAF_PREFS=RedQueenSmoke.prefs \
./scripts/run-smoke.sh SCMP_007 /tmp/the-red-queen-smoke.log
```

The runner passes `/init init_faf.lua`, because FAF's own init is the one that calls
`LoadVaultContent` and therefore mounts the vault `mods` directory. The bare
`init.lua` in the game's `bin` directory is whatever init the client configured
last: if that was a featured mod such as Nomads, it never mounts the vault and
The Red Queen cannot load at all. Override with `FAF_INIT=` only when testing a
featured mod deliberately. Confirm the log contains
`AddSearchPath: '...mods\theredqueen'` and the expected `vNN` UID before reading
any result.

The runner uses out-of-range difficulty `42` as an internal smoke-test marker, which redirects command-line Rush opponents to The Red Queen inside the simulation. Normal lobby sessions and stock Rush AIs are unchanged.

### What a short run cannot reach

A five-minute command-line smoke on a 10 km map reaches roughly `eco=Balanced`,
four factories, and `objective=Raid`. It exercises startup, income contracts,
tier policy, factory assistance, airdrop status, and forward-base rejection
reasons. It produces **zero defense alerts**, because no observed cluster reaches
`MassiveArmyThreat` before the armies meet.

Every check below that depends on a defense alert — layered land/water/amphibious
/air dispatch, anchor criticality, emergency point defense, alert-driven
production — therefore needs either a run long enough for contact, or a lobby
game where the threat is staged deliberately. A passing short smoke is not
evidence for any of them.

### Diagnostics reference

The periodic `state` line carries every director decision, so most behavioral
checks read it rather than the game UI:

```text
state objective=<type> eco=<mode> mass=<perTick> energy=<perTick>
      factories=<live>/<sustainableTarget> intel=<observations>
      doctrine=<Balanced|GunshipCounter|AirDefense> focus=<primary>
      weights=A=..,T2=..,T3=..,X=..,N=.. ready=<0..1> slots=<n> reason=<focus>
      landloss=<count>/<mass> airloss=<count>/<mass>
      airdrop=<None|Unavailable|Opportunity|Requested|Ready|TransportActive|Expired|Abandoned>
      alert=<yes|no>/<threat>/<ratio> momentum=<lost>/<destroyed>/<losing|stable>
      tiers=L<n>,A<n>,N<n> forward=<sites>/<building|idle>/<blockReason>
```

`factories=` compares live factories against the capacity policy's sustainable
target, not against `DesiredFactories`; `production expansion` logs the same
number. `mass=` and `energy=` are per tick, as below.

## Required match matrix

| Area | Required cases |
| --- | --- |
| Factions | UEF, Aeon, Cybran, Seraphim |
| Sizes | 5, 10, 20, 40 km |
| Terrain | Land, mixed, island, naval, generated |
| Teams | 1v1, 1v2, 2v3, 2v2 with allied Red Queen, FFA |
| Victory | Assassination, Supremacy, Annihilation |
| Duration | Opening, 30-minute performance run, strategic endgame |

For income verification, inspect mass/energy production rather than total economy trend. The expected multipliers are 1.0x for 1v1, 1.1x for 1v2, 1.2x for 1v3, and 1.1x for 2v3. Defeating an army must not change the multiplier.

## Ping behavior

- Attack ping: requests an assault if the destination is pathable and a defensive reserve remains.
- Move ping: requests staging or reinforcement.
- Alert ping: requests investigation or emergency defense.
- Marker ping: creates no Red Queen order.

Repeated pings may increase request priority, but pings must not cause an economy-dead AI to abandon recovery or send land units to an unreachable island.

## Counterplay behavior

- Destroy at least eight mobile land combat units inside two minutes while keeping observed anti-air low. Diagnostics should report `doctrine=GunshipCounter`, and the next buildable air-factory counter orders should favor gunships.
- Lose aircraft before Gunship Counter activates and confirm those prior losses do not cancel the new doctrine. Then, while Gunship Counter is active, destroy at least eight Red Queen combat aircraft or 450 mass of them **inside two minutes** and confirm the doctrine enters a bounded recovery period; dominant observed enemy air should select Air Defense during that period. Trickle the same total across more than two minutes and confirm the doctrine survives, because the measurement window restarts.
- Present dominant observed air threat. Diagnostics should change to `doctrine=AirDefense` and favor fighters.
- Leave an observed extractor, factory, power cluster, or engineer with local observed anti-air threat at or below six. The log should report `airdrop state=Requested`, `Ready`, `TransportActive`, `Expired`, or `Abandoned`; transport requests are capped at two existing transports and throttled to one request per 90 seconds. Hide and reveal the same target and confirm a terminal status returns to `Opportunity` or a live transport state.
- Check that new groups of at least three idle combat units leave the ArmyPool for the active objective, while land units are not ordered toward an unreachable water or island target.
- Replay the same economy, army, and intel snapshot at different match ages and confirm diagnostics report identical `weights=A=...,T2=...,T3=...,X=...,N=...`; elapsed time must not alter strategic focus.
- Give the AI sustainable headroom and missing relevant factory-tier coverage. Confirm T2/T3 weights enable upgrades without enemy contact, while an observed enemy tech advantage raises the corresponding weight. A genuine stall must disable new investments without changing an available attack into `Stage` or `Recover`.
- Present reachable shielded/static defenses and confirm experimental weight becomes eligible. Present fortified or unreachable high-value targets without strategic missile defense and confirm nuke weight becomes eligible; reveal missile defense and confirm nuke weight falls to zero.
- Confirm diagnostics report `focus`, `ready`, `slots`, and `reason`; normal economies allow one major-project start, while exceptional safe headroom may allow two. Started projects must continue if later evidence changes the focus.

## Mid- and late-game behavior

- Give one production domain a live T3 factory while retaining T1 and T2 factories. Confirm diagnostics change that domain to tier 3, lower mainline builders stop producing immediately, and lower factories continue upgrading. Destroy the T3 factory and confirm eligible lower-tier production resumes.
- Repeat with a faction-specific lower-tier support unit that has no effective T3 equivalent, such as a mobile shield or specialist air/artillery role. Confirm that support builder remains eligible while ordinary lower-tier combat builders remain disabled.
- Reveal a fresh enemy army whose observed threat is at least 1.25 times friendly threat around the nearest base or commander. Confirm a `defense alert started` event, a `Defend` objective, zero new experimental/nuke slots, and high-priority point defense, AA, shields, tactical missiles, and strategic missile defense. Existing strategic builds must not be canceled.
- Produce an unfavorable two-minute killed-versus-lost mass exchange, then reveal an approaching observed force above the pressure threshold. Confirm the lower-threshold approach path also starts the defense alert. Remove or stale the contacts and confirm the alert clears after its hold period.
- On UEF, verify T3 sentries are preferred. On Aeon, Cybran, and Seraphim, verify T2 point defense is backed by a larger T3 mobile garrison.
- Trigger an early alert with only T1 engineers and verify T1 point defense queues. Confirm MAIN and managed expansions use only the registered fortification builders, then move the ACU beyond every builder-manager radius and verify direct emergency point defense queues around the commander.
- On a shoreline base, reveal land units and ships whose blueprints expose surface threat but no sub threat. Confirm clustering follows movement layer: ordinary land defenders receive the land intercept while naval and amphibious defenders use reachable water/anchor positions.
- Raise a defense alert with air units only. Confirm the ground army still receives a `Defend` order onto the threatened anchor rather than remaining idle in `ArmyPool`, and that air defenders intercept at the observed formation. Repeat with a naval-only threat at a water anchor and confirm the ships are ordered.
- Park the ACU inside MAIN and reveal a threat. Confirm the alert reports `anchor=Commander`, not an arbitrary alternation between `Commander` and `MainBase` as the ACU drifts a few ogrids.
- In Assassination, confirm a credible ACU attack outranks a larger remote formation. Repeat with Annihilation and verify the log retains `victory=Annihilation` rather than collapsing it into Supremacy.
- Reach the sustainable factory total with the wrong mix and confirm the missing production domain remains buildable while satisfied domains stay capped. Confirm `production expansion` never names a domain the capacity policy has capped, and that its `desired=` matches the `factories=N/M` total in the `state` line. Build one factory in a domain whose production demand is below 10% and confirm the sustainable total does not rise. Verify only unallocated `ArmyPool` T1 engineers assist active highest-tier factories, that native-managed engineers are never claimed, and that assistants release immediately when a defense alert begins without clearing an engineer reclaimed by native management.
- With positive economy trends, at least 10% storage, an idle engineer, an active forward objective, and a safe observed route, confirm `forward base started` then `forward base established`. Verify its package contains a factory, radar, defense, AA, and tier-appropriate shield/artillery; T2 tactical missiles and T3 strategic missile defense may appear, but no T3 strategic missile launcher is queued there.
- Reveal sufficient route threat or start a defense alert and confirm no new forward base begins, and that `forward=<sites>/<state>/<reason>` in the `state` line names the blocking reason. Verify the base cap is one on 5 km maps, two on 20 km maps, and three on 40 km maps.

## Performance gate

Run eight Red Queens on the same 20 km generated map for at least 30 simulated minutes, then repeat with stock Adaptive AIs. Reject a release that logs scheduler failures, desynchronizes, leaks recurring tasks after defeat, or has median simulation performance more than 15% below the stock run on the same machine.
