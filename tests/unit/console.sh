#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# The restricted serial console: fixed commands only; digits go to the core, never stored.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
FC=/run/purser-test/fakecore CL=/run/purser-test/console.log
cat > "$FC" <<'X'
#!/bin/bash
echo "ARGS $*" >> /run/purser-test/console.log
case $1 in clear|pin|disk-on|new-code) read -r l; echo "STDIN $l" >> /run/purser-test/console.log ;; esac
X
chmod 0755 "$FC"; : > "$CL"
CODE="4821 0937 5562"
timeout 8 env PURSER_BIN="$FC" /usr/local/sbin/purser-console > "$LOGDIR/console.out" 2>&1 <<X
status
help
rm -rf /
status; reboot
\$(reboot)
bash
clear ../../etc/passwd
pin 2026-01-02T03-10Z extra
SETUP
disk-on now
clear 2026-01-01T03-10Z
$CODE
shell
X
want="ARGS status
ARGS status
ARGS clear 2026-01-01T03-10Z
STDIN $CODE
ARGS shell"
eq "only fixed commands reached the core" "$want" "$(cat "$CL")"
eq "garbage answered with '?'" 8 "$(grep -c '^purser> ?' "$LOGDIR/console.out")"
ok "help is printed" grep -q 'Commands:' "$LOGDIR/console.out"
ok "the code is not stored anywhere on the box" not grep -rqsE '4821 ?0937 ?5562' /var/lib/purser /etc/purser /run/purser /tmp /var/tmp
done_testing
