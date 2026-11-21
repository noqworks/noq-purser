#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Hardware layer on the fake sysfs tree: USB disk discovery, link speed, USB reset, board LED.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
S=/run/sim/sys L=/run/sim/sys/class/leds/green:status U=/run/sim/sys/bus/usb/devices/1-1
dev=$(cat /run/sim/loopdev)

out=$(usb_disks)
eq "usb_disks lists the one USB disk" 1 "$(wc -l <<< "$out")"
ok "usb_disks: device, size, model" grep -qE "^$dev [0-9]+ TestDisk SSD$" <<< "$out"
eq "usb_port_of" 1-1 "$(usb_port_of "$dev")"
eq "usb_speed" 480 "$(usb_speed "$dev")"
eq "usb_storage_ports" 1-1 "$(usb_storage_ports)"
ok "a non-USB block device is not listed" not grep -q zram <<< "$(install -d "$S/devices/virtual/block/zram0"; echo 1 > "$S/devices/virtual/block/zram0/size"; ln -s ../devices/virtual/block/zram0 "$S/block/zram0"; usb_disks)"

# reset: authorized 0 -> 1
echo 1 > "$U/authorized"; before=$(stat -c %y "$U/authorized")
usb_reset 1-1; eq "usb_reset via authorized" 0 $?
eq "authorized is 1 again" 1 "$(cat "$U/authorized")"
ok "authorized was written" test "$(stat -c %y "$U/authorized")" != "$before"
# fallback: no authorized file -> unbind/bind at the USB core
mv "$U/authorized" /run/sim/authorized.saved
: > "$S/bus/usb/drivers/usb/bind"; : > "$S/bus/usb/drivers/usb/unbind"
usb_reset 1-1; eq "usb_reset via unbind/bind" 0 $?
eq "unbind got the port" 1-1 "$(cat "$S/bus/usb/drivers/usb/unbind")"
eq "bind got the port" 1-1 "$(cat "$S/bus/usb/drivers/usb/bind")"
mv /run/sim/authorized.saved "$U/authorized"
usb_reset '1-1;reboot'; ok "a malformed port is refused" test $? -ne 0
usb_reset '../../x'; ok "a path as port is refused" test $? -ne 0

# LED
eq "board_led picks the status LED" "$L" "$(board_led)"
led_show ok;    eq "ok: steady on" "none 1" "$(cat "$L/trigger") $(cat "$L/brightness")"
led_show warn;  eq "warn: slow blink" "timer 1000 1000" "$(cat "$L/trigger") $(cat "$L/delay_on") $(cat "$L/delay_off")"
led_show alarm; eq "alarm: fast blink" "timer 150 150" "$(cat "$L/trigger") $(cat "$L/delay_on") $(cat "$L/delay_off")"
led_show setup; eq "setup: heartbeat" heartbeat "$(cat "$L/trigger")"
led_show off;   eq "off: dark" "none 0" "$(cat "$L/trigger") $(cat "$L/brightness")"
echo sentinel > "$L/trigger"
BOARD_LED=none; led_show alarm; eq "BOARD_LED=none leaves the LED alone" sentinel "$(cat "$L/trigger")"
BOARD_LED=green:status; led_show ok; eq "BOARD_LED by name" none "$(cat "$L/trigger")"
BOARD_LED=nonexistent; led_show alarm; eq "unknown BOARD_LED is silent" 0 $?
BOARD_LED=auto
mv "$S/class/leds" /run/sim/leds.saved; install -d "$S/class/leds/mmc0::" 
eq "no usable LED: board_led is empty" "" "$(board_led)"
led_show alarm; eq "no LED: led_show is silent" 0 $?
rm -rf "$S/class/leds"; led_show warn; eq "no leds class at all: silent" 0 $?
mv /run/sim/leds.saved "$S/class/leds"
done_testing
