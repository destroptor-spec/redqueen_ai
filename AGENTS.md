# Repository Guidelines

## Project Structure & Module Organization

`mod_info.lua` defines the FAF simulation mod. `lua/AI/RedQueenBrain.lua` is the brain entry point, while focused systems live under `lua/AI/RedQueen/` (intel, economy, production, strategy, combat, team coordination, and diagnostics). Lobby registration and tooltips are in `lua/AI/CustomAIs_v2/` and `lua/AI/LobbyTooltips/`. Engine-safe extensions belong under `hook/`; keep hooks additive and narrowly scoped. Pure contract tests live in `tests/`, developer utilities in `scripts/`, and design/runtime notes in `docs/`.

## Build, Test, and Development Commands

- `./scripts/validate.sh` — required fast gate; validates metadata/imports, compiles every Lua file with LuaJIT, and runs contract tests.
- `./scripts/install-dev.sh "/path/to/.../mods"` — installs a development symlink named `TheRedQueen`, which is required by absolute mod imports.
- `./scripts/analyze-log.py /path/to/game.log` — summarizes Red Queen startup, income contracts, diagnostics, and failures.
- `FAF_WRAPPER=... FAF_EXE=... FAF_PREFS=RedQueenSmoke.prefs ./scripts/run-smoke.sh SCMP_007` — launches the isolated command-line smoke test. Follow `docs/testing.md` when preparing the preferences file.

## Runtime Test Harness

Behavioural claims about this AI come from matches, not from the contract suite. The values below are the verified layout on the development machine; re-verify them rather than assuming them if any path moves.

| What | Path |
| --- | --- |
| Active mod symlink | `/var/home/andreas/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/TheRedQueen` |
| Preferences directory | `/var/home/andreas/faf-linux/prefix/drive_c/users/steamuser/AppData/Local/Gas Powered Games/Supreme Commander Forged Alliance` |
| Game binary | `/home/andreas/.faforever/bin/ForgedAlliance.exe` |
| Launch wrapper | `/var/home/andreas/faf-linux/launchwrapper` |
| Blueprint archive | `/home/andreas/.faforever/gamedata/units.nx2` (extracted to `/tmp/faunits/units`) |

`/prefs` resolves **relative to the preferences directory**, so it takes a bare filename and never an absolute path. Never point a test at `Game.prefs`: the FAF client rewrites it and has silently dropped `active_mods`, which produces a full-length run with zero Red Queen output. Use the per-slot `RQTest<1-6>.prefs` files instead.

### Pre-flight

Run all four checks before interpreting any match. Each has produced a wasted or misleading run at least once.

```bash
# 1. The active mod must be a symlink into this checkout, not a copy or a stale payload.
M="/var/home/andreas/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/TheRedQueen"
[[ -L "$M" && "$(readlink -f -- "$M")" == "$(pwd -P)" ]] && echo OK || echo MISMATCH

# 2. The slot preferences must still activate the mod; compare against mod_info.lua.
D="/var/home/andreas/faf-linux/prefix/drive_c/users/steamuser/AppData/Local/Gas Powered Games/Supreme Commander Forged Alliance"
grep -n "uid" mod_info.lua
for i in 1 2 3 4; do grep -A3 active_mods "$D/RQTest$i.prefs" | head -4; done

# 3. Identify the user's live game positively, and never terminate it.
for p in $(ps -eo pid,comm | awk '$2 ~ /^ForgedAlliance/ {print $1}'); do
    cl=$(tr '\0' ' ' < /proc/$p/cmdline)
    [[ "$cl" == *"/gpgnet"* ]] && echo "LIVE USER GAME pid=$p" || echo "test pid=$p"
done

# 4. The contract gate must be green before a run is worth launching.
./scripts/validate.sh
```

Match processes on their **name** via `ps -eo pid,comm`, never with `pkill -f`: a `pkill -f ForgedAlliance` matches this session's own command line — which carries `FAF_EXE=.../ForgedAlliance.exe` — and kills the shell. Only ever terminate a process whose command line contains both `/redqueen` and the test log prefix.

### Launching

```bash
./scripts/run-matrix.sh <slot> <map> <seed> <rq_faction> <opp_faction> <label>
```

