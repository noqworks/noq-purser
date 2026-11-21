#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# The server stops publishing: "no generation" every window, delay alarm after 30 hours.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
o=$(opens); clear_notes; run_box none
eq "result" no_generation "$(last)"
ok "notified: no generation" notified "The server produced no generation tonight"
eq "disk never unlocked" "$o" "$(opens)"
# the server rewinds LATEST to an old generation: not taken either
echo 2026-02-01T03-10Z > "$SG/LATEST"; run_box rewind
eq "rewound LATEST is ignored" no_generation "$(last)"
clear_notes; $P tick >/dev/null 2>&1; $P tick >/dev/null 2>&1
eq "delay alarm, once per last sound generation" 1 "$(ncount "The last sound backup is")"
done_testing
