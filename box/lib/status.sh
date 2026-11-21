# shellcheck shell=bash
# Hourly tick (LED, delay alarm, reminders, clock) and the status page of the console.

image_built() { kv_get "$IMAGE_RELEASE" BUILD_DATE; }

last_sound_age_h() {
  local s; s=$(cat "$ST_LAST_SOUND" 2>/dev/null || true)
  valid_id "$s" || return 1
  echo $(( ( $(now) - $(id_epoch "$s") ) / 3600 ))
}

led_update() {
  local result age
  result=$(kv_get "$ST_LAST_RUN" result)
  if ! age=$(last_sound_age_h); then led_set both; return 0; fi
  if [ -s "$ST_SUSPECT_FLAG" ]; then led_set red; return 0; fi
  case $result in
    list_rejected|rejected_tree|tree_mismatch|verify_failed|disk_error|disk_full|list_fetch_failed) led_set red; return 0 ;;
  esac
  if [ "$age" -ge "$LATE_H" ] || [ "$result" = uyari ] || [ "$result" = partial ] || [ "$result" = no_generation ]; then
    led_set red-blink
  else
    led_set green
  fi
}

systemd_up() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

tick() {
  notify_flush || true
  if systemd_up && [ "$(kv_get "$ST_SETUP" state)" = "done" ] && ! systemctl -q is-enabled purser.timer 2>/dev/null; then
    [ "$(cat "$ST_TIMER_OFF_SENT" 2>/dev/null)" = "$(today)" ] || {
      notify timer_off high N_TIMER_OFF; today > "$ST_TIMER_OFF_SENT"; }
  fi
  local s age built
  s=$(cat "$ST_LAST_SOUND" 2>/dev/null || true)
  if age=$(last_sound_age_h) && [ "$age" -ge "$LATE_H" ]; then
    [ "$(cat "$ST_LATE_SENT" 2>/dev/null)" = "$s" ] || { notify late high N_LATE "$age"; echo "$s" > "$ST_LATE_SENT"; }
  fi
  built=$(image_built)
  if [[ $built =~ ^[0-9]+$ ]] && [ $(( ( $(now) - built ) / 86400 )) -ge "$IMAGE_MAX_DAYS" ] && due_once image_age $(( 30 * 86400 )); then
    notify image_age default N_IMAGE_AGE "$(( ( $(now) - built ) / 86400 / 30 ))"
  fi
  clock_check
  led_update
}

# Network time that disagrees with the box clock by more than CLOCK_JUMP_MAX is not taken
# (chrony: no step after start, maxchange); the alarm tells someone it is happening.
clock_check() {
  command -v chronyc >/dev/null 2>&1 || return 0
  local worst
  worst=$(chronyc -c sourcestats 2>/dev/null | awk -F, '{ o = $7 + 0; if (o < 0) o = -o; if (o > m) m = o } END { printf "%d", m }')
  [[ $worst =~ ^[0-9]+$ ]] || return 0
  if [ "$worst" -gt "$CLOCK_JUMP_MAX" ] && due_once clock_jump 86400; then
    notify clock_jump high N_CLOCK_JUMP "$(( worst / 60 ))"
  fi
  # keep the DS3231 right while network time agrees with it
  if [ "$worst" -lt 5 ] && chronyc -c tracking 2>/dev/null | awk -F, '$NF != "Not synchronised" { f = 1 } END { exit !f }' \
     && due_once rtc_write 86400; then
    local rtc; rtc=$(rtc_device 2>/dev/null || true)
    [ -n "$rtc" ] && [ "$(gpio_mode)" != sim ] && hwclock --systohc -f "$rtc" 2>/dev/null || true
  fi
  return 0
}

ago() {   # ago <epoch> -> "N h" / "N days"
  local d=$(( $(now) - $1 ))
  if [ "$d" -lt 172800 ]; then msg T_HOURS "$(( d / 3600 ))"; else msg T_DAYS "$(( d / 86400 ))"; fi
}

cmd_status() {
  local s v built r id at used total suspects pending f
  say "NOQ Purser $PURSER_VERSION"
  built=$(image_built)
  if [[ $built =~ ^[0-9]+$ ]]; then say "$(msg S_IMAGE "$(date -u -d "@$built" +%F)" "$(ago "$built")")"; fi
  s=$(cat "$ST_LAST_SOUND" 2>/dev/null || true)
  if valid_id "$s"; then say "$(msg S_LAST_SOUND "$s" "$(ago "$(id_epoch "$s")")")"; else say "$(msg S_LAST_SOUND_NONE)"; fi
  r=$(kv_get "$ST_LAST_RUN" result); id=$(kv_get "$ST_LAST_RUN" id); at=$(kv_get "$ST_LAST_RUN" at)
  if [ -n "$r" ]; then
    say "$(msg S_LAST_RUN "$(msg "RUN_${r^^}")" "${id:--}" "$(date -d "@$at" '+%F %H:%M')")"
  fi
  suspects=$(cat "$ST_SUSPECT_FLAG" 2>/dev/null || true)
  if [ -n "$suspects" ]; then
    say "$(msg S_SUSPECT "$suspects")"
    if [ -r "$AUDIT/supheli/$suspects" ]; then say "  $(reasons_text "$(cat "$AUDIT/supheli/$suspects")")"
    else
      v=$(kv_get "$ST_LAST_RUN" detail); [ -n "$v" ] && say "  $(reasons_text "$(tr ' ' '\n' <<< "$v")")"
    fi
    v=$(kv_get "$ST_MAINT" paused_since)
    [[ $v =~ ^[0-9]+$ ]] && say "$(msg S_PAUSED "$(( ( $(now) - v ) / 86400 ))")"
  else
    say "$(msg S_NO_SUSPECT)"
  fi
  pending=$(cat "$ST_PENDING_ACK" 2>/dev/null || true)
  [ -n "$pending" ] && say "$(msg S_PENDING_ACK "$pending")"
  used=$(kv_get "$ST_DISK_USAGE" used); total=$(kv_get "$ST_DISK_USAGE" total); at=$(kv_get "$ST_DISK_USAGE" at)
  if [[ $total =~ ^[0-9]+$ ]] && [ "$total" -gt 0 ]; then
    say "$(msg S_DISK "$(human_gb "$used")" "$(human_gb "$total")" "$(( used * 100 / total ))" "$(date -d "@$at" +%F)")"
  fi
  f=$ST_SMART
  if [ -r "$f" ]; then
    say "$(msg S_SMART "$(kv_get "$f" health)" "$(kv_get "$f" hours)" "$(kv_get "$f" realloc)" "$(kv_get "$f" life)" "$(date -d "@$(kv_get "$f" at)" +%F)")"
  else say "$(msg S_SMART_NONE)"; fi
  v=$(kv_get "$ST_MAINT" scrub_done)
  if [[ $v =~ ^[0-9]+$ ]]; then say "$(msg S_SCRUB "$(date -d "@$v" +%F)")"; else say "$(msg S_SCRUB_NONE)"; fi
  if code_is_set; then
    v=$(code_locked_for); if [ "$v" -gt 0 ]; then say "$(msg S_CODE_LOCKED "$(( (v + 59) / 60 ))")"; else say "$(msg S_CODE_SET)"; fi
  else say "$(msg S_CODE_NONE)"; fi
  [ -s "$ST_NOTIFY_QUEUE" ] && say "$(msg S_QUEUE "$(wc -l < "$ST_NOTIFY_QUEUE")")"
  say "$(msg S_SENSE "$(sense_get)")"
}
