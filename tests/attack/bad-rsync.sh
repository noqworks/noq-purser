#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Bad rsync answers: symlink, device file, FIFO, a file over the size ceiling. Rejected or
# never transferred; only the staging area is affected.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
id=2026-03-02T03-10Z; night_activity 20260302 1; publish_generation "$id"
ln -s /etc/shadow "$SG/$id/dumps/evil-link"
mknod "$SG/$id/dumps/evil-dev" b 7 200
mkfifo "$SG/$id/dumps/evil-fifo"
run_box specials
eq "specials not in the list: generation taken" tamam "$(last)"
mount_disk
eq "no symlink, device or FIFO arrived" "" "$(find "$G" \( -type l -o -type b -o -type c -o -type p \) -print)"
umount_disk
# listed specials: the tree cannot match the list
id=2026-03-03T03-10Z; night_activity 20260303 2; publish_generation "$id"
ln -s /etc/shadow "$SG/$id/dumps/evil-link2"
echo "$(printf 'c%.0s' $(seq 1 64))  dumps/evil-link2" >> "$(list_of "$id")"
run_box listed-link
eq "listed symlink: not published" tree_mismatch "$(last)"
# huge file over MAX_FILE_SIZE (64M in the lab)
id=2026-03-04T03-10Z; publish_generation "$id"
head -c 80M /dev/zero > "$SG/$id/dumps/huge.bin"; chgrp purser "$SG/$id/dumps/huge.bin"; chmod 0640 "$SG/$id/dumps/huge.bin"
relist "$id"
clear_notes; run_box huge
eq "file over the size ceiling: not published" tree_mismatch "$(last)"
ok "huge: notified" notified "does not match its list"
ok "huge: disk locked" locked
mount_disk
ok "huge file never landed on the disk" not test -e "$G/gen-$id/dumps/huge.bin"
ok "huge file not kept in staging either" sh -c "! find $M/hazirlik -name 'huge.bin*' -size +60M | grep -q ."
eq "published generations unchanged" "gen-2026-03-01T03-10Z gen-2026-03-02T03-10Z" "$(find "$G" -mindepth 1 -maxdepth 1 -name 'gen-*' -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//')"
cmp_ok=$(cd "$G/gen-2026-03-02T03-10Z" && sha256sum -c --quiet "$A/liste/2026-03-02T03-10Z.list" 2>&1 | grep -c FAILED)
eq "the last published generation still matches its list" 0 "$cmp_ok"
umount_disk
done_testing
