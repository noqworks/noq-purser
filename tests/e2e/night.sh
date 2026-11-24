#!/bin/bash
# End to end: real gate (sshd + purser-gate + rrsync), real purser-source, real box core with
# the systemd-run sandbox, real btrfs; LUKS and the box's sysfs simulated.
. /src/tests/lib/assert.sh
. /src/tests/lab/data.sh
bash /src/tests/lab/setup.sh reset-all >/dev/null
conf() { sed -i "/^$1=/d" /etc/purser/purser.conf; echo "$1=\"$2\"" >> /etc/purser/purser.conf; }
conf KEEP_DAILY 4
P=purser_lab
M=/srv/purser
G=$M/nesil
last() { sed -n 's/^result=//p' /var/lib/purser/last-run; }
mount_disk() { mount "$(cat /run/sim/loopdev)" $M; }
umount_disk() { umount $M; }
locked() { ! mountpoint -q $M && [ ! -e /run/sim/mapper/purser ]; }
opens() { cat /run/sim/luks-opens 2>/dev/null || echo 0; }
ids=(2026-02-04T03-10Z 2026-02-05T03-10Z 2026-02-06T03-10Z 2026-02-07T03-10Z 2026-02-08T03-10Z 2026-02-09T03-10Z 2026-02-10T03-10Z)

src_init
publish_generation "${ids[0]}"
$P run > /run/purser-test/n1.log 2>&1; rc=$?
eq "night 1 exits 0" 0 "$rc"
eq "night 1 result" tamam "$(last)"
ok "disk locked after the window (no mapper, no mount)" locked
ok "ack written on the server" grep -q '^tamam ' "/srv/server/ack/${ids[0]}"
eq "last published" "${ids[0]}" "$(cat /var/lib/purser/son-yayin)"
eq "last sound" "${ids[0]}" "$(cat /var/lib/purser/son-saglam)"

for i in 1 2 3 4 5 6; do
  id=${ids[$i]}; night_activity "${id:0:4}${id:5:2}${id:8:2}" "$(date -u -d "${id:0:10}" +%u)"
  publish_generation "$id"
  $P run > "/run/purser-test/n$((i + 1)).log" 2>&1
  eq "night $((i + 1)) result" tamam "$(last)"
done

mount_disk
ok "generations are read-only" sh -c "btrfs property get -ts $G/gen-${ids[6]} ro | grep -q true"
ok "Sunday long-retention copy cut" test -d "$G/uzun-2026-02-08T03-10Z"
eq "long copy holds no WAL segments" 0 "$(find $G/uzun-2026-02-08T03-10Z/pgdemo/archive -name '*.zst' | wc -l)"
eq "long copy keeps one full backup" 1 "$(find $G/uzun-2026-02-08T03-10Z/pgdemo/backup/demo -mindepth 1 -maxdepth 1 -type d -name '*F' | wc -l)"
ok "long copy keeps borg intact" test -d "$G/uzun-2026-02-08T03-10Z/borgdemo/data"
eq "daily generations kept (KEEP_DAILY=4)" 4 "$(find $G -maxdepth 1 -name 'gen-*' | wc -l)"
ok "audit list stored" test -s "$M/denetim/liste/${ids[6]}.list"
ok "meta has the original keys" sh -c "grep -q '^bayt=' $M/denetim/meta/${ids[6]} && grep -q '^dosya=' $M/denetim/meta/${ids[6]} && grep -q '^sure=' $M/denetim/meta/${ids[6]}"
eq "staging removed after publish" no "$([ -e $M/hazirlik ] && echo yes || echo no)"
cmp_ok=$(cd "$G/gen-${ids[6]}" && sha256sum -c --quiet "$M/denetim/liste/${ids[6]}.list" 2>&1 | grep -c FAILED)
eq "published tree matches its list" 0 "$cmp_ok"
umount_disk

# no new generation: the disk is never powered, a notification goes out
ons=$(opens)
$P run > /run/purser-test/n-none.log 2>&1
eq "no generation: result" no_generation "$(last)"
eq "no generation: LUKS never opened" "$ons" "$(opens)"
journalctl --sync 2>/dev/null || true
ok "no generation: notified" bash -c "journalctl -q -t purser -o cat | grep -q 'produced no generation'"
ok "no generation: reached the server" grep -q " no_generation$" /srv/server/ack/.notes

# pending acknowledgement: the gate cannot write it, the next night sends it first
id=2026-02-11T03-10Z; night_activity 20260211 3; publish_generation "$id"
chmod 0550 /srv/server/ack; $P run >/dev/null 2>&1; chmod 0770 /srv/server/ack
ok "ack pending on the box" grep -q "^$id tamam" /var/lib/purser/bekleyen-ack
id2=2026-02-12T03-10Z; night_activity 20260212 4; publish_generation "$id2"
$P run >/dev/null 2>&1
ok "pending ack delivered next night" test -s "/srv/server/ack/$id2"
ok "pending ack file removed" not test -e /var/lib/purser/bekleyen-ack

