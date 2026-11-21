#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Mass delete: everything in every source disappears. Expected: suspect, deletion stops.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
conf KEEP_DAILY 2
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
find /srv/src -mindepth 2 -type f -delete
publish_generation 2026-03-03T03-10Z; clear_notes; run_box wipe
eq "result" supheli "$(last)"
ok "alarm names the mass deletion" notified "percent of the files were deleted"
eq "alarm is urgent" urgent "$(last_header Priority)"
ok "the box told the server" grep -q '^supheli ' /srv/server/ack/2026-03-03T03-10Z
src_init
publish_generation 2026-03-04T03-10Z; run_box n4
night 2026-03-05T03-10Z
eq "deletion stopped: all five dailies kept despite KEEP_DAILY=2" 5 "$(gens 'gen-*' | wc -l)"
$P status > "$LOGDIR/status-wipe.txt" 2>&1
ok "status names the first suspect" grep -q '^Suspect: 2026-03-03T03-10Z' "$LOGDIR/status-wipe.txt"
ok "status: deletion paused" grep -q '^Deletion paused for' "$LOGDIR/status-wipe.txt"
eq "last sound is the night before the suspect" 2026-03-02T03-10Z "$(cat "$ST/son-saglam")"
done_testing
