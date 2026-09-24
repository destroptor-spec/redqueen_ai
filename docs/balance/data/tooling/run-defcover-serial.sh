#!/usr/bin/env bash
# Eighteen mirror cells on the instrumented payload, two at a time.
# Reproduces the control set exactly (same maps, seeds, mirrored factions),
# so step 1 is a neutrality check: outcomes must match the control.
set -uo pipefail
cd "/var/home/andreas/VS Code/TheRedQueen" || exit 1

MAPS=("isis:SCMP_015" "syrtis:SCMP_017")
SEEDS=(2071971 424242 8675309)
FACS=("uef:1" "aeon:2" "sera:4")

# Parallel arrays, never `eval set --`: collapsing a quoted line into one
# argument silently failed all 24 cells of an earlier matrix and still exited 0.
c_map=(); c_seed=(); c_fac=(); c_label=()
for m in "${MAPS[@]}"; do
    mname=${m%%:*}; mid=${m##*:}
    for s in "${SEEDS[@]}"; do
        for f in "${FACS[@]}"; do
            fname=${f%%:*}; fidx=${f##*:}
            c_map+=("$mid"); c_seed+=("$s"); c_fac+=("$fidx")
            c_label+=("defcover-$mname-$s-$fname")
        done
    done
done

reap() {  # only this cell's own game process, never the user's live game
    local log=$1 p cl
    for p in $(ps -eo pid,comm | awk '$2 ~ /^ForgedAlliance/ {print $1}'); do
        cl=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) || continue
        case "$cl" in
            *"/gpgnet"*) continue ;;
        esac
        case "$cl" in
            *"/redqueen"*"$log"*|*"$log"*"/redqueen"*) kill -TERM "$p" 2>/dev/null ;;
        esac
    done
}

worker() {
    local slot=$1 mid=$2 seed=$3 fac=$4 label=$5
    local log="/tmp/rq-m-$label.log"
    timeout --signal=TERM --kill-after=15s 900s \
        ./scripts/run-matrix.sh "$slot" "$mid" "$seed" "$fac" "$fac" "$label" &
    local runner=$!
    while kill -0 "$runner" 2>/dev/null; do
        if grep -q GameEnded "$log" 2>/dev/null; then
            sleep 3          # let JsonStats land
            reap "$log"
            break
        fi
        sleep 5
    done
    wait "$runner" 2>/dev/null
    if grep -q GameEnded "$log" 2>/dev/null; then
        echo "DONE  $label"
    else
        echo "NOEND $label"
    fi
}

total=${#c_label[@]}
echo "launching $total cells, ONE at a time (swap exhausted; a killed match yields nothing)"
i=0
while [ "$i" -lt "$total" ]; do
    echo "--- cell $((i + 1))/$total: ${c_label[$i]} ---"
    free -h | awk 'NR==2 {print "    mem available: " $7}'
    worker 1 "${c_map[$i]}" "${c_seed[$i]}" "${c_fac[$i]}" "${c_label[$i]}"
    i=$((i + 1))
done
echo "ENGSURV MATRIX COMPLETE"
