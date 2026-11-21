# shellcheck shell=bash
# Hardware self-test: relay and voltage sense, LEDs, RTC, disk on USB and its link speed.
# Prints one PASS/FAIL line per item; returns the number of failures.

cmd_selftest() {
  local fails=0 dev speed rtc t
  st_line() { if [ "$1" = 0 ]; then say "  PASS  $2"; else say "  FAIL  $2"; fails=$(( fails + 1 )); fi; }
  say "$(msg ST_TITLE)"
  if disk_is_open; then say "$(msg E_DISK_OPEN)"; return 1; fi

  relay_set 0; sleep 1
  t=1; wait_sense 0 5 && t=0; st_line $t "$(msg ST_SENSE_OFF)"
  relay_set 1
  t=1; wait_sense 1 10 && t=0; st_line $t "$(msg ST_SENSE_ON)"
  if [ -n "$LUKS_UUID" ]; then
    for (( i = 0; i < DISK_WAIT; i++ )); do disk_present && break; sleep 1; done
    t=1; disk_present && t=0; st_line $t "$(msg ST_DISK_SEEN)"
    dev=$(disk_dev || true)
  else
    sleep 8
    dev=$(lsblk -dnpo NAME,TRAN 2>/dev/null | awk '$2 == "usb" { print $1; exit }' || true)
    t=1; [ -n "$dev" ] && t=0; st_line $t "$(msg ST_DISK_SEEN_USB "${dev:-none}")"
  fi
  if [ -n "$dev" ]; then
    speed=$(usb_speed "$dev" || echo "?")
    t=1; [ "$speed" = 480 ] && t=0; st_line $t "$(msg ST_USB_SPEED "$speed")"
  fi
  relay_set 0
  t=1; wait_sense 0 10 && t=0; st_line $t "$(msg ST_SENSE_DROP)"

  say "$(msg ST_LEDS)"
  led_set green; sleep 2; led_set red; sleep 2; led_set both; sleep 2; led_set off; sleep 1

  rtc=$(rtc_device 2>/dev/null || true)
  if [ -n "$rtc" ]; then
    local r d
    r=$(hwclock -r -f "$rtc" 2>/dev/null || true)
    d=$(( $(date -d "$r" +%s 2>/dev/null || echo 0) - $(date +%s) )); d=${d#-}
    t=1; [ -n "$r" ] && [ "$d" -lt 120 ] && t=0
    st_line $t "$(msg ST_RTC "$rtc" "$d")"
  else
    st_line 1 "$(msg ST_RTC_NONE)"
  fi
  led_update
  say "$(msg ST_RESULT "$fails")"
  return "$fails"
}
