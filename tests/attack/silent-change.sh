#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Silent change: content changes while the server's list keeps the old hash, or while size and
# modification time are kept. ctime and the list difference catch it: suspect.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
# (a) the list lies: content changed, list still carries the old hash
f=$(find /srv/src/pgdemo/backup/demo -path '*F/pg_data/base/1/1259.zst' | sort | head -1)
rel=pgdemo/${f#/srv/src/pgdemo/}
night_activity 20260303 2
old=$(hash_of 2026-03-02T03-10Z "$rel")
head -c "$(stat -c %s "$f")" /dev/urandom > "$f.x"; mv "$f.x" "$f"
publish_generation 2026-03-03T03-10Z
sed -i "s|^[0-9a-f]\{64\}  $rel\$|$old  $rel|" "$(list_of 2026-03-03T03-10Z)"
clear_notes; run_box lie
eq "list lie: result" supheli "$(last)"
ok "list lie: named" notified "files changed while the server's list said they did not"
mount_disk
eq "the box's own list records what is really on the disk" "$(sha256sum < "$G/gen-2026-03-03T03-10Z/$rel" | cut -c1-64)" \
  "$(grep -F "  $rel" "$A/liste/2026-03-03T03-10Z.list" | cut -c1-64)"
umount_disk
# (b) size and time kept: rsync's quick check would skip it
g=$(find /srv/src/borgdemo/data -type f | sort | head -1)
night_activity 20260304 3
head -c "$(stat -c %s "$g")" /dev/urandom > "$g.x"; touch -r "$g" "$g.x"; mv "$g.x" "$g"
rm -f /srv/server/cache/*.cache                      # the server hashes everything again
publish_generation 2026-03-04T03-10Z
clear_notes; run_box silent
eq "silent change: result" supheli "$(last)"
ok "silent change: named" notified "files changed with size and time kept"
done_testing
