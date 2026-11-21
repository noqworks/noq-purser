#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Notifications: ntfy and webhook requests as the endpoint receives them, stripping of anything
# that is not plain text, the queue, and the reminders the hourly tick sends.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
cp "$NOTIFY" /run/purser-test/bildirim.saved

clear_notes
notify test urgent N_TEST
eq "ntfy: topic path" /purser-lab "$(last_path)"
eq "ntfy: title" "NOQ Purser" "$(last_header Title)"
eq "ntfy: priority" urgent "$(last_header Priority)"
eq "ntfy: tags" floppy_disk "$(last_header Tags)"
eq "ntfy: body" "Test message." "$(bodies | tail -1)"
notify test bogus N_TEST
eq "unknown priority falls back to default" default "$(last_header Priority)"

notify list_rejected high N_LIST_REJECTED $'2026-03-01T03-10Z\a|evil\r\nInjected: line' $'LIST_LINE\e[31m'
b=$(bodies | tail -1)
ok "no control characters reach a notification" not grep -qP '[\x00-\x1f\x7f]' <<< "$b"
ok "no '|' reaches a notification" not grep -qF '|' <<< "$b"
eq "the body stays one line" 1 "$(wc -l <<< "$b")"

# webhook
printf 'WEBHOOK_URL=https://ntfy.test/hooks/purser\nWEBHOOK_TOKEN=tok-123\n' > "$NOTIFY"
NOTIFY_KIND=webhook
notify disk_full urgent N_DISK_FULL
eq "webhook: path" /hooks/purser "$(last_path)"
eq "webhook: event header" disk_full "$(last_header X-Purser-Event)"
eq "webhook: priority header" urgent "$(last_header X-Purser-Priority)"
eq "webhook: bearer token" "Bearer tok-123" "$(last_header Authorization)"
ok "webhook: plain text body" grep -q '^text/plain' <<< "$(last_header Content-Type)"
printf 'WEBHOOK_URL=http://ntfy.test/hooks/purser\n' > "$NOTIFY"
n=$(wc -l < "$NLOG"); notify test default N_TEST
eq "webhook over plain http is refused" "$n" "$(wc -l < "$NLOG")"
printf 'WEBHOOK_URL=https://ntfy.test/hooks/purser\nWEBHOOK_TOKEN=bad token\n' > "$NOTIFY"
notify test default N_TEST
eq "token with a space is refused" "$n" "$(wc -l < "$NLOG")"
NOTIFY_KIND=ntfy; cp /run/purser-test/bildirim.saved "$NOTIFY"; rm -f "$ST_NOTIFY_QUEUE"

# queue: endpoint unreachable -> queued; later flushed in order with the original time
NOTIFY_CA=/nonexistent
notify late high N_LATE 31
notify late high N_LATE 32
eq "two notifications queued" 2 "$(wc -l < "$ST_NOTIFY_QUEUE")"
NOTIFY_CA=/etc/purser/test-ca.pem
clear_notes; notify_flush
eq "queue flushed" 2 "$(bodies | wc -l)"
ok "flushed notification carries its time" grep -qE '31 hours old\. \([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}Z\)' <<< "$(bodies | head -1)"
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