# interrupted between snapshot and audit rename: the next run finishes it without refetching
id=2026-02-13T03-10Z; night_activity 20260213 5; publish_generation "$id"
PURSER_FAULT=after_snapshot $P run >/dev/null 2>&1
eq "fault: last published not advanced" "$id2" "$(cat /var/lib/purser/son-yayin)"
mountpoint -q $M && umount $M; rm -f /run/sim/mapper/purser
$P run >/dev/null 2>&1
eq "fault: recovered and published" "$id" "$(cat /var/lib/purser/son-yayin)"
eq "fault: result" tamam "$(last)"

# interrupted transfer: the half-filled staging area is kept and completed the next night
id=2026-02-14T03-10Z; night_activity 20260214 6
head -c 32M /dev/urandom > /srv/src/dumps/big-20260214.bin
publish_generation "$id"
conf RSYNC_BWLIMIT 2000
( $P run >/dev/null 2>&1 ) & bg=$!
# rsync writes the file under a temporary name (.big-...) while it is being transferred
for _ in $(seq 1 60); do sleep 0.5; [ -n "$(find $M/hazirlik/dumps -name '.big-*' 2>/dev/null | head -1)" ] && break; done
sleep 1; systemctl kill --signal=KILL 'run-*.service' >/dev/null 2>&1 || true
wait $bg
eq "interrupted: result partial" partial "$(last)"
sed -i '/^RSYNC_BWLIMIT=/d' /etc/purser/purser.conf
$P run >/dev/null 2>&1
eq "interrupted: completed next run" "$id" "$(cat /var/lib/purser/son-yayin)"
mount_disk
ok "interrupted: no partial-dir left in the generation" sh -c "[ -z \"\$(find $G/gen-$id -name .purser-partial)\" ]"
umount_disk

# read-back larger than the window: what was read is kept, the next window reads only the rest
id=2026-02-15T03-10Z   # no night activity: only new files, so nothing but the read-back differs
for n in 1 2 3 4 5 6; do head -c 2M /dev/urandom > "/srv/src/dumps/rb$n-20260215.bin"; done
publish_generation "$id"
PURSER_FAULT=readback_cut $P run > /run/purser-test/rb1.log 2>&1
eq "read-back cut: result partial" partial "$(last)"
ok "read-back cut: progress kept" test -s /var/lib/purser/geri-okuma
ok "read-back cut: not published" not grep -qx "$id" /var/lib/purser/son-yayin
ok "read-back cut: disk locked" locked
$P run > /run/purser-test/rb2.log 2>&1
eq "read-back resumed: published" "$id" "$(cat /var/lib/purser/son-yayin)"
eq "read-back resumed: result" tamam "$(last)"
ok "read-back resumed: earlier reads reused" grep -Eq 'read-back: [1-9][0-9]* file\(s\) already read back' /run/purser-test/rb2.log
ok "read-back progress cleared after publish" not test -e /var/lib/purser/geri-okuma
mount_disk
cmp_ok=$(cd "$G/gen-$id" && sha256sum -c --quiet "$M/denetim/liste/$id.list" 2>&1 | grep -c FAILED)
eq "read-back resumed: published tree matches its list" 0 "$cmp_ok"
umount_disk

# stopping the service that runs the core stops its sandboxes too, so nothing keeps the disk busy
id=2026-02-16T03-10Z; night_activity 20260216 1
head -c 32M /dev/urandom > /srv/src/dumps/big-20260216.bin
publish_generation "$id"
conf RSYNC_BWLIMIT 2000
systemd-run --quiet --unit=purser-owner-test /usr/local/sbin/purser run
sandboxes() { systemctl list-units --plain --no-legend --state=active,activating 'run-*.service' | wc -l; }
for _ in $(seq 1 60); do sleep 0.5; [ "$(sandboxes)" -gt 0 ] && break; done
ok "owner: a sandbox is running" test "$(sandboxes)" -gt 0
systemctl stop purser-owner-test
sleep 2
eq "owner stopped: no sandbox left" 0 "$(sandboxes)"
sed -i '/^RSYNC_BWLIMIT=/d' /etc/purser/purser.conf
mountpoint -q $M && umount $M; rm -f /run/sim/mapper/purser
$P run >/dev/null 2>&1
eq "owner: completed next run" "$id" "$(cat /var/lib/purser/son-yayin)"

# status prints the main lines
$P status > /run/purser-test/status.txt 2>&1
ok "status: last sound line" grep -q 'Last sound generation: ' /run/purser-test/status.txt
ok "status: disk line" grep -q '^Disk: ' /run/purser-test/status.txt
done_testing