Run **two cells at a time**. Four ran fine for short naval matches, but on the
large maps a long match grows well past its 0.6 GiB starting resident size and
four instances exhausted memory on a 30 GiB machine — the runs were killed
mid-match and produced no result at all, which is worse than running them
serially. Check `free -h` before launching and prefer two long runs to four that
may not finish. Each cell uses its own preferences slot. `FAF_SEED`, `FAF_RQ_FACTION` and `FAF_OPP_FACTION` are the variety knobs; `FAF_FIXED_RUNTIME=1` pins factions and raises game speed, and `FAF_MIXED=1` selects a strict 1v1. Faction indices are 1 UEF, 2 Aeon, 3 Cybran, 4 Seraphim. `run-smoke.sh` picks a `/diff` sentinel from these variables: 42 all-Red Queen, 43 mixed with production tracing, 44 mixed 1v1, 45 2v2, 46 2v2 traced, 47 lifecycle fixture, 48 defense fixture. Leave `FAF_PRODUCTION_TRACE=1` off for balance runs — it has exhausted Wine's address space and crashed a match.

The reference map set, with the profile each selects:

| Map | Id | Profile |
| --- | --- | --- |
| Sludge | `SCMP_037` | Naval (5 km, 93% water) |
| Sentry Point | `SCMP_018` | LandSmall |
| Fields of Isis | `SCMP_015` | LandLarge |
| Syrtis Major | `SCMP_017` | LandLarge |
| Seton's Clutch | `SCMP_009` | Naval (20 km, 60% water, 8 starts; **two-team map** — not a 2v2v2 venue) |
| Saltrock Colony | `SCMP_025` | NavalLarge (10 km, 65% water, 6 starts, three pairs — the 2v2v2 venue) |
| Crossfire Canal | `SCMP_024` | 20 km, 6 starts |
| Crash Site | `crash_site.v0003` | 10 km, 6 starts (vault map; versioned names do resolve) |

### Team layouts

Pass a seventh argument to `run-matrix.sh`, or `FAF_LAYOUT` to `run-smoke.sh`,
for a long match with ordinary allies and opponents:

```bash
./scripts/run-matrix.sh 1 SCMP_009 8675309 2 3 my-3v3 3v3
./scripts/run-matrix.sh 2 SCMP_025 8675309 2 3 my-2v2v2 2v2v2
```

`3v3` is sentinel 49 and `2v2v2` is sentinel 50. Exactly **one** army is Red
Queen and every other contestant is FAF's stock Adaptive brain, so these measure
Red Queen cooperating with ordinary allies rather than fighting a mirror of
itself — which is the one thing the symmetric 1v1 sentinels cannot show.

Layouts default to **no human player** (`FAF_NO_HUMAN=1`, set automatically;
pass `0` to keep a human slot). The launching player only ever occupied a start
without contesting, so removing it frees that slot: a layout needs
`teams * size` AI starts, and with the human gone a six-army map seats a full
2v2v2. Verified on Saltrock Colony (`SCMP_025`, 10 km, 6 starts, 65% water →
`NavalLarge`), which reported `allies=2 enemies=4 deficit=2 income=1.20` with
all six armies contesting.

**Teams are grouped by start proximity, never by slot number.** Slot order is
not team order: Saltrock numbers its six starts interleaved, so sequential
pairing put every army's nearest neighbour on the *opposing* team — allies about
285 apart on a 512 map against enemies about 100 apart. That is three duels with
the partners exiled, and it silently misdescribes any team result measured that
way. Teams are grown by single linkage from the lexicographically first
unassigned army, which needs no per-map knowledge; with no usable start markers
it falls back to declaration order.

Undersized maps still fail silently by producing a smaller match — the old
`FAF_MIXED=2` sentinel returned a 2v1 on a four-start map and every result
labelled 2v2 was actually 2v1, with nothing in the log to say so. Confirm the
shape from the log before trusting a result:

```
income contract allies=3 enemies=3 deficit=0 income=1.00   # a real 3v3
income contract allies=2 enemies=4 deficit=2 income=1.20   # a real 2v2v2
```

`tests/team_layout_spec.lua` covers the assignment, including that an
undersized map yields an incomplete layout.

### Watching a match

A matrix says which cells were lost. It cannot say why, and two rounds of
spectating produced eight defects in an afternoon that twelve matches had not
surfaced. The `watch` line exists so that view can be had from the log:
`Observer.lua` writes one a game minute carrying the inventory and intent a
spectator reads off the screen — what the commander is doing and how far from
home it has gone, point defence and anti-air by tier, extractors by tier, idle
engineers, and own versus enemy unit counts by tier.

