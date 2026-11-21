#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Fake clean: the server serves damaged content with valid hashes and clean=yes.
# Expected: the box keeps it (it cannot know), and nothing old is deleted.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
f=$(find /srv/src/dumps -type f -name 'dump-2026*' | sort | tail -1); rel=dumps/${f##*/}
good=$(sha256sum < "$f" | cut -c1-64)
night_activity 20260303 2
head -c 2048 /dev/zero > "$f"                  # "encrypted" by the attacker, plausible size
publish_generation 2026-03-03T03-10Z
set_header 2026-03-03T03-10Z clean yes
run_box fake
ok "the damaged generation is kept (the box cannot know)" grep -qE '^(tamam|uyari)$' <<< "$(last)"
eq "nothing old was deleted" "gen-2026-03-01T03-10Z gen-2026-03-02T03-10Z gen-2026-03-03T03-10Z" "$(gens 'gen-*' | tr '\n' ' ' | sed 's/ $//')"
mount_disk
eq "the previous night still has the good content" "$good" "$(sha256sum < "$G/gen-2026-03-02T03-10Z/$rel" | cut -c1-64)"
ok "published generations are read-only" sh -c "btrfs property get -ts $G/gen-2026-03-02T03-10Z ro | grep -q true"
umount_disk
done_testing
