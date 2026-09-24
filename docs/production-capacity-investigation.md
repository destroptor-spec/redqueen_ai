# Production capacity investigation — 2026-09-06

## Outcome

The passive reproduction reached **one counted factory against a target of
seven** at 782.2 simulation seconds. Sixteen direct expansion requests returned
success. None produced an observed additional factory completion. This is
evidence of an execution failure after request acceptance, not evidence that
the capacity target is too low.

The suggested engineer-production explanation is not supported as the sole
cause in this reproduction: the initial land factory completed ten engineers.
The trace instead exposes native engineer-task ownership and a concrete
coordinate-contract mismatch in the direct expansion path. No production
priorities, ownership rules, orders or placement behavior were changed for
this investigation. Existing uncommitted calibration and behavior work was
retained, not treated as part of the instrumentation patch.

## Reproduction and provenance

- Checkout: `ai/v8-execution-fixes`, HEAD
  `581d2a26c1d774ba707734eb415e090c271d92f9`, plus the working changes.
- Both before launch and after the run, the active `mods/TheRedQueen` was a
  symbolic link resolving to `/var/home/andreas/VS Code/TheRedQueen`.
- Map: `sweepwing_sanctum.v0003` (Sweepwing Sanctum). Red Queen: army 2, Aeon;
  stock Adaptive: army 3. Victory: Assassination.
- Opt-in sentinel 43 reproduces the prior mixed command-line setup. Additional
  starts remain present: startup logs `allies=1 enemies=3 deficit=2 income=1.20`.
  **This is not a strict 1v1, nor an exact replay of the earlier Cybran run.**
- FAF game 3839, commit `36701ed9e184818bc264ec0b325676356c1ed743`;
  client 2026.7.0; Red Queen V8 / enabled UID ending `000008`.
- Log: `/tmp/rq-production-trace-20260906-2.log`.
  Last periodic game-time marker: 13:06. Stopped deliberately after a sustained
  deficit and repeated requests; not a completed match or balance test.
- Working snapshot at launch: `/tmp/rq-production-trace-20260906-2.patch`.
  Documentation and analyzer tests were subsequently refined; runtime Lua was
  unchanged during the successful run and subsequent analysis.
- Runtime payload SHA-256:
  `43cc1615612aa5ef229f4e93d925006db7a60f83c47b4ec205eaba4e50214482`.
  Computed from sorted `sha256sum` records for all tracked/untracked,
  non-ignored files under `mod_info.lua`, `hook`, and `lua`.
- Log SHA-256:
  `9ff410bec47283bdb5d70a3ad6558b8ffd45059750aa04860a8737ac749f91f5`.
- Launch snapshot SHA-256:
  `d1ab1aad3a87c86c42967f6d18f155b17ce7776d3f2bb2504165bcd28504f0a4`.

```bash
timeout --signal=TERM --kill-after=10s 1900s env FAF_PRODUCTION_TRACE=1 \
FAF_WRAPPER=/var/home/andreas/faf-linux/launchwrapper \
FAF_EXE=/var/home/andreas/.faforever/bin/ForgedAlliance.exe \
FAF_PREFS=RedQueenSmoke.prefs \
./scripts/run-smoke.sh sweepwing_sanctum.v0003 /tmp/rq-production-trace-20260906-2.log

./scripts/analyze-log.py /tmp/rq-production-trace-20260906-2.log
python3 scripts/analyze-production-trace.py /tmp/rq-production-trace-20260906-2.log
```

The first attempted trace launch, `/tmp/rq-production-trace-20260906.log`, is
invalid evidence: FAF Lua 5.0 rejected a modern vararg expression. The observer
was corrected to use the engine's implicit `arg` table and relaunched. Contract
tests emulate that language feature in LuaJIT. Only the `-2` log is analyzed here.

## What the trace measured

### Engineers exist; native managers continue assigning them

The land factory selected `T1 Engineer Disband - Init` nine times and
`T1 Engineer Power` once. Ten engineer completion callbacks were observed from
50.1s through 536.2s. Red Queen's 955–980 combat builders in
`CounterBuilders.lua` are **Air** builders, not competitors for this land
factory. Later T2 land combat selections do not establish that an unevaluated
engineer candidate would have been eligible.

The original four engineers were not all stuck in one unknown owner:

- `1048579`: native `EngineerBuildAI`, principally `T1ResourceEngineer 150`,
  with moves toward distant mass sites. Lost at 425.9s; the ID was reused by a
  replacement completed at 459.6s. These are separate lifetimes.
- `1048582`: native power and mass builders, with frequent reassignment and
  periods without a current platoon. Direct expansion reservations did not
  stop native task assignment.
- `1048585`: native `StateMachineAI` / `T1 Engineer Reclaim`, moving between
  sampled positions until its loss at 450.3s.
- `1048588`: native mass/power builders, lost at 415.7s; a replacement later
  entered the Red Queen forward-base flow. Other replacement engineers were
  assigned native vacant-start expansion plans.

### Accepted requests do not become added capacity

