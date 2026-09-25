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

# The folder name is load-bearing and cannot be chosen freely.
#
# The FAF uploader records the folder the mod is in, and every import in this
# mod is absolute -- `import("/mods/TheRedQueen/...")`. Ship it under any other
# name and every path inside the mod resolves to nothing, which is a mod that
# loads and then fails on first use rather than one that fails to install.
#
# So the name is derived from the imports themselves and cross-checked, rather
# than written here and trusted to stay in agreement with them.
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

echo "==> checking the mod folder name"
mapfile -t prefixes < <(
    grep -rhoE 'import\("/mods/[^/]+/' lua hook --include='*.lua' \
        | sed 's|import("/mods/||; s|/$||' | sort -u
)
if [[ ${#prefixes[@]} -ne 1 ]]; then
    echo "    imports disagree on the mod folder: ${prefixes[*]}" >&2
    exit 1
fi
if [[ "${prefixes[0]}" != "$name" ]]; then
    echo "    imports are rooted at /mods/${prefixes[0]}/ but this packages $name;" >&2
    echo "    the uploader records the folder name, so every path would break" >&2
    exit 1
fi

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
    if [[ "$icon" != /mods/"$name"/* ]]; then
        echo "    icon $icon is not rooted at /mods/$name/" >&2
        exit 1
    fi
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
