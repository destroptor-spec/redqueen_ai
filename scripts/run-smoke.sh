#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: FAF_WRAPPER=/path/to/launchwrapper FAF_EXE=/path/to/ForgedAlliance.exe $0 MAP_NAME [LOG_PATH]" >&2
    exit 2
fi

: "${FAF_WRAPPER:?Set FAF_WRAPPER to the FAF Wine/Proton launch wrapper}"
: "${FAF_EXE:?Set FAF_EXE to the FAF ForgedAlliance.exe}"

case ${FAF_SCOUTING_MODE-combined} in
    combined) ;;
    production-only|dispatch-only)
        if [[ ${FAF_FIXED_RUNTIME:-0} != 1 ]]; then
            echo "FAF_SCOUTING_MODE requires FAF_FIXED_RUNTIME=1 to transmit the scenario option" >&2
            exit 2
        fi
        ;;
    *) echo "Unknown FAF_SCOUTING_MODE '${FAF_SCOUTING_MODE}' (expected combined, production-only or dispatch-only)" >&2; exit 2 ;;
esac

map_name=$1
log_path=${2:-/tmp/the-red-queen-smoke.log}
# init.lua is whatever init the FAF client configured last, which may be a
# featured mod such as Nomads whose init never calls LoadVaultContent. Without
# that call the vault mods directory is never mounted and The Red Queen cannot
# load at all, so default to FAF's own init instead.
init_file=${FAF_INIT:-init_faf.lua}
binary_directory=$(cd -- "$(dirname -- "$FAF_EXE")" && pwd)
preferences_file=${FAF_PREFS:-}
# Strict mixed matches use equal-sized teams; non-contestants are civilian.
# Tracing is bounded and can run in either 1v1 or 2v2.
difficulty=42
if [[ ${FAF_PRODUCTION_TRACE:-0} == 1 ]]; then
    difficulty=43
    if [[ ${FAF_MIXED:-0} == 2 ]]; then difficulty=46; fi
elif [[ ${FAF_MIXED:-0} == 2 ]]; then
    difficulty=45
elif [[ ${FAF_MIXED:-0} == 1 ]]; then
    difficulty=44
fi

if [[ ${FAF_LIFECYCLE_FIXTURE:-0} == 1 ]]; then difficulty=47; fi
if [[ ${FAF_DEFENSE_FIXTURE:-0} == 1 ]]; then difficulty=48; fi

# Team layouts put one Red Queen army alongside stock Adaptive allies and
# opponents. They need team_count * team_size AI starts, and the launching
# player consumes a slot, so both of these want a seven-start map or larger --
# SCMP_009 (Seton's Clutch, 8 starts, 20 km) is the reference.
case ${FAF_LAYOUT:-} in
    3v3) difficulty=49 ;;
    2v2v2) difficulty=50 ;;
    "") ;;
    *) echo "Unknown FAF_LAYOUT '${FAF_LAYOUT}' (expected 3v3 or 2v2v2)" >&2; exit 2 ;;
esac

# A layout gives its slots to AI contestants, so the launching player is pure
# overhead: it occupies a start, which is why a 2v2v2 would not fit a six-army
# map like Saltrock Colony. Verified that the engine runs a session with no
# human player at all, so layouts default to that and every start contests.
# Set FAF_NO_HUMAN=0 explicitly to keep a human slot.
if [[ -n ${FAF_LAYOUT:-} ]]; then
    : "${FAF_NO_HUMAN:=1}"
    export FAF_NO_HUMAN
fi

if [[ ${FAF_FIXED_RUNTIME:-0} == 1 ]]; then
    runtime_team_size=1
    if [[ ${FAF_MIXED:-0} == 2 ]]; then runtime_team_size=2; fi
    runtime_overlay="${log_path}.runtime"
    script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    init_file=$(python3 "$script_directory/prepare-runtime.py" "$binary_directory" "$runtime_overlay" "$runtime_team_size")
fi

launch_arguments=(
    /init "$init_file"
    /map "$map_name"
    /redqueen
    /seed "${FAF_SEED:-2071971}"
    /diff "$difficulty"
    /victory demoralization
    /windowed 1280 720
    /nomovie
    /nosound
    /nobugreport
    /log "$log_path"
)

if [[ -n "$preferences_file" ]]; then
    launch_arguments+=(/prefs "$preferences_file")
fi

repository_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
active_mod=${FAF_MOD_PATH:-/var/home/andreas/My Games/Gas Powered Games/Supreme Commander Forged Alliance/mods/TheRedQueen}
if [[ ! -L "$active_mod" || "$(readlink -f -- "$active_mod")" != "$repository_directory" ]]; then
    echo "Active TheRedQueen must be a symlink resolving to $repository_directory" >&2
    exit 1
fi
# The slot preferences must enable *this* mod UID. The UID carries the release
# revision (validate_mod.py requires its last six digits to equal the Vault
# version), so a version bump changes it -- and a prefs file still naming the
# previous UID launches the game with the mod silently disabled. That was a
# documented manual pre-flight step and nothing enforced it; a whole matrix run
# could have been interpreted as Red Queen while Red Queen was not loaded.
if [[ -n "$preferences_file" ]]; then
    mod_uid=$(sed -n 's/^uid = "\([^"]*\)".*/\1/p' "$repository_directory/mod_info.lua")
    prefs_directory="/var/home/andreas/faf-linux/prefix/drive_c/users/steamuser/AppData/Local/Gas Powered Games/Supreme Commander Forged Alliance"
    prefs_path="$preferences_file"
    [[ -f "$prefs_path" ]] || prefs_path="$prefs_directory/$preferences_file"
    if [[ -z "$mod_uid" ]]; then
        echo "Could not read the mod UID from mod_info.lua" >&2
        exit 1
    fi
    if [[ ! -f "$prefs_path" ]]; then
        echo "Preferences file not found: $prefs_path" >&2
        exit 1
    fi
    if ! grep -q "$mod_uid" "$prefs_path"; then
        echo "$prefs_path does not enable mod UID $mod_uid; the game would run without The Red Queen" >&2
        exit 1
    fi
fi
python3 "$repository_directory/scripts/record-runtime.py" "$repository_directory" "$log_path" "$map_name" "$difficulty"

cd -- "$binary_directory"
exec "$FAF_WRAPPER" "$FAF_EXE" "${launch_arguments[@]}"
