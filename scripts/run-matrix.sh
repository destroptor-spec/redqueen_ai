#!/usr/bin/env bash
# One cell of the behavioural variety matrix.
#
# Each cell is an isolated command-line match: its own preferences file so
# concurrent instances cannot race each other's write-back, its own log, and an
# explicit seed and faction pair so a result can be reproduced exactly. Four
# cells were safe in short tests; limit long matches to two concurrent cells.
#
# usage: run-matrix.sh <slot> <map> <seed> <rq_faction> <opp_faction> <label>
#   slot         1-6, selects RQTest<slot>.prefs (never the user's Game.prefs)
#   map          SCMP id, e.g. SCMP_037
#   seed         simulation seed; the same seed reproduces a match byte for byte
#   rq_faction   1 UEF, 2 Aeon, 3 Cybran, 4 Seraphim — the Red Queen army
#   opp_faction  faction index for every opposing army
#   label        names /tmp/rq-m-<label>.log and its manifest
# FAF_SCOUTING_MODE selects combined (default), production-only or dispatch-only.
set -euo pipefail

if [[ $# -lt 6 || $# -gt 7 ]]; then
    echo "usage: $0 <slot> <map> <seed> <rq_faction> <opp_faction> <label> [layout]" >&2
    exit 2
fi

slot=$1; map=$2; seed=$3; rq_faction=$4; opp_faction=$5; label=$6; layout=${7:-}
repository_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
log=${FAF_MATRIX_LOG_DIR:-/tmp}/rq-m-$label.log

rm -rf "$log" "$log.runtime"
cd -- "$repository_directory"
FAF_WRAPPER=${FAF_WRAPPER:-/var/home/andreas/faf-linux/launchwrapper} \
FAF_EXE=${FAF_EXE:-/home/andreas/.faforever/bin/ForgedAlliance.exe} \
FAF_PREFS="RQTest$slot.prefs" \
FAF_SEED="$seed" FAF_RQ_FACTION="$rq_faction" FAF_OPP_FACTION="$opp_faction" \
FAF_MIXED=$([[ -n "$layout" ]] && echo 0 || echo 1) \
FAF_LAYOUT="$layout" FAF_FIXED_RUNTIME=1 \
./scripts/run-smoke.sh "$map" "$log" > "$log.launch" 2>&1
