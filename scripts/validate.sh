#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_directory=$(cd -- "$script_directory/.." && pwd)
cd -- "$repository_directory"

python3 scripts/validate_mod.py

while IFS= read -r lua_source; do
    luajit -bl "$lua_source" >/dev/null
done < <(find hook lua tests -type f -name '*.lua' -print | sort)

luajit tests/contract_spec.lua
luajit tests/commander_safety_spec.lua
luajit tests/combat_manager_spec.lua
luajit tests/counter_builders_spec.lua
luajit tests/economy_manager_spec.lua
luajit tests/fortification_builders_spec.lua
luajit tests/income_bonus_spec.lua
luajit tests/intel_manager_spec.lua
luajit tests/production_manager_spec.lua
luajit tests/strategy_director_spec.lua
luajit tests/world_model_spec.lua
echo "All Red Queen validation checks passed"