```bash
# follow a running match; alarms as they fire, context every five game minutes
python3 scripts/watch-match.py /tmp/rq-m-<label>.log --follow --timeout 180
# after the fact, one row per game minute
python3 scripts/watch-match.py /tmp/rq-m-<label>.log --timeline
```

The alarms are the observations from those rounds, turned into triggers that
fire once each: a tier reached with no defence built behind it, a missile
launcher before a point defence, a Tech 3 extractor while Tech 1 extractors
remain, a commander past its leash or below half health, a brownout, idle
engineers, being outgunned, and extractors falling three minutes running.

Enemy counts in the `watch` line are read straight off the opposing brains.
That is telemetry and nothing else: **no decision may read it**, or Red Queen
is playing with knowledge it has not earned.

Visual capture is not available on this machine. The game runs under rootless
XWayland, so an X11 grab of its window returns black, and this build's
ImageMagick `import` cannot reach the display at all. The log is the view.

### Reaping a finished cell

A match writes `GameEnded` and `JsonStats` and then **sits at the post-game
screen forever**. `run-matrix.sh` has no timeout of its own, so a driver that
only waits on the process waits until its own timeout expires: twelve cells took
ninety minutes where the matches themselves took four minutes each. Wrap each
cell in `timeout --signal=TERM --kill-after=15s 900s` as the backstop, and poll
its log so the cell is reaped as soon as the match is actually over:

```bash
while ! grep -q GameEnded "$log" 2>/dev/null; do sleep 5; done
sleep 3   # let JsonStats land
```

Then terminate only processes whose own `/proc/<pid>/cmdline` contains that
cell's log path, and never one containing `/gpgnet`. With early reaping the same
twelve cells take twenty-two minutes.

### Reading the result

```bash
./scripts/analyze-log.py /tmp/rq-m-<label>.log          # behaviour summary, failure gate, army stats
python3 -c "import json;print(json.load(open('/tmp/rq-m-<label>.log.manifest.json'))['map'])"
```

Every launch writes `<log>.manifest.json` — the revision, the payload hash, the working-tree status and the map — plus `<log>.patch`. That manifest is how a result stays attributable to an exact tree; recover the map of a past run from it rather than from memory. The engine's end-of-match `JsonStats` line carries per-army built/lost/kills by category, which is the only place commander loss and per-tier unit counts appear.

A single match is one sample. Seed alone has flipped an outcome on the same map, faction and profile, so treat a lone result as a hypothesis and vary seed and faction before drawing a conclusion.

Every mechanism must be visible in a match log, and it is worth adding the log line *before* the run rather than after. Two mechanisms once ran a full 21-cell matrix leaving no trace: forward-base cover, which logged at `Logger.Debug` (off in behavioural runs) and stood down for 86% of bases behind a Tech 3 filter, and native engineer suppression, which was inferable only by noticing that held engineers tracked their target exactly. Outcomes cannot attribute a change; only mechanism figures can. `Logger.Debug` is for interactive work — a figure a matrix has to read belongs in the periodic state line, with a contract asserting it is reported.

### Where results live

`run-matrix.sh` writes every log and manifest to `/tmp`, which does not survive a reboot. Anything a conclusion rests on belongs in **`docs/balance/data/`** before the machine goes down:

| file | what it holds |
| --- | --- |
| `matrix-results.csv` | one row per cell per payload — the end-of-match value of every instrumented figure |
| `defence-coverage-series.csv` | per-game-minute series where a figure needs its shape, not just its endpoint |
| `manifests/` | the launch manifests. This is what keeps a result attributable to an exact tree, and it is the cheapest thing here to lose |
| `raw-logs.tar.gz`, `earlier-runs.tar.gz` | the full logs, compressed |
| `tooling/` | the matrix drivers and the paired-comparison script |
| `payloads.json`, `README.md` | payload hash to what that payload changed, and how to read the rest |

Extract the per-cell figures when the matrix lands, not later: a conclusion recorded in a document with its evidence left in `/tmp` cannot be rechecked, and re-running costs hours. Record the payload hash with the numbers — `docs/balance/README.md` maps hashes to changes, and a figure without one cannot be compared against anything.

