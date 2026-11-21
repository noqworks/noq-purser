# shellcheck shell=bash
# Self-test: the disk is on USB, its link speed, SMART can be read through the bridge, the
# network reaches the gate, the clock is synchronised. One PASS/FAIL line each; returns the
# number of failures. Reads only; the disk stays locked.

cmd_selftest() {
  local fails=0 dev speed t c
  st_line() { if [ "$1" = 0 ]; then say "  PASS  $2"; else say "  FAIL  $2"; fails=$(( fails + 1 )); fi; }
  say "$(msg ST_TITLE)"

  # 1. disk on USB (the configured one if there is a configuration, else any)
  if [ -n "$LUKS_UUID" ]; then
    t=1; disk_wait 5 && t=0; st_line $t "$(msg ST_DISK_SEEN)"
    dev=$(disk_dev || true)
  else
    dev=$(usb_disks | awk '{ print $1; exit }' || true)
    t=1; [ -n "$dev" ] && t=0; st_line $t "$(msg ST_DISK_SEEN_USB "${dev:-none}")"
  fi
  # 2. link speed: High Speed or better
  if [ -n "$dev" ]; then
    speed=$(usb_speed "$dev" 2>/dev/null || echo "?")
    t=1; [[ $speed =~ ^[0-9]+$ ]] && [ "$speed" -ge 480 ] && t=0; st_line $t "$(msg ST_USB_SPEED "$speed")"
  else
    st_line 1 "$(msg ST_USB_SPEED "?")"
  fi
  # 3. SMART through the USB-SATA bridge
  t=1
  if [ -n "$dev" ] && command -v smartctl >/dev/null 2>&1; then
    local rc=0; smartctl -d sat -i "$dev" >/dev/null 2>&1 || rc=$?
    [ $(( rc & 3 )) -eq 0 ] && t=0
  fi
  st_line $t "$(msg ST_SMART)"
  # 4. network: an address, a default route, the gate's port answers
  t=1
  if awk '$2 == "00000000" { f = 1 } END { exit !f }' /proc/net/route 2>/dev/null && [ -n "$SERVER" ] \
     && timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$SERVER" "$SERVER_PORT" 2>/dev/null; then t=0; fi
  st_line $t "$(msg ST_NETWORK "${SERVER:-?}" "$SERVER_PORT")"
  # 5. clock
  c=$(clock_state)
  t=1; [ "$c" = ok ] && t=0; st_line $t "$(msg ST_CLOCK "$(msg "CLOCK_${c^^}")")"

  [ -n "$(board_led)" ] && { say "$(msg ST_LED)"; led_show alarm; sleep 3; }
  led_update
  say "$(msg ST_RESULT "$fails")"
  return "$fails"
}
