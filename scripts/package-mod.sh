#!/usr/bin/env bash
# Build the uploadable mod archive.
#
# The repository is a development tree: 38 MB of match archives under
# docs/balance/data, plus scripts, contracts and notes. None of that belongs in
# the Vault, and none of it may be shipped by accident.
#
# The payload is therefore an **allowlist**, not an exclusion list. A denylist
# would have to be updated every time a new directory appears, and the one that
# appeared this month was 38 MB of logs.
#
# usage: package-mod.sh [output-directory]     (default: dist/)
set -euo pipefail

repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repository"

output=${1:-dist}
name="TheRedQueen"

# Everything the game loads, and nothing else. Paths are relative to the
# repository root and are copied to the same place inside the archive.
payload=(
    mod_info.lua
    lua
    hook
    assets
    LICENSE
    README.md
)

# A broken tree must not be packaged. The gate compiles every Lua file and runs
# the contracts, including the one that keeps the version, the UID revision and
# the two release labels agreeing.
echo "==> validating"
./scripts/validate.sh > /dev/null 2>&1

version=$(grep -oE '^version = [0-9]+' mod_info.lua | grep -oE '[0-9]+')
uid=$(grep -oE '^uid = "[^"]+"' mod_info.lua | cut -d'"' -f2)

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "    WARNING: working tree is dirty; the archive will not match any commit"
fi

staging=$(mktemp -d)
trap 'rm -rf -- "$staging"' EXIT
root="$staging/$name"
mkdir -p -- "$root"

echo "==> staging"
for item in "${payload[@]}"; do
    if [[ ! -e "$item" ]]; then
        echo "    missing payload entry: $item" >&2
        exit 1
    fi
    cp -R -- "$item" "$root/"
done

# Development residue can still ride along inside an allowed directory.
find "$root" \( -name '__pycache__' -o -name '*.pyc' -o -name '*.log' \
    -o -name '*.tmp' -o -name '*.patch' -o -name '.DS_Store' \) -prune -exec rm -rf -- {} +

# The icon path in mod_info.lua is resolved by the game inside the mod folder,
# so a missing file is a broken upload rather than a missing picture.
icon=$(grep -oE '^icon = "[^"]+"' mod_info.lua | cut -d'"' -f2 || true)
if [[ -n "$icon" ]]; then
    relative=${icon#/mods/$name/}
    if [[ ! -f "$root/$relative" ]]; then
        echo "    icon declared as $icon but $relative is not in the payload" >&2
        exit 1
    fi
fi

# Nothing outside the allowlist may appear at the archive root.
mapfile -t staged < <(cd -- "$root" && ls -A)
for entry in "${staged[@]}"; do
    keep=false
    for item in "${payload[@]}"; do
        [[ "$entry" == "${item%%/*}" ]] && keep=true
    done
    if [[ "$keep" != true ]]; then
        echo "    unexpected entry in payload: $entry" >&2
        exit 1
    fi
done

mkdir -p -- "$output"
archive="$repository/$output/$name.v$version.zip"
rm -f -- "$archive"

echo "==> archiving"
( cd -- "$staging" && zip -q -r -X "$archive" "$name" )

echo
echo "  archive : $archive"
echo "  size    : $(du -h "$archive" | cut -f1)"
echo "  files   : $(unzip -Z1 "$archive" | grep -cv '/$')"
echo "  version : $version"
echo "  uid     : $uid"
echo
echo "  top level inside the archive:"
unzip -Z1 "$archive" | awk -F/ 'NF>1 && $2 != "" {print "    " $1 "/" $2}' | sort -u | head -12
