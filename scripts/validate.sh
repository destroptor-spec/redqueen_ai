#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_directory=$(cd -- "$script_directory/.." && pwd)
cd -- "$repository_directory"

python3 scripts/validate_mod.py

while IFS= read -r lua_source; do
    luajit -bl "$lua_source" >/dev/null
done < <(find hook lua tests -type f -name '*.lua' -print | sort)

luajit tests/base_lifecycle_spec.lua
luajit tests/contract_spec.lua
luajit tests/commander_safety_spec.lua
luajit tests/combat_manager_spec.lua
luajit tests/combat_telemetry_spec.lua
luajit tests/counter_builders_spec.lua
luajit tests/diagnostics_spec.lua
luajit tests/economy_manager_spec.lua
luajit tests/assistance_spec.lua
luajit tests/extractor_upgrades_spec.lua
luajit tests/engineer_survival_spec.lua
luajit tests/factory_tier_spec.lua
luajit tests/fortification_builders_spec.lua
luajit tests/income_bonus_spec.lua
luajit tests/redqueen_brain_spec.lua
luajit tests/engineer_recall_spec.lua
luajit tests/intel_manager_spec.lua
luajit tests/profile_spec.lua
luajit tests/scouting_config_spec.lua
luajit tests/experimentals_spec.lua
luajit tests/team_layout_spec.lua
luajit tests/production_manager_spec.lua
luajit tests/production_trace_spec.lua
luajit tests/strategy_director_spec.lua
luajit tests/world_model_spec.lua
luajit tests/platoon_plans_spec.lua
luajit tests/narrator_spec.lua
luajit tests/observer_spec.lua
python3 tests/analyze_log_spec.py
python3 tests/analyze_combat_spec.py
python3 tests/watch_match_spec.py
python3 -B tests/production_trace_log_spec.py
python3 -B tests/prepare_runtime_spec.py
python3 -B tests/summarize_matrix_spec.py
echo "All Red Queen validation checks passed"
