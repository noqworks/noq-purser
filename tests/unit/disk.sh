#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# The always-attached disk: a hung USB-SATA bridge gets one software reset; a disk that will
# not lock is reported; the hourly tick locks a disk left open outside a job.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
first_night 2026-03-01T03-10Z
eq "night 1" tamam "$(last)"
eq "USB port remembered at the last good open" 1-1 "$(cat "$ST/usb.port")"

# hung once: the device comes back after one reset
rm -f "$ST/usb.port"   # also exercise the fallback: find the port by its mass-storage interface
rm -f /run/sim/by-uuid/test-0001; echo once > /run/sim/bridge-hung; sleep 1
night_activity 20260302 1; publish_generation 2026-03-02T03-10Z
clear_notes; run_box hung-once
eq "bridge hung once: generation taken after the reset" tamam "$(last)"
ok "the reset is logged" grep -q 'disk is back after the USB reset' "$LOGDIR/run-hung-once.log"
ok "the reset time is recorded" grep -qE '^usb_reset_at=[0-9]+$' "$ST/maint"
eq "no alarm when the reset helped" 0 "$(ncount "not visible")"
$P status > "$LOGDIR/status-usb.txt" 2>&1
ok "status shows the last USB reset" grep -q '^Last USB reset of the bridge: ' "$LOGDIR/status-usb.txt"

# hung for good: one reset, then an urgent alarm; the disk is never unlocked
rm -f /run/sim/by-uuid/test-0001; echo always > /run/sim/bridge-hung
night_activity 20260303 2; publish_generation 2026-03-03T03-10Z
o=$(opens); clear_notes; run_box hung-always
eq "bridge hung: result" disk_error "$(last)"
eq "bridge hung: LUKS never opened" "$o" "$(opens)"
ok "bridge hung: alarm" notified "not visible or not readable on USB, also after one USB reset"
eq "bridge hung: urgent" urgent "$(last_header Priority)"
eq "exactly one reset attempt" 1 "$(grep -c 're-authorized\|unbound and bound' "$LOGDIR/run-hung-always.log")"
ln -sfn "$(cat /run/sim/loopdev)" /run/sim/by-uuid/test-0001; rm -f /run/sim/bridge-hung
run_box back
eq "cable fine again: the waiting generation is taken" 2026-03-03T03-10Z "$(cat "$ST/son-yayin")"

# a disk that will not lock
touch /run/sim/close-fails
night_activity 20260304 3; publish_generation 2026-03-04T03-10Z
clear_notes; run_box nolock
ok "disk that will not lock: alarm" notified "The disk could not be locked"
ok "the mapper is still there" test -e /run/sim/mapper/purser
ok "the notification does not claim the disk is locked" not notified "Disk locked."
rm -f /run/sim/close-fails
$P tick >/dev/null 2>&1
ok "the hourly tick locks a disk left open outside a job" locked
# not while a job holds the lock
mount_disk; ln -sfn "$(cat /run/sim/loopdev)" /run/sim/mapper/purser
( exec 9>/run/purser.lock; flock 9; sleep 4 ) & sleep 1
$P tick >/dev/null 2>&1
ok "tick leaves the disk alone while a job runs" mountpoint -q "$M"
wait; $P tick >/dev/null 2>&1
ok "and locks it once the job is gone" locked
done_testing
