#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Ceiling and acknowledgement tampering on the server: no effect on the box.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
first_night 2026-03-01T03-10Z
night 2026-03-02T03-10Z
rm -f /srv/server/ack/*
printf 'supheli 2099-01-01T00:00:00Z\n' > /srv/server/ack/2026-03-01T03-10Z
rm -rf "$SG/2026-03-01T03-10Z" "$SG/2026-03-01T03-10Z.list" "$SG/2026-03-02T03-10Z" "$SG/2026-03-02T03-10Z.list"
night 2026-03-03T03-10Z
eq "next night as usual" tamam "$(last)"
eq "every generation still on the box" 3 "$(gens 'gen-*' | wc -l)"
ok "forged acks changed nothing on the box" not grep -q supheli "$ST/last-run"
# a forged acknowledgement from the future: the server's own ceiling now deletes every new
# generation right after publishing it. The box gets nothing new, and loses nothing.
printf 'tamam 2099-01-01T00:00:00Z\n' > /srv/server/ack/2099-01-01T00-00Z
for i in 4 5; do
  clear_notes; night "2026-03-0${i}T03-10Z"
  ok "night $i: nothing to fetch (result $(last))" grep -qE '^(list_fetch_failed|no_generation)$' <<< "$(last)"
done
ok "the box reports it" notified "Could not fetch the list"
eq "the box keeps all of its own generations" 3 "$(gens 'gen-*' | wc -l)"
done_testing