Compare a cell against itself across payloads, at that pair's common horizon. Cells are observed for 28–95 game minutes, deterministically but unequally, so a cross-cell comparison of final values measures match length as much as policy.

Bundling several changes into one run is acceptable only when each is separately observable that way. Otherwise one dominant regression masks everything: an engineer ceiling that cut factory production reduced two cells to 6 factories and 89-128 peak mass, and made the establishment and tiering changes shipped alongside it unmeasurable.

## Coding Style & Naming Conventions

Use four spaces and no tabs. Follow existing FAF Lua style: `PascalCase` for classes, exported functions, and module filenames; descriptive local names; and `UPPER_CASE` category expressions only where FAF APIs require them. Use `__init` for `ClassSimple` constructors. Export from a module by assigning globals, never with a top-level `return { ... }`: FAF's `import()` runs the file in a fresh environment and returns *that environment*, discarding the returned value, so a `return`-style module raises "access to nonexistent global variable" on first use. Contracts cannot catch this on their own, because `dofile` honours the return value the engine ignores — load modules in specs the way the engine does, with `setfenv` over a fresh environment table. FAF uses an older Lua dialect: use `math.mod(a, b)`, not `%`. Keep imports rooted at `/mods/TheRedQueen/` with exact filename casing. Simulation logic must remain deterministic; do not use wall-clock time or hidden enemy-state enumeration.

## Testing Guidelines

Name Lua tests `*_spec.lua`. Add pure tests for formulas and invariants, and extend `scripts/validate_mod.py` for structural contracts. Run `./scripts/validate.sh` before every submission. Runtime changes also require an in-game smoke test and log analysis. Broader releases should cover the faction, terrain, team, victory, and performance matrix in `docs/testing.md`.

Never iterate a multi-return call directly: `for _, x in ipairs(self:Thing())` raises `loop over expected but got number` in the game's Lua when `Thing` returns more than one value, because the extra returns are flattened into the generic-for's control variables. LuaJIT accepts it, so `./scripts/validate.sh` compiles and every contract passes — the failure appears only in a match, as a scheduler task dying every pass. It cost 177 failed production passes in a run whose result had already been reported. Bind the call to a local first; `scripts/validate_mod.py` now fails on the pattern.

**Run `scripts/analyze-log.py` on every match log before reporting anything from it.** It gates on exactly this: `Red Queen scheduler failures: 177` was sitting in that log the whole time. Ad-hoc greps for the figure of interest will not show that the run was broken.

Hooks must be placed in the file that *defines* the symbol they capture, not one that merely uses it. `hook/lua/<path>` is appended to the environment of `lua/<path>`, and `system/config.lua` installs a strict metatable that raises on reading a nonexistent global — so a misplaced capture aborts that file's import and crashes the simulation before the first frame, with a native callstack rather than a Lua error. It happened with `EngineerMoveWithSafePath`, which `platoon.lua` uses as `AIUtils.EngineerMoveWithSafePath` but `lua/AI/aiutilities.lua` defines. The contract gate cannot see this, because specs supply the hook's environment themselves. Run `scripts/check-hook-targets.py ~/.faforever/gamedata/lua.nx2` after adding or moving a hook; it resolves each hook to its native file in the installed archive and fails on a symbol that file does not define.

The same strict metatable reaches ordinary modules, not only hooks. Reading a
global that does not exist *yet* raises, so `if SomeEngineGlobal then` is not a
safe probe inside a constructor: the brain is built before the engine has
finished publishing its globals. `IntelManager.__init` probing `MapSize` that
way killed the brain outright — zero brains started, seven log lines, and a
recorded victory that meant nothing. Resolve engine globals lazily, on first
use, and wrap the read in `pcall`. No contract can catch this, because specs
supply their own permissive environment; only a match can.

Before starting any in-game or command-line smoke test, verify that the active `mods/TheRedQueen` path is a symbolic link and that `readlink -f` resolves to this repository checkout. Do not interpret runtime results from a copied directory, stale payload, or link targeting another checkout; correct the development installation first.

## Commit & Pull Request Guidelines

No repository-specific commit history is available yet. Use short imperative subjects, optionally scoped, such as `ai: preserve defensive reserve`. Keep commits focused. Pull requests should explain behavioral impact, identify affected match types, link relevant issues, and include validation commands plus representative `[RedQueen]` log evidence. Include screenshots only for lobby or other UI changes. Never claim the target rating without replay or beta evidence.
