# Review corrections verified on 2026-09-10

All nine review findings have implementation changes and targeted regressions.
Existing working-tree changes were retained. These checks establish the corrected
contracts and bounded runtime execution; they do not establish match balance.

| Finding | Correction | Regression |
| --- | --- | --- |
| Native engineer recall | Mark retreat ownership before disband, cancel assignment threads created before and during disband, and defer native assignment until arrival at home. Forward engineer selection respects the hold. | `engineer_recall_spec.lua`, `production_manager_spec.lua`; installed FAF disband/task methods also exercised. |
| Repeated fallback scouting | Retain destination reservations across passes and pool changes; allow only one outstanding combat fallback. Dead or expired assignments release reservations. | `combat_manager_spec.lua`: six repeated passes, changed objective, dedicated scout in transit, pool removal, death, expiry. |
| Factory engineer tier | Read every squad after the native name and plan header; reject lower-tier engineers in any squad. | `factory_tier_spec.lua`: native three-entry layout, mixed squads, captured factories, stock AI and native refusal. |
| Empty terrain coverage | Record recent positions within friendly observers' vision separately from enemy contacts; decay and prune these samples. | `intel_manager_spec.lua`: empty visit, vision boundary, departure, expiry, dead observer, revisit, unchanged threat. |
| Experimental concurrency under alert | Clamp the additional allowance while retaining the owned count. | `strategy_director_spec.lua`: two/four owned experimentals with funded and taxed concurrency. |
| Factions on proximity teams | Share `TeamLayout.ProximityTeams` between simulation and the generated launcher; read the scenario's start markers before faction selection. | `prepare_runtime_spec.py`, `team_layout_spec.lua`: Saltrock geometry, both human-slot modes, reordered starts, missing markers and undersized layouts. |
| Result attribution | Filter lifecycle results by the same army index selected for statistics. | `summarize_matrix_spec.py`: opposing results in either order and missing selected-army result. |
| Emergency cover reporting | Initialize cover counts to zero before early returns. | `combat_manager_spec.lua`: defense release and absent pool. |
| Allied income reporting | Use each ally's established Red Queen context; omit unverified income. | `redqueen_brain_spec.lua`: own 1.20, stock ally without income, another established 1.10 context. |

The following checks passed:

```text
./scripts/validate.sh
git diff --check
python3 scripts/check-hook-targets.py /home/andreas/.faforever/gamedata/lua.nx2
python3 scripts/check-native-engineer-recall.py /home/andreas/.faforever/gamedata/lua.nx2
python3 scripts/check-native-placement.py /home/andreas/.faforever/gamedata/lua.nx2
```

The native recall check uses installed `PlatoonDisband`, `TaskFinished`,
`ForkEngineerTask`, `DelayAssign`, and `Wait` with movement and final assignment
stubbed. It preserves the return order through 1,000 ticks of native retries,
then permits native work after arrival. The hook check validated seven captures.

Two simultaneous Saltrock (`SCMP_025`, seed `8675309`) smoke runs used dedicated
`RQTest1.prefs` and `RQTest2.prefs`. The mod symlink and active UID were verified.
Both manifests have payload
`c3570d0e4fb274c2aa0e9beb91e8c4c3c28e1690faacec5e11b6a5bddf50d434`;
every recorded source hash matched the working tree after the runs.

| Smoke | Runtime confirmation | Log analysis |
| --- | --- | --- |
| Mixed 2v2, human slot retained, UEF/Cybran | Red Queen ARMY_2 and ARMY_5 both faction 1; opponents ARMY_3 and ARMY_6 both faction 3; `allies=2 enemies=2 deficit=0 income=1.00`. | 36 state samples, last session-time report at simulation 16:24; zero attributed Red Queen Lua/scheduler failures; one native FAF error. |
| 2v2v2, no human, Aeon/Cybran | ARMY_1 faction 2 reports `income=1.20`; stock ally ARMY_4 faction 3 has no income field; `allies=2 enemies=4 deficit=2 income=1.20`. | 18 state samples, last session-time report at simulation 16:18; zero attributed Red Queen Lua/scheduler failures; two native FAF errors. |

Artifacts are under `/tmp/rq-review-fixes-smoke-live/`: `mixed2.log` and
`2v2v2.log`, their manifests, launch overlays, patches, `.analysis.txt` reports,
and `results.json`. Both runs were capped after 120 wall-clock seconds. Cleanup
used pidfd signals only for executable command lines containing `/redqueen` and
the exact corresponding `/log` path; no FAF processes remained afterward.

Both logs contain a native `aiutilities.lua:GetBuildLocation` nil-arithmetic
failure; the 2v2v2 log additionally contains a native `platoon.lua` missing
`PlatoonDisband` method failure. Neither traceback identifies Red Queen, so the
analyzer retains these as unattributed errors. The runs are unfinished samples,
not victories or clean end-to-end acceptance. Experimental starts and all nine
mechanisms were not individually proven in-game; no full balance matrix ran.
