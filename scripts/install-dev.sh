#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /absolute/path/to/forged-alliance/mods" >&2
    exit 2
fi

mods_directory=$1
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_directory=$(cd -- "$script_directory/.." && pwd)
target_path="$mods_directory/TheRedQueen"

if [[ ! -d "$mods_directory" ]]; then
    echo "Mods directory does not exist: $mods_directory" >&2
    exit 2
fi

if [[ -e "$target_path" && ! -L "$target_path" ]]; then
    echo "Refusing to replace non-symlink path: $target_path" >&2
    exit 3
fi

ln -sfn -- "$repository_directory" "$target_path"
echo "Installed development link: $target_path -> $repository_directory"
