# Repository Guidelines

## Project Structure & Module Organization

`mod_info.lua` defines the FAF simulation mod. `lua/AI/RedQueenBrain.lua` is the brain entry point, while focused systems live under `lua/AI/RedQueen/` (intel, economy, production, strategy, combat, team coordination, and diagnostics). Lobby registration and tooltips are in `lua/AI/CustomAIs_v2/` and `lua/AI/LobbyTooltips/`. Engine-safe extensions belong under `hook/`; keep hooks additive and narrowly scoped. Pure contract tests live in `tests/`, developer utilities in `scripts/`, and design/runtime notes in `docs/`.

## Build, Test, and Development Commands

- `./scripts/validate.sh` — required fast gate; validates metadata/imports, compiles every Lua file with LuaJIT, and runs contract tests.
- `./scripts/install-dev.sh "/path/to/.../mods"` — installs a development symlink named `TheRedQueen`, which is required by absolute mod imports.
- `./scripts/analyze-log.py /path/to/game.log` — summarizes Red Queen startup, income contracts, diagnostics, and failures.
- `FAF_WRAPPER=... FAF_EXE=... FAF_PREFS=RedQueenSmoke.prefs ./scripts/run-smoke.sh SCMP_007` — launches the isolated command-line smoke test. Follow `docs/testing.md` when preparing the preferences file.

## Coding Style & Naming Conventions

Use four spaces and no tabs. Follow existing FAF Lua style: `PascalCase` for classes, exported functions, and module filenames; descriptive local names; and `UPPER_CASE` category expressions only where FAF APIs require them. Use `__init` for `ClassSimple` constructors. FAF uses an older Lua dialect: use `math.mod(a, b)`, not `%`. Keep imports rooted at `/mods/TheRedQueen/` with exact filename casing. Simulation logic must remain deterministic; do not use wall-clock time or hidden enemy-state enumeration.

## Testing Guidelines

Name Lua tests `*_spec.lua`. Add pure tests for formulas and invariants, and extend `scripts/validate_mod.py` for structural contracts. Run `./scripts/validate.sh` before every submission. Runtime changes also require an in-game smoke test and log analysis. Broader releases should cover the faction, terrain, team, victory, and performance matrix in `docs/testing.md`.

Before starting any in-game or command-line smoke test, verify that the active `mods/TheRedQueen` path is a symbolic link and that `readlink -f` resolves to this repository checkout. Do not interpret runtime results from a copied directory, stale payload, or link targeting another checkout; correct the development installation first.

## Commit & Pull Request Guidelines

No repository-specific commit history is available yet. Use short imperative subjects, optionally scoped, such as `ai: preserve defensive reserve`. Keep commits focused. Pull requests should explain behavioral impact, identify affected match types, link relevant issues, and include validation commands plus representative `[RedQueen]` log evidence. Include screenshots only for lobby or other UI changes. Never claim the target rating without replay or beta evidence.
