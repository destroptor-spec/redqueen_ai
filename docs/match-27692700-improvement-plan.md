# Match 27692700 Improvement Plan

## Evidence

The 28-minute Adaptive Seton's Clutch V7 match exposed a gap between strategic
recognition and execution. Both Red Queens raised defense alerts, but Priscilla
was defeated near minute 18 and Blacklisted near minute 28.

- Actual factories reached 22 while the economic target was 2.
- The two AIs built 278 engineers and lost 276 of them.
- Structures recorded only 3 and 4 kills despite sustained defense alerts.
- Air production built 242 units, lost 232, and recorded 79 kills.
- T2 and T3 units recorded no kills.
- A naval classification produced only 18 naval units across both AIs.
- No forward base was attempted or established.
- Four transports were built and lost without a recorded kill.
- Post-defeat native manager and platoon Lua failures were not reported by the
  log analyzer.

The lobby used raw victory condition `demoralization`, which is Assassination.
Both defeats followed ACU-kill warnings. The design must also preserve the
distinct meaning of Annihilation (`eradication`) for future matches.

## Implementation Plan

### 1. Critical anchors and defensive mobilization

- Represent protected locations as records with position, kind, layer,
  manager name, and criticality instead of anonymous positions.
- Preserve Assassination, Supremacy, and Annihilation as distinct match modes.
- Treat a credible ACU attack as an absolute emergency in Assassination and as
  a high, state-dependent threat in Annihilation and Supremacy.
- Keep land and naval enemy threat separate when clustering armies.
- Give land, amphibious, naval, and air defenders independent reachable
  destinations rather than deriving one layer from a shoreline anchor.

Acceptance: tests prove that a smaller ACU-threatening army outranks a larger
non-critical formation, Annihilation remains distinguishable, and land units
remain eligible against land forces threatening a water-adjacent base.

### 2. Emergency construction and build power

- Add a T1 point-defense fallback when no local T2 or T3 engineer is available.
- Allow emergency defense around a commander even when it is not colocated
  with an existing builder manager.
- Reserve and redirect suitable engineers to the threatened anchor.
- Suppress native factory construction when the sustainable per-domain or
  total factory target is already met.
- Prefer assisting active highest-tier factories over adding factory shells;
  scale assistant targets with income and release assistants during stalls or
  emergency construction.

Acceptance: contracts cover T1 fallback, commander-centered defense, hard
factory caps, deterministic assistant selection, and emergency release.

### 3. Counter effectiveness and feature observability

- End Gunship Counter early when recent air losses show that the response is
  trading badly, and transition to Air Defense when enemy air is dominant.
- Log forward-base rejection reasons at a bounded cadence.
- Log airdrop requests and whether a transport-backed opportunity remains
  pending, launches, expires, or is abandoned.
- Log emergency defense demand and factory-assistant assignments.

Acceptance: contracts cover doctrine reversal; runtime diagnostics expose why
forward bases, airdrops, defenses, and factory assistance did or did not run.

### 4. Diagnostics and verification

- Report engine Lua errors that occur during or immediately after Red Queen
  teardown, while distinguishing them from Red Queen scheduler failures.
- Extend structural validation and pure Lua contracts for the new invariants.
- Run `./scripts/validate.sh`, verify the active development symlink, run the
  command-line V7 smoke, and analyze its log.

The smoke test proves initialization and scheduler safety only. A repeat
full-length Assassination match and a separate Annihilation match remain the
behavioral acceptance tests.

## Execution Status — 2026-08-27

- Critical anchors, distinct victory modes, and split defensive layers are
  implemented with pure contract coverage.
- T1 commander-centered point defense, sustainable factory caps, and
  income-scaled factory assistance are implemented. Assistants are released
  when demand falls, the economy stalls, or emergency defense activates.
- Gunship-counter recovery, airdrop state, forward-base blockers, air-loss
  pressure, and emergency construction now have bounded diagnostics.
- The analyzer now reports all engine Lua failures and identifies post-defeat
  failures and invalid manager locations separately.
- `./scripts/validate.sh` passes all 11 contract suites and structural checks.
- The copied FAF installation was preserved as `TheRedQueen.copy-20260827` and
  replaced with a verified `mods/TheRedQueen` symlink to this checkout.
- The first V7 smoke exposed an invalid `T1EngineerBuilder` template. It was
  corrected to FAF's registered `EngineerBuilder` template and protected by a
  contract plus structural validation.
- The corrected five-brain V7 smoke started all brains and reported zero
  engine Lua failures, post-defeat failures, invalid manager locations, and
  potential failures.

The repeat full-length Assassination and Annihilation matches remain pending;
they are gameplay acceptance tests, not part of the command-line smoke.

## Review Fix Plan — 2026-08-27

The first implementation review identified six engine-facing cases that the
initial contracts did not reproduce accurately:

1. Bucket mobile army threat by the observed unit's movement layer so ships
   with surface weapons remain naval formations.
2. Keep a missing factory domain buildable even when the total factory target
   has already been reached with the wrong domain mix.
3. Assign factory assistance only to engineers that are currently in
   `ArmyPool`, and never clear a stale assistant order after native management
   has reclaimed the engineer.
4. Use direct emergency construction only where no registered local engineer
   manager can run the emergency fortification builders.
5. Count air losses against `GunshipCounter` only after that doctrine starts.
6. Reactivate a terminal airdrop status when the same observed target returns.

Each correction requires a reproducing pure contract. Completion also
requires the full validation gate, a verified development symlink, and a clean
five-brain V7 smoke analysis.
