# shellcheck shell=bash
# The nightly window. Success means: a new generation was checked, verified, published and the
# disk was locked again. Re-processing, sending a pending ack or a partial transfer is not success.
#
#   clock check -> pending ack -> ask "latest" (disk locked) -> fetch + check the list (disk locked)
#   -> find the USB disk -> LUKS open -> mount -> sync -> verify -> publish -> retention
#   -> maintenance -> unmount -> LUKS close -> ack -> alarm if needed

record_run() {   # record_run <result> [id] [bytes] [seconds] [detail]
  printf 'result=%s\nid=%s\nbytes=%s\nseconds=%s\ndetail=%s\nat=%s\n' \
    "$1" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "$(now)" > "$ST_LAST_RUN"
}

send_pending_ack() {
  local p
  p=$(cat "$ST_PENDING_ACK" 2>/dev/null || true)
  [ -n "$p" ] || return 0
  # shellcheck disable=SC2086  # "<id> <verdict>"
  if [[ $p =~ ^[0-9TZ-]+( (tamam|uyari|supheli))?$ ]] && remote ack $p >/dev/null; then rm -f "$ST_PENDING_ACK"; fi
}

# Ask for the newest published generation until the end of the polling interval.
wait_for_generation() {   # prints the new id; returns 1 when none arrived
  local last=$1 first_fill=$2 deadline id
  deadline=$(date -d "$(date -d "@$(now)" +%F) $POLL_UNTIL" +%s)
  while :; do
    id=$(remote latest 2>/dev/null | head -1 || true)
    if valid_id "$id" && [[ $id > $last ]] && [ "$(id_epoch "$id")" -le $(( $(now) + 3600 )) ]; then
      echo "$id"; return 0
    fi
    [ -n "$first_fill" ] && return 1
    [ "$(now)" -lt "$deadline" ] || return 1
    sleep "$POLL_EVERY"
  done
}

budget_left() {   # seconds left in the window, minus a reserve
  local start=$1 reserve=$2
  [ -n "${FIRST_FILL:-}" ] && { echo 172800; return; }
  echo $(( MAX_MIN * 60 - ( $(now) - start ) - reserve ))
}

night_run() {   # night_run [first-fill]
  need_config SERVER LUKS_UUID
  FIRST_FILL=${1:-}
  take_lock
  if disk_is_open; then disk_close || true; fi
  # Without a clock it can believe the box takes nothing tonight (and does not ask the server).
  local clock
  clock=$(clock_check)
  if [ "$clock" != ok ]; then
    record_run clock_untrusted "" "" "" "$clock"
    notify clock_untrusted high N_CLOCK_UNTRUSTED "$(msg "CLOCK_${clock^^}")"
    led_update; return 0
  fi
  send_pending_ack
  paused_report

  local last id w start
  last=$(cat "$ST_LAST_PUBLISHED" 2>/dev/null || true)
  if ! id=$(wait_for_generation "$last" "$FIRST_FILL"); then
    record_run no_generation
    [ -z "$FIRST_FILL" ] && notify no_generation high N_NO_GENERATION "${last:-none}"
    led_update; return 0
  fi

  # The list is fetched and checked while the disk is still locked.
  w=$RUN_DIR/work; rm -rf "$w"; install -d -m 0755 "$w"
  install -d -o "$RSYNC_USER" -g "$RSYNC_USER" -m 0755 "$INCOMING"
  find "$INCOMING" -mindepth 1 -delete
  rsync_opts
  if ! sandbox "$RSYNC_USER" "$INCOMING" 600 net -- "${RSYNC_OPTS[@]}" --max-size="$LIST_MAX_SIZE" \
       -e "$(ssh_e)" "$SERVER_USER@$SERVER:$id.list" "$INCOMING/" || [ ! -f "$INCOMING/$id.list" ]; then
    record_run list_fetch_failed "$id"; notify list_fetch high N_LIST_FETCH "$id"; led_update; return 1
  fi
  install -m 0644 "$INCOMING/$id.list" "$w/list"
  local reason
  if ! reason=$(verify list "$w/list" "$id"); then
    [[ $reason =~ ^LIST_[A-Z_]+$ ]] || reason=LIST_ERROR
    record_run list_rejected "$id" "" "" "$reason"; notify list_rejected high N_LIST_REJECTED "$id" "$reason"
    led_update; return 1
  fi

  start=$(now)
  disk_open || { record_run disk_error "$id"; led_update; return 1; }
  if [ -d "$GEN_DIR/gen-$id" ]; then
    publish_recover "$id"
    if [ -s "$AUDIT/meta/$id" ]; then log "$id is already published; finishing the remaining steps"; finish "$id" "$start"; return 0; fi
  fi
  if ! disk_make_room; then
    disk_close || true
    record_run disk_full "$id"; notify disk_full urgent N_DISK_FULL; led_update; return 1
  fi
  if ! transfer_and_verify "$id" "$last" "$w" "$start"; then return 1; fi
  finish "$id" "$start"
}