| Time | Measured event | Log line |
| --- | --- | --- |
| 36.8s | Opening land factory completes at `(127.5,156.5)`. | 290 |
| 242.2s | Request 1 accepted behind a mass-extractor queue entry; count/target `1/3`. | 556–565 |
| 302.2s | Request 3 queues `uab0101` at `(21,30)` on engineer `1048588`. | 663 |
| 302.3s | Native manager assigns that same engineer `T1ResourceEngineer 150`; factory entry is still present at assignment. | 675 |
| 332.2s | Request 3's entry is absent; the engineer's head entry is now a mass extractor. Request 4 queues another factory at `(21,30)`. | 730–739 |
| 332.3s | Request 4's engineer is likewise assigned the native mass builder. | 741 |
| 642.2s | Request 14 queues an air factory at `(29,16)`. | 1748 |
| 670.2s | A T2 factory completion callback comes from the original factory at the original position: an upgrade, not a second production site. | 1831 |
| 782.2s | Mass income is `5.16` per tick (`51.6/sec`), count/target `1/7`; request 16's entry is absent. | 2224–2228 |

Of the sixteen requests, fourteen were last observed as `queue-absent`; two
ended with their engineer's death. Entry disappearance is **not** a recorded
cancellation reason or completion. Some requests were appended behind active
native builds; the trace identifies entries by object identity, not just by
queue length or blueprint.

Only two factory completion callbacks occurred: the opening factory and its
T2 upgrade. `CountFactories` includes unfinished entities, so a transient
count of two is not proof of two operational factories. A separate forward-base
factory was lost at 781.1s without an observed completion callback. The direct
requests must not be credited with that independent forward-base attempt.

## Source corroboration and remaining uncertainty

The installed native source was read from
`/var/home/andreas/.faforever/gamedata/lua.nx2`, not guessed from API names.

1. `ProductionManager.lua` passes unshifted `BaseTemplates.BaseTemplates` to
   `ExecuteBuildStructure`, whose `relative` argument is hard-coded `false`.
   Native `lua/basetemplates.lua` generates these positions around `(0,0)`.
2. Native `lua/AI/aibuildstructures.lua:AIExecuteBuildStructure` only adds the
   engineer-manager/base position when `relative` is true. Native
   `lua/platoon.lua:EngineerBuildAI` uses `relative=true` for this ordinary
   unshifted-template case; its absolute-template branches shift the template
   before passing false. This is a verified call-contract mismatch.
3. A read-only LuaJIT probe executed the installed `AIExecuteBuildStructure`
   function with an explicitly stubbed `FindPlaceToBuild` result `(21,30)` and
   origin `(127.5,156.5)`. False queued `(21,30)`; true queued `(148.5,186.5)`.
   This confirms the Lua conversion, **not** the engine placement search or a
   successful construction after a fix. The live trace supplies the actual
   near-origin queue observations.
4. Native `EngineerManager:AssignEngineerTask` does not inspect
   `RedQueenProductionBuildUntil`. The trace records new native assignments
   one tick after requests 3 and 4 while those reservations were active.
   `EngineerBuildAI` clears engine orders on entry; `ProcessBuildCommand` can
   also remove entries when safe movement fails. Both are relevant code paths,
   but this trace does not instrument the exact clear/removal that affected
   each request. Do not label all fourteen missing entries as order clobbering.

For source provenance, SHA-256 of the extracted native files:

- `lua/AI/aibuildstructures.lua`:
  `b0142530cc7190106187af9bf648a53fe66eb8529062f02a0e0c3000e15f8141`.
- `lua/platoon.lua`:
  `c6c107aa4a4a7e8ccab6fd4a12e1ce5a5ffc2ffcbd8de9b009c5032eb3e5a9cc`.

The normal analyzer reports zero attributed Red Queen Lua/scheduler failures
and one unattributed native `GetBuildLocation` arithmetic failure around 62s
(log lines 309–312). Its traceback contains no army identity or Red Queen frame;
it precedes the first direct expansion request. Its effect is unknown, so this
is not a clean engine-error-free run. No `production trace unavailable` occurred.

## Smallest justified next experiment

Correct **only the direct capacity request's relative-coordinate contract** in
a separately authorized behavior patch. Make the helper's coordinate mode
explicit; preserve false for callers that already shift their templates to a
fortification/forward-base site. Do not globally flip the shared helper.

Test both unshifted and pre-positioned templates, then rerun with the same map,
faction, army configuration and income multiplier. Record the requested
factory entry's own position even when it is behind another queue entry, the
first construction start, progress and completion. Success means an additional
completed factory and capacity following demand, not `accepted=true`.

If near-base requests still disappear, trace command clearing and
`ProcessBuildCommand` removal reasons for those requests before changing native
engineer ownership. The measured immediate reassignment justifies that probe;
it does not justify raising engineer priorities or clearing native task flags
speculatively. Broader priority tuning and strict-1v1 balance remain untested.

## Validation

`./scripts/validate.sh` and `git diff --check` pass. Passive-observer contracts
cover unchanged native selection/condition/random/order call counts, nil-bearing
return tuples, opt-in activation, manager replacement/cleanup, skipped candidate
eligibility, and request disappearance versus completion. Analyzer tests cover
quoted fields, army separation, reused engineer IDs and terminal request counts.
The successful runtime verified the FAF dialect and produced the evidence
above; it does **not** establish that the capacity regression has been fixed.
