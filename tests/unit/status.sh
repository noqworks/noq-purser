#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# The status page and the self-test.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
printf 'BUILD_DATE=%s\n' "$(( $(date +%s) - 10 * 86400 ))" > /run/purser-test/image-release
conf IMAGE_RELEASE /run/purser-test/image-release
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
# night 3: a pgBackRest file that never changes is changed -> suspect
night_activity 20260303 2
f=$(find /srv/src/pgdemo/backup/demo -path '*F/pg_data/base/1/2608.zst' | sort | tail -1); echo tamper >> "$f"
publish_generation 2026-03-03T03-10Z; run_box 2026-03-03T03-10Z
eq "night 3 suspect" supheli "$(last)"
night 2026-03-04T03-10Z
$P status > "$LOGDIR/status.txt" 2>&1; eq "status exits 0" 0 $?
s=$LOGDIR/status.txt
ok "image line" grep -qE '^Image built [0-9-]{10} \(10 days ago\)' "$s"
ok "last sound line (the one before the suspect)" grep -qE '^Last sound generation: 2026-03-02T03-10Z \([0-9]+ (h|days) ago\)' "$s"
ok "last window line" grep -qE '^Last window: .*taken.*\(2026-03-04T03-10Z, ' "$s"
ok "suspect line" grep -q '^Suspect: 2026-03-03T03-10Z' "$s"
ok "suspect reason shown with the disk locked" grep -q 'pgBackRest files in pgdemo that never change were changed' "$s"
ok "deletion paused line" grep -qE '^Deletion paused for [0-9]+ days' "$s"
ok "disk usage line" grep -qE '^Disk: [0-9.]+ of [0-9.]+ GB used \([0-9]+%\), measured' "$s"
ok "SMART line" grep -qE '^SMART: PASSED, 1234 hours, 0 reallocated, life left' "$s"
ok "disk locked line" grep -q '^Disk now: locked' "$s"
ok "clock line" grep -q '^Clock: synchronised' "$s"
ok "operation code line" grep -q '^Operation code: not set' "$s"
ok "no hardware lines of removed parts" not grep -qiE 'voltage|relay|DS3231' "$s"
conf LANG_UI tr
$P status > "$LOGDIR/status-tr.txt" 2>&1
ok "Turkish status" grep -q '^Disk şu an: kilitli' "$LOGDIR/status-tr.txt"
conf LANG_UI en

# self-test
$P selftest > "$LOGDIR/selftest.txt" 2>&1; rc=$?
eq "self-test passes on the lab" 0 "$rc"
eq "five PASS lines" 5 "$(grep -c '^  PASS' "$LOGDIR/selftest.txt")"
ok "lines: disk, speed, SMART, network, clock" sh -c "grep -q 'disk appears on USB' $LOGDIR/selftest.txt && grep -q 'USB link speed 480' $LOGDIR/selftest.txt && grep -q 'SMART can be read' $LOGDIR/selftest.txt && grep -q 'gate 127.0.0.1:2222 answers' $LOGDIR/selftest.txt && grep -q 'clock: synchronised' $LOGDIR/selftest.txt"
echo 12 > /run/sim/sys/bus/usb/devices/1-1/speed; echo 2 > /run/sim/smart-rc; echo unsynced > /run/sim/chrony
$P selftest > "$LOGDIR/selftest-bad.txt" 2>&1; rc=$?
eq "three failures counted" 3 "$rc"
ok "slow link fails" grep -q 'FAIL  USB link speed 12' "$LOGDIR/selftest-bad.txt"
ok "SMART fails" grep -q 'FAIL  SMART' "$LOGDIR/selftest-bad.txt"
ok "clock fails" grep -q 'FAIL  clock: not synchronised' "$LOGDIR/selftest-bad.txt"
echo 480 > /run/sim/sys/bus/usb/devices/1-1/speed; rm -f /run/sim/smart-rc /run/sim/chrony
ok "self-test leaves the disk locked" locked
unconf IMAGE_RELEASE
# the hourly tick must not draw over a running job's light (the job holds the lock)
$P light pulling
( flock 9; $P tick >/dev/null 2>&1 ) 9>/run/purser.lock
eq "tick leaves a running job's light alone" pulling "$(tr -d " " < /run/purser/light)"
$P tick >/dev/null 2>&1
ok "tick without a job redraws the light" not grep -q "^pulling" /run/purser/light
done_testing
