# shellcheck shell=bash
# Hourly tick (LED, delay alarm, reminders, clock, disk left open) and the console status page.

image_built() { kv_get "$IMAGE_RELEASE" BUILD_DATE; }

last_sound_age_h() {
  local s; s=$(cat "$ST_LAST_SOUND" 2>/dev/null || true)
  valid_id "$s" || return 1
  echo $(( ( $(now) - $(id_epoch "$s") ) / 3600 ))
}

# One colour, one meaning (MIMARI §8). Priority: suspect > fault > (code lock: drawn by purser-light)
# > warning > pulling / checking (set by the nightly job while it runs) > done > ready.
led_update() {
  local result age
  result=$(kv_get "$ST_LAST_RUN" result)
  if [ -z "$SERVER" ] || [ -z "$LUKS_UUID" ] || [ "$(kv_get "$ST_SETUP" state)" != "done" ]; then
    led_show setup; light_set unpaired; return 0
  fi
  if [ -s "$ST_SUSPECT_FLAG" ]; then led_show alarm; light_set suspect; return 0; fi
  # no disk on USB: the nightly job cannot run, whatever the last result was
  if ! disk_present; then led_show alarm; light_set fault disk; return 0; fi
  case $result in
    list_rejected|rejected_tree|tree_mismatch) led_show alarm; light_set suspect; return 0 ;;
    verify_failed) led_show alarm; light_set fault verify; return 0 ;;
    disk_error|disk_full) led_show alarm; light_set fault disk; return 0 ;;
    list_fetch_failed) led_show alarm; light_set fault server; return 0 ;;
  esac
  if ! age=$(last_sound_age_h); then led_show setup; light_set ready; return 0; fi
  if [ "$result" = clock_untrusted ]; then
    led_show warn; light_set warning clock
  elif [ "$result" = no_generation ] || [ "$age" -ge "$LATE_H" ]; then
    led_show warn; light_set warning server
  elif [ "$result" = uyari ] || [ "$result" = partial ]; then
    led_show warn; light_set warning
  elif [ "$age" -lt 20 ]; then
    led_show ok; light_set 'done'
  else
    led_show ok; light_set ready
  fi
}
systemd_up() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

# A nightly job or a first fill holds LOCK_FILE for its whole run.
job_running() {
  ! { flock -n 9; } 9>"$LOCK_FILE"
}

tick() {
  notify_flush || true
  if systemd_up && [ "$(kv_get "$ST_SETUP" state)" = "done" ] && ! systemctl -q is-enabled purser.timer 2>/dev/null; then
    [ "$(cat "$ST_TIMER_OFF_SENT" 2>/dev/null)" = "$(today)" ] || {
      notify timer_off high N_TIMER_OFF; today > "$ST_TIMER_OFF_SENT"; }
  fi
  local s age built c
  c=$(clock_check)
  s=$(cat "$ST_LAST_SOUND" 2>/dev/null || true)
  # the delay alarm needs a clock it can believe
  if [ "$c" = ok ] && age=$(last_sound_age_h) && [ "$age" -ge "$LATE_H" ]; then
    [ "$(cat "$ST_LATE_SENT" 2>/dev/null)" = "$s" ] || { notify late high N_LATE "$age"; echo "$s" > "$ST_LATE_SENT"; }
  fi
  built=$(image_built)
  if [[ $built =~ ^[0-9]+$ ]] && [ $(( ( $(now) - built ) / 86400 )) -ge "$IMAGE_MAX_DAYS" ] && due_once image_age $(( 30 * 86400 )); then
    notify image_age default N_IMAGE_AGE "$(( ( $(now) - built ) / 86400 / 30 ))"
  fi
  if ! code_is_set && [ "$(kv_get "$ST_SETUP" state)" = "done" ] && due_once code_missing $(( 7 * 86400 )); then
    notify code_missing default N_CODE_MISSING
  fi
  disk_left_open
  job_running || led_update   # a running job owns the light (pulling / checking)
}

# Outside a job and outside a "disk-on" session the disk is closed. If it is not, close it.
disk_left_open() {
  disk_is_open || return 0
  ( flock -n 9 || exit 1 ) 9>"$LOCK_FILE" || return 0
  if systemd_up && systemctl -q is-active purser-disk-off.timer 2>/dev/null; then return 0; fi
  log "disk found open outside a job; closing it"
  disk_close || true
}

# One look at the clock (see clock_state in hw.sh); alarms at most once a day per kind.
clock_check() {   # prints the state
  local c
  c=$(clock_state)
  case $c in
    ok) rm -f "$ST_CLOCK_SENT" ;;
    *)  if [ "$(cat "$ST_CLOCK_SENT" 2>/dev/null)" != "$c $(today)" ]; then
          clock_notify "$c"; echo "$c $(today)" > "$ST_CLOCK_SENT"
        fi ;;
  esac
  echo "$c"
}
clock_notify() {   # clock_notify <state>
  case $1 in
    jump) notify clock_jump high N_CLOCK_JUMP "$(( $(awk '{ print $2 }' "$RUN_DIR/clock.jump" 2>/dev/null || echo 0) / 60 ))" ;;
    disagree) notify clock_jump high N_CLOCK_DISAGREE "$(( $(cat "$RUN_DIR/clock.diff" 2>/dev/null || chrony_worst_offset) / 60 ))" ;;
    unsynced) notify clock_unsynced default N_CLOCK_UNSYNCED ;;
    early) notify clock_unsynced high N_CLOCK_EARLY ;;
  esac
}

ago() {   # ago <epoch> -> "N h" / "N days"
  local d=$(( $(now) - $1 ))
  if [ "$d" -lt 172800 ]; then msg T_HOURS "$(( d / 3600 ))"; else msg T_DAYS "$(( d / 86400 ))"; fi
}

cmd_status() {
  local s v built r id at used total suspects pending f c
  c=$(clock_state)
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
    elif [ -s "$ST_SUSPECT_REASONS" ]; then say "  $(reasons_text "$(cat "$ST_SUSPECT_REASONS")")"
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
  if disk_is_open; then say "$(msg S_DISK_OPEN)"; else say "$(msg S_DISK_CLOSED)"; fi
  v=$(kv_get "$ST_MAINT" usb_reset_at)
  [[ $v =~ ^[0-9]+$ ]] && say "$(msg S_USB_RESET "$(date -d "@$v" '+%F %H:%M')")"
  say "$(msg S_CLOCK "$(msg "CLOCK_${c^^}")")"
}
