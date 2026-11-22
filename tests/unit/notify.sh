#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Notifications: the box raises the text locally and sends only the event name to the server
# through the gate ("note <event>"); unpaired or unreachable means queued, later flushed in order.
# Nothing the server wrote reaches a message.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core

clear_notes
notify test urgent N_TEST
eq "raised: text" "Test message." "$(bodies | tail -1)"
eq "raised: priority" urgent "$(last_prio)"
eq "delivered: the event name only" test "$(delivered | tail -1)"
ok "the gate records the box id" grep -q " LAB2 test$" "$NOTES"
notify list_rejected high N_LIST_REJECTED $'2026-03-01T03-10Z\a|evil\r\nInjected: line' $'LIST_LINE\e[31m'
b=$(bodies | tail -1)
ok "no control characters in the raised text" not grep -qP '[\x00-\x1f\x7f]' <<< "$b"
ok "no '|' in the raised text" not grep -qF '|' <<< "$b"
eq "delivered: list_rejected" list_rejected "$(delivered | tail -1)"
notify 'Bad Event;rm' default N_TEST
eq "an event outside the alphabet travels as 'other'" other "$(delivered | tail -1)"
ok "the gate never stored the raw name" not grep -qF 'Bad' "$NOTES"

# queue: not paired -> queued; paired again -> flushed in order with the original time
clear_notes
SERVER=""
notify late high N_LATE 31
notify late high N_LATE 32
eq "two notifications queued" 2 "$(wc -l < "$ST_NOTIFY_QUEUE")"
eq "nothing delivered while unpaired" 0 "$(delivered | grep -c .)"
SERVER=127.0.0.1
notify_flush
eq "queue flushed" 2 "$(delivered | grep -c '^late$')"
ok "queue file removed" not test -e "$ST_NOTIFY_QUEUE"

# reminders of the hourly tick
printf 'BUILD_DATE=%s\n' "$(( $(date +%s) - 200 * 86400 ))" > /run/purser-test/image-release
conf IMAGE_RELEASE /run/purser-test/image-release
clear_notes
$P tick >/dev/null 2>&1; $P tick >/dev/null 2>&1
eq "image older than 6 months: one reminder" 1 "$(ncount "SD card image is 6 months old")"
unconf IMAGE_RELEASE
printf 'state=done\n' > "$ST/setup"; rm -f "$ST/code.hash" "$ST"/sent.code_missing
clear_notes; $P tick >/dev/null 2>&1; $P tick >/dev/null 2>&1
eq "no operation code: one weekly reminder" 1 "$(ncount "No operation code is set")"
rm -f "$ST/setup"
done_testing
