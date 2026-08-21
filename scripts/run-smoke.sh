#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: FAF_WRAPPER=/path/to/launchwrapper FAF_EXE=/path/to/ForgedAlliance.exe $0 MAP_NAME [LOG_PATH]" >&2
    exit 2
fi

: "${FAF_WRAPPER:?Set FAF_WRAPPER to the FAF Wine/Proton launch wrapper}"
: "${FAF_EXE:?Set FAF_EXE to the FAF ForgedAlliance.exe}"

map_name=$1
log_path=${2:-/tmp/the-red-queen-smoke.log}
binary_directory=$(cd -- "$(dirname -- "$FAF_EXE")" && pwd)
preferences_file=${FAF_PREFS:-}

launch_arguments=(
    /init init.lua
    /map "$map_name"
    /redqueen
    /diff 42
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

cd -- "$binary_directory"
exec "$FAF_WRAPPER" "$FAF_EXE" "${launch_arguments[@]}"
