#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Mass encryption in place: every repository file rewritten, same names and sizes.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
find /srv/src -mindepth 2 -type f | while read -r f; do head -c "$(stat -c %s "$f")" /dev/urandom > "$f.enc"; mv "$f.enc" "$f"; done
publish_generation 2026-03-03T03-10Z; clear_notes; run_box encrypt
eq "result" supheli "$(last)"
ok "mass change named" notified "percent of the files were changed"
ok "pgBackRest immutable files named" notified "pgBackRest files in pgdemo that never change were changed"
ok "borg segments named" notified "borg segments in borgdemo that never change were changed"
ok "restic content hashes named" notified "restic objects in resticdemo do not match their content hash"
eq "older generations kept" 3 "$(gens 'gen-*' | wc -l)"
done_testing
