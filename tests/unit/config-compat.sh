#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# An older purser.conf still carries the keys of hardware this release removed (relay, voltage
# sense, external LEDs, GPIO). They must load and be ignored without an error.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
cat >> /etc/purser/purser.conf <<'X'
GPIO_CHIP=gpiochip9
GPIO_BASE=
GPIO_FIFO=/run/purser/gpio
RELAY_LINE=71
RELAY_ACTIVE_LOW=1
SENSE_LINE=75
LED_G_LINE=69
LED_R_LINE=72
GPIO_MODE="sim"
SIM_DIR="/run/sim"
X
$P status > "$LOGDIR/compat-status.txt" 2>&1; eq "status runs with the old keys" 0 $?
$P tick > "$LOGDIR/compat-tick.txt" 2>&1; eq "tick runs with the old keys" 0 $?
first_night 2026-03-01T03-10Z; eq "night runs with the old keys" 0 $?
eq "result" tamam "$(last)"
ok "no GPIO FIFO is created" not test -e /run/purser/gpio
ok "no purser-gpio program is installed" not test -e /usr/local/sbin/purser-gpio
ok "no purser-gpio unit is installed" not test -e /etc/systemd/system/purser-gpio.service
ok "no error about unknown keys" not grep -qiE 'unbound|unknown|error' "$LOGDIR/run-2026-03-01T03-10Z.log"
# the prototype installer's placeholder for "no disk yet"
sed -i 's/^LUKS_UUID=.*/LUKS_UUID=yok/' /etc/purser/purser.conf
$P status > "$LOGDIR/compat-yok.txt" 2>&1
ok "LUKS_UUID=yok counts as no disk (setup still missing the disk)" sh -c \
  "PURSER_LIB=/usr/local/lib/purser bash -c '. /usr/local/lib/purser/common.sh; load_config; [ -z \"\$LUKS_UUID\" ]'"
done_testing
