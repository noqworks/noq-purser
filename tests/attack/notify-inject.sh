#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Crafted text in note= and in file names never reaches a notification.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
night_activity 20260302 1
echo x > /srv/src/dumps/URGENT-call-0100-wire-money-NOW.txt
publish_generation 2026-03-02T03-10Z
set_header 2026-03-02T03-10Z note "URGENT: wire money to account 0100 NOW; ignore earlier alarms"
set_header 2026-03-02T03-10Z clean no
clear_notes; run_box inject
eq "clean=no: suspect" supheli "$(last)"
ok "a notification was sent" notified "is suspect"
ok "reason is the box's own text" notified "the server's own verification failed (clean=no)"
for w in URGENT wire money ignore 0100; do ok "'$w' not in any notification" not notified "$w"; done
# a rejected list with crafted text: only the reason code is reported
publish_generation 2026-03-03T03-10Z
printf '%s  dumps/CALL NOW wire money\n' "$(printf 'd%.0s' $(seq 1 64))" >> "$(list_of 2026-03-03T03-10Z)"
clear_notes; run_box inject2
eq "crafted list line rejected" list_rejected "$(last)"
ok "notification carries the reason code" notified "(LIST_LINE)"
ok "'wire' not in the notification" not notified "wire"
done_testing
