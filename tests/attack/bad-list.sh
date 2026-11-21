#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Bad list: path traversal, control character, duplicate path. Rejected; disk never unlocked.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
H=$(printf 'b%.0s' $(seq 1 64))
n=1
for bad in "$H  dumps/../../../etc/cron.d/x" "$H  ../outside" "$(printf '%s  dumps/a\033[2Jb' "$H")" "$(printf '%s  dumps/a\nb' "$H")" dup; do
  n=$((n + 1)); id=2026-03-0${n}T03-10Z
  publish_generation "$id"
  l=$(list_of "$id")
  if [ "$bad" = dup ]; then d=$(grep -v '^# ' "$l" | head -1); printf '%s\n' "$d" >> "$l"; else printf '%s\n' "$bad" >> "$l"; fi
  o=$(opens); clear_notes; run_box "bad-$n"
  eq "list $n rejected" list_rejected "$(last)"
  eq "list $n: disk never unlocked" "$o" "$(opens)"
  ok "list $n: notified" notified "breaks the format"
done
eq "nothing new published" "gen-2026-03-01T03-10Z" "$(gens 'gen-*')"
ok "nothing written outside the box's areas" not test -e /etc/cron.d/x
done_testing
