#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core
# Borg signals: a changed committed segment is suspect; a segment after the previous copy's last
# commit (interrupted transaction, rolled back and written again by borg) is not.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
W=$(mktemp -d)
h() { printf '%064d' "$1"; }
lst() { printf '# purser-list 1\n# generation=%s\n# clean=yes\n# fresh=yes\n' "$1"; shift; printf '%s\n' "$@"; }
KINDS="borg:borgdemo"
run() { WARN=() SUSPECT=(); signals "$W/prev" "$W/new" 2026-03-03T03-10Z 1 "$W" >/dev/null 2>&1; echo "${SUSPECT[*]}"; }

lst 2026-03-02T03-10Z "$(h 1)  borgdemo/index.2440" "$(h 2)  borgdemo/data/2/2439" "$(h 3)  borgdemo/data/2/2440" "$(h 4)  borgdemo/data/2/2441" > "$W/prev"
lst 2026-03-03T03-10Z "$(h 5)  borgdemo/index.3045" "$(h 2)  borgdemo/data/2/2439" "$(h 3)  borgdemo/data/2/2440" "$(h 9)  borgdemo/data/2/2441" > "$W/new"
eq "segment after the last commit rewritten: not suspect" "" "$(run)"

lst 2026-03-03T03-10Z "$(h 5)  borgdemo/index.3045" "$(h 2)  borgdemo/data/2/2439" "$(h 8)  borgdemo/data/2/2440" "$(h 4)  borgdemo/data/2/2441" > "$W/new"
eq "committed segment changed: suspect" "borg_segment_changed/borgdemo" "$(run)"

lst 2026-03-02T03-10Z "$(h 2)  borgdemo/data/2/2439" "$(h 4)  borgdemo/data/2/2441" > "$W/prev"
lst 2026-03-03T03-10Z "$(h 2)  borgdemo/data/2/2439" "$(h 9)  borgdemo/data/2/2441" > "$W/new"
eq "no index in the previous copy: every changed segment counts" "borg_segment_changed/borgdemo" "$(run)"
done_testing
