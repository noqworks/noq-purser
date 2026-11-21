# shellcheck shell=bash
# Maintenance inside the window, in the time that is left after publishing:
#   SMART once a month; btrfs scrub resumed window by window (one full pass a month);
#   a slice of the full hash scan of files that did not change (cursor kept on the SD card).

maintenance() {   # maintenance <newest id> <seconds left>
  local id=$1 left=$2 t
  [ "$left" -gt 120 ] || return 0
  local smart_at; smart_at=$(kv_get "$ST_MAINT" smart_at)
  if [ $(( $(now) - ${smart_at:-0} )) -ge $(( SMART_EVERY_DAYS * 86400 )) ]; then smart_read || true; fi
  left=$(( left - 60 ))
  if scrub_due; then
    t=$(( left / 2 )); [ "$t" -gt 60 ] && scrub_slice "$t"
    left=$(( left - t ))
  fi
  [ "$left" -gt 60 ] && scan_slice "$id" "$left"
  return 0
}

scrub_due() {
  local done_at state
  state=$(kv_get "$ST_MAINT" scrub_state)
  [ "$state" = running ] && return 0
  done_at=$(kv_get "$ST_MAINT" scrub_done)
  [ $(( $(now) - ${done_at:-0} )) -ge $(( SCRUB_EVERY_DAYS * 86400 )) ]
}

scrub_slice() {   # scrub_slice <seconds>
  local t=$1 out errs
  if [ "$(kv_get "$ST_MAINT" scrub_state)" = running ]; then
    timeout "$t" btrfs scrub resume -B "$MNT" >/dev/null 2>&1 || true
  else
    timeout "$t" btrfs scrub start -B "$MNT" >/dev/null 2>&1 || true
  fi
  btrfs scrub cancel "$MNT" >/dev/null 2>&1 || true
  out=$(btrfs scrub status "$MNT" 2>/dev/null || true)
  if grep -qiE 'Status:[[:space:]]+finished' <<< "$out"; then
    kv_set "$ST_MAINT" scrub_state "done"; kv_set "$ST_MAINT" scrub_done "$(now)"
    log "scrub finished"
  else
    kv_set "$ST_MAINT" scrub_state running
  fi
  errs=$(awk '/Error summary:/ { sub(/.*Error summary:[[:space:]]*/, ""); print }' <<< "$out")
  if [ -n "$errs" ] && ! grep -qi 'no errors found' <<< "$errs"; then
    notify scrub_errors urgent N_SCRUB_ERRORS "$(safe_text "$errs")"
  fi
}

# Files that did not change are only protected by btrfs checksums unless they are read again.
# Each window reads the next slice of the newest generation against its list.
scan_slice() {   # scan_slice <id> <seconds>
  local id=$1 t=$2 cursor gen list total out ndone bad
  list=$AUDIT/liste/$id.list
  [ -r "$list" ] && [ -d "$GEN_DIR/gen-$id" ] || return 0
  cursor=$(kv_get "$ST_MAINT" scan_cursor); [[ $cursor =~ ^[0-9]+$ ]] || cursor=0
  gen=$(kv_get "$ST_MAINT" scan_gen)
  total=$(grep -vc '^# ' "$list" || true)
  [ "$cursor" -lt "$total" ] || cursor=0
  [ "$gen" = "$id" ] || log "full scan continues on gen-$id at file $cursor of $total"
  out=$(grep -v '^# ' "$list" | tail -n +"$(( cursor + 1 ))" \
        | VERIFY_TIMEOUT=$(( t + 30 )) verify scan "$GEN_DIR/gen-$id" "$(( $(now) + t ))" || true)
  ndone=$(sed -n "s/^#done //p" <<< "$out"); [[ $ndone =~ ^[0-9]+$ ]] || ndone=0
  bad=$(grep -c '^bad ' <<< "$out" || true)
  cursor=$(( cursor + ndone ))
  if [ "$cursor" -ge "$total" ]; then kv_set "$ST_MAINT" scan_round_done "$(now)"; cursor=0; fi
  kv_set "$ST_MAINT" scan_cursor "$cursor"; kv_set "$ST_MAINT" scan_gen "$id"
  if [ "$bad" -gt 0 ]; then notify scan_mismatch urgent N_SCAN_MISMATCH "$id" "$bad"; fi
}
