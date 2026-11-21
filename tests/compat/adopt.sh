#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers
# A card and a disk from the ORIGINAL core (tests/compat/fixture, made by make-fixture.sh):
# the new code adopts them as they are. The old purser.conf still has the keys of the removed
# hardware; the old suspect reason is Turkish free text; one acknowledgement is pending.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
FX=/src/tests/compat/fixture
lab_reset
LAB_DISK_FROM=$FX/disk.img.xz bash /src/tests/lab/setup.sh reset-box >/dev/null
rm -rf /srv/server/generation/* /srv/server/ack/* /srv/server/ack/.contact /srv/server/cache/* /srv/src
tar -C / -xzf "$FX/server.tar.gz"
rm -rf /var/lib/purser; tar -C / -xzf "$FX/state.tar.gz"
ok "the old configuration has the removed hardware keys" grep -q '^RELAY_LINE=' /etc/purser/purser.conf
bash /src/tests/lab/setup.sh paths >> /etc/purser/purser.conf
rm -f "$ST/setup" "$ST/code.hash"
cleanup() { systemctl disable --now purser.timer purser-tick.timer >/dev/null 2>&1; nft flush ruleset 2>/dev/null; true; }
trap cleanup EXIT

mount_disk
before_gen=$(find "$G" -mindepth 1 -maxdepth 1 -name 'gen-*' -printf '%f\n' | sort)
before_long=$(find "$G" -mindepth 1 -maxdepth 1 -name 'uzun-*' -printf '%f\n' | sort)
pins=$(find "$A/pin" -mindepth 1 -printf '%f\n'); sus=$(find "$A/supheli" -mindepth 1 -printf '%f\n')
umount_disk
ok "fixture has daily generations" test -n "$before_gen"
ok "fixture has a long-retention copy" test -n "$before_long"
eq "fixture has a pin" 2026-01-02T03-10Z "$pins"
eq "fixture has a suspect" 2026-01-06T03-10Z "$sus"
eq "fixture has a pending ack" "2026-01-07T03-10Z tamam" "$(cat "$ST/bekleyen-ack")"

# first boot of the new card with the moved state
clear_notes
$P firstboot > "$LOGDIR/compat-firstboot.log" 2>&1; eq "firstboot exits 0" 0 $?
eq "setup complete without an operation code" "done" "$(sed -n 's/^state=//p' "$ST/setup")"
eq "disk marked adopted" adopted "$(sed -n 's/^disk=//p' "$ST/setup")"
eq "nightly timer enabled" enabled "$(systemctl is-enabled purser.timer 2>/dev/null)"
eq "hourly tick enabled" enabled "$(systemctl is-enabled purser-tick.timer 2>/dev/null)"
ok "box ready notified" notified "Box started: NOQ Purser"
ok "missing operation code reminded" notified "No operation code is set"
ok "disk locked after firstboot" locked
eq "last sound corrected to the night before the old suspect" 2026-01-05T03-10Z "$(cat "$ST/son-saglam")"
$P status > "$LOGDIR/compat-status1.txt" 2>&1
ok "status (disk locked) shows the old suspect" grep -q '^Suspect: 2026-01-06T03-10Z' "$LOGDIR/compat-status1.txt"
ok "status shows the old Turkish reason text" grep -q 'değişmemesi gereken' "$LOGDIR/compat-status1.txt"

# a new night with the new code
night_activity 20260108 4; publish_generation 2026-01-08T03-10Z
run_box compat
ok "new night taken (result $(last))" grep -qE '^(tamam|uyari)$' <<< "$(last)"
ok "pending ack delivered" test -s /srv/server/ack/2026-01-07T03-10Z
ok "pending ack cleared" not test -e "$ST/bekleyen-ack"
ok "new ack written" test -s /srv/server/ack/2026-01-08T03-10Z
mount_disk
after_gen=$(find "$G" -mindepth 1 -maxdepth 1 -name 'gen-*' -printf '%f\n' | sort)
eq "every old daily generation kept (deletion paused by the old suspect)" "" "$(comm -23 <(echo "$before_gen") <(echo "$after_gen"))"
eq "every old long-retention copy kept" "" "$(comm -23 <(echo "$before_long") <(find "$G" -mindepth 1 -maxdepth 1 -name 'uzun-*' -printf '%f\n' | sort))"
ok "new generation published as nesil/gen-<id>" test -d "$G/gen-2026-01-08T03-10Z"
ok "pin kept" test -e "$A/pin/2026-01-02T03-10Z"
ok "old suspect still flagged, not cleared" sh -c "test -e $A/supheli/2026-01-06T03-10Z && ! test -e $A/temiz/2026-01-06T03-10Z"
eq "top level names unchanged" "denetim nesil" "$(find "$M" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//')"
eq "audit area names unchanged" "liste meta pin supheli temiz" "$(find "$A" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//')"
eq "stored list format" "# purser-list 1" "$(head -1 "$A/liste/2026-01-08T03-10Z.list")"
ok "meta keys bayt/dosya/sure" sh -c "grep -q '^bayt=' $A/meta/2026-01-08T03-10Z && grep -q '^dosya=' $A/meta/2026-01-08T03-10Z && grep -q '^sure=' $A/meta/2026-01-08T03-10Z"
ok "generations read-only" sh -c "btrfs property get -ts $G/gen-2026-01-08T03-10Z ro | grep -q true"
umount_disk
$P status > "$LOGDIR/compat-status2.txt" 2>&1
ok "status after the night: old suspect and its reason" sh -c "grep -q '^Suspect: 2026-01-06T03-10Z' $LOGDIR/compat-status2.txt && grep -q 'değişmemesi gereken' $LOGDIR/compat-status2.txt"
ok "status: deletion paused" grep -q '^Deletion paused for' "$LOGDIR/compat-status2.txt"
ok "status: last sound before the suspect" grep -q '^Last sound generation: 2026-01-05T03-10Z' "$LOGDIR/compat-status2.txt"
$P firstboot >/dev/null 2>&1; eq "a second firstboot is a no-op" 0 $?
done_testing
