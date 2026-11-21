#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced helpers

# Stale source: the server says fresh=no (warning the same night); a source that does not
# change for 2 nights is a warning from the box itself.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
. /src/tests/attack/lib-attack.sh
lab_reset
cp /etc/purser/source.conf /run/purser-test/source.conf.saved
trap 'cp /run/purser-test/source.conf.saved /etc/purser/source.conf' EXIT
sed -i 's/^FRESH_MAX_H=.*/FRESH_MAX_H="1"/' /etc/purser/source.conf
src_init; publish_generation 2026-03-01T03-10Z
ok "server marks the list fresh=no" grep -qx '# fresh=no' "$(list_of 2026-03-01T03-10Z)"
clear_notes; run_box fresh-no
eq "fresh=no: warning, not suspect" uyari "$(last)"
ok "fresh=no: notified the same night" notified "the server reports a stale source (fresh=no)"
cp /run/purser-test/source.conf.saved /etc/purser/source.conf
publish_generation 2026-03-02T03-10Z; clear_notes; run_box same-1
eq "one night without change: no warning yet" 0 "$(ncount "has not changed")"
publish_generation 2026-03-03T03-10Z; clear_notes; run_box same-2
eq "second night without change: warning" uyari "$(last)"
ok "box names the stale source" notified "dumps has not changed for 2 nights"
ok "the box told the server" grep -q '^uyari ' /srv/server/ack/2026-03-03T03-10Z
done_testing