# Returns 1 after it has recorded, notified and closed the disk itself.
transfer_and_verify() {   # <id> <last published> <work dir> <start>
  local id=$1 last=$2 w=$3 start=$4 prev=/dev/null t
  [ -n "$last" ] && [ -f "$AUDIT/liste/$last.list" ] && prev=$AUDIT/liste/$last.list
  # staging: writable snapshot of the last published generation; a half-filled one is kept
  if [ ! -d "$STAGING" ]; then
    if [ -n "$last" ] && [ -d "$GEN_DIR/gen-$last" ]; then btrfs -q subvolume snapshot "$GEN_DIR/gen-$last" "$STAGING"
    else btrfs -q subvolume create "$STAGING"; fi
  fi
  find -P "$STAGING" -xdev ! -user "$RSYNC_USER" -exec chown -h "$RSYNC_USER:$RSYNC_USER" {} + 2>/dev/null || true
  # damaged copies (holes) are removed so tonight's transfer pulls them again; size and mtime alone
  # would let rsync skip them for ever. Pulled again, they are read back below like any touched file.
  holes_find "$STAGING" > "$w/holes" || true
  if [ -s "$w/holes" ]; then
    log "staging: $(count "$w/holes") damaged file(s) with holes, pulled again tonight"
    ( cd "$STAGING" && tr '\n' '\0' < "$w/holes" | xargs -0 -r rm -f -- )
  fi
  touch "$w/t0"; sleep 1
  cp "$w/t0" "$ST_MARK" 2>/dev/null || true
  # bytes used on the disk as the transfer starts (after disk_make_room): the page shows the growth since
  df -P -B1 "$MNT" 2>/dev/null | awk 'NR == 2 { print $3 }' > "$w/used0" || true

  t=$(budget_left "$start" 900)
  if [ "$t" -le 300 ]; then
    abort_window partial "$id" N_NO_TIME "$id"; return 1
  fi
  rsync_opts
  light_set pulling
  if ! sandbox "$RSYNC_USER" "$STAGING" "$t" net -- "${RSYNC_OPTS[@]}" -e "$(ssh_e)" "$SERVER_USER@$SERVER:$id/" "$STAGING/"; then
    # why it stopped: the disk dropped off USB, the first fill is unfinished, or the night's time ran out
    if disk_dropped; then abort_window disk_error "$id" N_DISK_DROPPED
    elif [ -n "$FIRST_FILL" ]; then abort_window partial "$id" N_FIRST_FILL_PARTIAL
    else abort_window partial "$id" N_PARTIAL "$MAX_MIN"; fi
    return 1
  fi

  local r
  light_set checking
  if ! r=$(verify tree "$STAGING" "$w/list"); then
    if [ "$r" = TREE_TYPE ]; then
      btrfs -q subvolume delete "$STAGING" || true
      abort_window rejected_tree "$id" N_TREE_TYPE "$id"
    else
      abort_window tree_mismatch "$id" N_TREE_MISMATCH "$id"
    fi
    return 1
  fi

  # what to read back: list difference (new or other hash) + everything the transfer touched
  list_diff "$prev" "$w/list" "$w"
  cat "$w/changed" "$w/added" | LC_ALL=C sort -u > "$w/listdiff"
  verify ctime "$STAGING" "$w/t0" > "$w/ctime"
  LC_ALL=C sort -u "$w/listdiff" "$w/ctime" > "$w/verify"
  cp "$w/verify" "$ST_VERIFY_SET"

  t=$(budget_left "$start" 300)
  [ "$t" -gt 60 ] || { abort_window partial "$id" N_NO_TIME "$id"; return 1; }
  # read back from the disk, not from memory: without this the hash reads the page cache rsync just
  # filled, and data that never reached the disk still verifies (seen on the bench box, Nov 2026)
  sync; { echo 3 > /proc/sys/vm/drop_caches; } 2>/dev/null || true
  if ! VERIFY_TIMEOUT=$t verify hash "$STAGING" < "$w/verify" > "$w/actual"; then
    abort_window verify_failed "$id" N_VERIFY_FAILED "$id"; return 1
  fi
  BYTES=$(sed -n 's/^#bytes //p' "$w/actual"); BYTES=${BYTES:-0}
  hash_compare "$w"

  # list hash changed but the file was not transferred (size and mtime kept): pull it again
  # by checksum; if the content then matches, the server changed it silently.
  local stale lied other
  stale=$(count "$w/bad.stale"); lied=$(count "$w/bad.lied")
  if [ "$stale" -gt 0 ]; then
    t=$(budget_left "$start" 300)
    sandbox "$RSYNC_USER" "$STAGING" "$t" net -- "${RSYNC_OPTS[@]}" -c --files-from="$w/bad.stale" \
      -e "$(ssh_e)" "$SERVER_USER@$SERVER:$id/" "$STAGING/" || true
    VERIFY_TIMEOUT=$t verify hash "$STAGING" < "$w/bad.stale" > "$w/actual2" || true
    awk -v st="$w/bad.stale" 'BEGIN { while ((getline l < st) > 0) want[l] = 1 }
         NR == FNR { if (!/^#/) a[substr($0, 67)] = substr($0, 1, 64); next }
         !/^# / { p = substr($0, 67); if ((p in want) && (!(p in a) || a[p] != substr($0, 1, 64))) print p }' \
      "$w/actual2" "$w/list" > "$w/bad.still"
    cat "$w/bad.still" >> "$w/bad.other"
  fi
  holes_find "$STAGING" >> "$w/bad.other" || true
  other=$(count "$w/bad.other")
  if [ "$other" -gt 0 ]; then
    abort_window verify_failed "$id" N_VERIFY_FAILED "$id"; return 1
  fi

  WARN=() SUSPECT=()
  signals "$prev" "$w/list" "$id" "$BYTES" "$w"
  [ "$lied" -gt 0 ] && SUSPECT+=("list_hash_lie/$lied")
  if [ "$stale" -gt 0 ] && [ "$(count "$w/bad.still")" -eq 0 ]; then SUSPECT+=("silent_change/$stale"); fi

  # The stored list describes what is on the disk: hashes the server lied about are replaced.
  awk -v lies="$w/bad.lied" 'BEGIN { while ((getline l < lies) > 0) lie[l] = 1 }
       NR == FNR { if (!/^#/) a[substr($0, 67)] = substr($0, 1, 64); next }
       /^# / { print; next }
       { p = substr($0, 67); if (p in lie) print a[p] "  " p; else print }' "$w/actual" "$w/list" > "$w/stored.list"
  publish "$id" "$w" "$start"
}

# actual vs. list for the read-back set: lied = list claims "unchanged" but the content was
# transferred and differs; stale = list says changed but nothing was transferred; other = rest.
hash_compare() {   # <work dir>
  local w=$1
  awk -v ld="$w/listdiff" -v ct="$w/ctime" -v lied="$w/bad.lied" -v stale="$w/bad.stale" -v other="$w/bad.other" '
    BEGIN { while ((getline l < ld) > 0) d[l] = 1; while ((getline l < ct) > 0) c[l] = 1
            printf "" > lied; printf "" > stale; printf "" > other }
    NR == FNR { if (!/^#/) a[substr($0, 67)] = substr($0, 1, 64); next }
    !/^# / { p = substr($0, 67); h = substr($0, 1, 64)
      if (!((p in d) || (p in c))) next
      if (!(p in a)) { print p > other; next }
      if (a[p] == h) next
      if ((p in c) && !(p in d)) print p > lied
      else if ((p in d) && !(p in c)) print p > stale
      else print p > other }' "$w/actual" "$w/list"
}

abort_window() {   # abort_window <result> <id> <message key> [args]
  local result=$1 id=$2 key=$3; shift 3
  disk_close || true
  record_run "$result" "$id"
  case $result in partial) notify partial default "$key" "$@" ;; *) notify "$result" high "$key" "$@" ;; esac
  led_update
}

# Publish order survives a power cut: audit files are written as .pending first, then the
# read-only snapshot, then the audit files are renamed. A generation without audit files is
# finished from the .pending files or removed.
publish() {   # <id> <work dir> <start>
  local id=$1 w=$2 start=$3 r
  {
    printf '%s=%s\n%s=%s\n%s=%s\n' "$META_BYTES" "$BYTES" "$META_FILES" "$(count "$w/verify")" "$META_SECONDS" "$(( $(now) - start ))"
    for r in "${WARN[@]}"; do printf '%s=%s\n' "$META_WARN" "$r"; done
    for r in "${SUSPECT[@]}"; do printf '%s=%s\n' "$META_SUSPECT" "$r"; done
  } > "$AUDIT/meta/.$id.pending"
  cp "$w/stored.list" "$AUDIT/liste/.$id.list.pending"
  if [ ${#SUSPECT[@]} -gt 0 ]; then printf '%s\n' "${SUSPECT[@]}" > "$AUDIT/supheli/.$id.pending"; fi
  sync
  btrfs -q subvolume snapshot -r "$STAGING" "$GEN_DIR/gen-$id"
  [ "${PURSER_FAULT:-}" = after_snapshot ] && { log "fault injection: stopping after the snapshot"; exit 99; }
  publish_recover "$id"
  btrfs -q subvolume delete "$STAGING"
}

publish_recover() {   # finish renaming the audit files of a published generation
  local id=$1
  [ -e "$AUDIT/liste/.$id.list.pending" ] && mv -f "$AUDIT/liste/.$id.list.pending" "$AUDIT/liste/$id.list"
  [ -e "$AUDIT/supheli/.$id.pending" ] && mv -f "$AUDIT/supheli/.$id.pending" "$AUDIT/supheli/$id"
  [ -e "$AUDIT/meta/.$id.pending" ] && mv -f "$AUDIT/meta/.$id.pending" "$AUDIT/meta/$id"
  if [ -d "$GEN_DIR/gen-$id" ] && [ ! -s "$AUDIT/meta/$id" ]; then
    log "gen-$id has no audit record; removing it so it is taken again"
    btrfs -q subvolume delete "$GEN_DIR/gen-$id"
  fi
  return 0
}

# After publishing: long-retention copy, retention, maintenance, disk locked, state, ack, alarm.
# Everything is read back from the meta file so an interrupted run resumes here.
finish() {   # <id> <start>
  local id=$1 start=$2 bytes warn suspect closed=1 verdict=tamam gb min left
  bytes=$(kv_get "$AUDIT/meta/$id" "$META_BYTES")
  warn=$(sed -n "s/^$META_WARN=\(..*\)/\1/p" "$AUDIT/meta/$id")
  suspect=$(sed -n "s/^$META_SUSPECT=\(..*\)/\1/p" "$AUDIT/meta/$id")
  cp "$AUDIT/liste/$id.list" "$ST_LAST_LIST"
  if long_cut_due "$id"; then long_cut "$id"; fi
  retention_apply
  left=$(budget_left "$start" $(( RESERVE_MIN * 60 )))
  # First generation: everything was just written and checked file by file against the list.
  # Reading the whole disk again (scrub, scan slice) adds hours and proves nothing new; the
  # monthly cycle starts from here.
  if [ ! -s "$ST_LAST_PUBLISHED" ]; then
    kv_set "$ST_MAINT" scrub_state "done"; kv_set "$ST_MAINT" scrub_done "$(now)"
    log "first generation: whole-disk read skipped, monthly scrub cycle starts now"
  else
    maintenance "$id" "$left"
  fi
  disk_usage_record
  generations_record
  cache_suspects
  suspect_state_sync
  disk_close || closed=0
  echo "$id" > "$ST_LAST_PUBLISHED"
  if [ -n "$(uncleared_suspects_cached)" ]; then uncleared_suspects_cached | head -1 > "$ST_SUSPECT_FLAG"
  else rm -f "$ST_SUSPECT_FLAG"; kv_set "$ST_MAINT" paused_since ""; echo "$id" > "$ST_LAST_SOUND"; fi
  [ -n "$warn" ] && verdict=uyari
  [ -n "$suspect" ] && verdict=supheli
  remote ack "$id" "$verdict" >/dev/null 2>&1 || echo "$id $verdict" > "$ST_PENDING_ACK"
  gb=$(human_gb "$bytes"); min=$(( ( $(now) - start + 59 ) / 60 ))
  local tail_key=N_TAIL_NONE
  [ $closed = 1 ] && tail_key=N_TAIL_DISK_LOCKED
  record_run "$verdict" "$id" "$bytes" "$(( $(now) - start ))" "$(printf "%s %s" "$suspect" "$warn" | tr "\n" " ")"
  if [ -n "$suspect" ]; then
    notify suspect urgent N_SUSPECT "$id" "$(reasons_text "$suspect")" "$(msg "$tail_key")"
  elif [ -n "$warn" ]; then
    notify warning default N_WARNING "$gb" "$min" "$(reasons_text "$warn")" "$(msg "$tail_key")"
  else
    log "$(msg N_DONE "$gb" "$min" "$(msg "$tail_key")")"
  fi
  led_update
}

# finish() runs after disk_close; the suspect list is cached while the disk is still open.
uncleared_suspects_cached() { cat "$RUN_DIR/uncleared" 2>/dev/null || true; }
cache_suspects() { install -d -m 0755 "$RUN_DIR"; uncleared_suspects > "$RUN_DIR/uncleared"; }

# Every night while deletion is paused: how long it has been.
paused_report() {
  local first since days
  first=$(cat "$ST_SUSPECT_FLAG" 2>/dev/null || true)
  [ -n "$first" ] || return 0
  since=$(kv_get "$ST_MAINT" paused_since)
  [ -n "$since" ] || { since=$(now); kv_set "$ST_MAINT" paused_since "$since"; }
  days=$(( ( $(now) - since ) / 86400 ))
  if [ "$days" -ge 1 ]; then notify deletion_paused high N_DELETION_PAUSED "$days"; fi
  return 0
}

reasons_text() {   # reasons_text "<code>\n<code>..." -> "text; text"
  local r out=() code rest a b
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    code=${r%%/*}; rest=${r#"$code"}; rest=${rest#/}
    IFS=/ read -r a b <<< "$rest"
    local args=(); [ -n "${a:-}" ] && args+=("$a"); [ -n "${b:-}" ] && args+=("$b")
    if [[ $code =~ ^[a-z_]+$ ]] && [ -n "${MSG[R_${code^^}]:-}" ]; then out+=("$(msg "R_${code^^}" "${args[@]}")")
    else out+=("$(printf '%s' "$r" | tr -d '\000-\037\177|')"); fi   # reason text written by an older core
  done <<< "$1"
  local IFS=';'; printf '%s' "${out[*]}" | sed 's/;/; /g'
}
