#!/bin/bash
# End to end: real gate (sshd + purser-gate + rrsync), real purser-source, real box core with
# the systemd-run sandbox, real btrfs; relay and LUKS simulated.
. /src/tests/lib/assert.sh
. /src/tests/lab/data.sh
bash /src/tests/lab/setup.sh reset-all >/dev/null
conf() { sed -i "/^$1=/d" /etc/purser/purser.conf; echo "$1=\"$2\"" >> /etc/purser/purser.conf; }
conf KEEP_DAILY 4
P=/usr/local/sbin/purser
M=/srv/purser
G=$M/nesil
last() { sed -n 's/^result=//p' /var/lib/purser/last-run; }
mount_disk() { /run/sim/on-relay 1; echo 1 > /run/sim/relay; mount /run/sim/by-uuid/test-0001 $M; }
umount_disk() { umount $M; /run/sim/on-relay 0; echo 0 > /run/sim/relay; }
ids=(2026-02-04T03-10Z 2026-02-05T03-10Z 2026-02-06T03-10Z 2026-02-07T03-10Z 2026-02-08T03-10Z 2026-02-09T03-10Z 2026-02-10T03-10Z)

src_init
publish_generation "${ids[0]}"
$P run > /run/purser-test/n1.log 2>&1; rc=$?
eq "night 1 exits 0" 0 "$rc"
eq "night 1 result" tamam "$(last)"
eq "relay off after the window" 0 "$(cat /run/sim/relay)"
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
ons=$(cat /run/sim/relay-ons)
$P run > /run/purser-test/n-none.log 2>&1
eq "no generation: result" no_generation "$(last)"
eq "no generation: disk never powered" "$ons" "$(cat /run/sim/relay-ons)"
ok "no generation: notified" grep -q 'produced no generation' /run/purser-test/notify.log

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
head -c 24M /dev/urandom > /srv/src/dumps/big-20260214.bin
publish_generation "$id"
conf RSYNC_BWLIMIT 2000
( $P run >/dev/null 2>&1 ) & bg=$!
for _ in $(seq 1 40); do sleep 0.5; [ -d $M/hazirlik ] && [ -n "$(find $M/hazirlik/dumps -name '*.purser-partial*' -o -name 'big-*' 2>/dev/null | head -1)" ] && break; done
sleep 2; systemctl kill --signal=KILL 'run-*.service' >/dev/null 2>&1 || true
wait $bg
eq "interrupted: result partial" partial "$(last)"
sed -i '/^RSYNC_BWLIMIT=/d' /etc/purser/purser.conf
$P run >/dev/null 2>&1
eq "interrupted: completed next run" "$id" "$(cat /var/lib/purser/son-yayin)"
mount_disk
ok "interrupted: no partial-dir left in the generation" sh -c "[ -z \"\$(find $G/gen-$id -name .purser-partial)\" ]"
umount_disk

# status prints the main lines
$P status > /run/purser-test/status.txt 2>&1
ok "status: last sound line" grep -q 'Last sound generation: ' /run/purser-test/status.txt
ok "status: disk line" grep -q '^Disk: ' /run/purser-test/status.txt
done_testing
