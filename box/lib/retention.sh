# shellcheck shell=bash
# Retention: 14 daily, 8 weekly, 12 monthly generations (defaults). History is deleted only by
# the box, on its own calendar; nothing the server says grants deletion.

generations() { find "$GEN_DIR" -mindepth 1 -maxdepth 1 -name "$1" -printf '%f\n' 2>/dev/null | LC_ALL=C sort; }

# Deletion is paused while any suspect generation has not been cleared at the console.
uncleared_suspects() {
  local s
  for s in "$AUDIT"/supheli/*; do
    [ -e "$s" ] || continue
    [ -e "$AUDIT/temiz/$(basename "$s")" ] || basename "$s"
  done
}
deletion_paused() { [ -n "$(uncleared_suspects | head -1)" ]; }

# Weekly/monthly copies are cut from the first generation on or after the long-retention day
# of each week (the day the weekly full backup exists).
long_cut_due() {   # long_cut_due <id>
  local id=$1 d back ref
  d=$(id_dow "$id")
  back=$(( (d - LONG_DOW + 7) % 7 ))
  ref=$(date -u -d "${id:0:10} -$back days" +%F)
  [ -e "$GEN_DIR/uzun-$id" ] && return 1
  ! generations 'uzun-*' | awk -v r="uzun-$ref" '$0 >= r { f = 1 } END { exit !f }'
}

# The privileged part only snapshots and flips the read-only flag; pruning inside the copy is
# done by the unprivileged sandbox, which never sees anything but that copy.
long_cut() {   # long_cut <id>
  local id=$1 kd
  [ -e "$LONG_TMP" ] && btrfs -q subvolume delete "$LONG_TMP"
  btrfs -q subvolume snapshot "$GEN_DIR/gen-$id" "$LONG_TMP"
  for kd in $KINDS; do
    [ "$(kind_type "$kd")" = pgbackrest ] || continue
    [ -d "$LONG_TMP/$(kind_dir "$kd")" ] || continue
    sandbox "$RSYNC_USER" "$LONG_TMP" 3600 nonet -- "$VERIFY_BIN" prune-pgbackrest "$LONG_TMP/$(kind_dir "$kd")"
  done
  btrfs -q property set -ts "$LONG_TMP" ro true
  mv "$LONG_TMP" "$GEN_DIR/uzun-$id"
  log "long-retention copy uzun-$id cut"
}

pinned() { find "$AUDIT/pin" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | grep -E "$ID_RE" || true; }

retention_keep() {
  { generations 'gen-*' | tail -n "$KEEP_DAILY"
    generations 'uzun-*' | tail -n "$KEEP_WEEKLY"
    generations 'uzun-*' | awk '{ m = substr($0, 6, 7); if (!(m in s)) { s[m] = 1; print } }' | tail -n "$KEEP_MONTHLY"
    pinned | sed 's/^/gen-/'; pinned | sed 's/^/uzun-/'
    generations 'gen-*' | tail -1; } | LC_ALL=C sort -u
}

retention_apply() {
  if deletion_paused; then log "suspect generation present; deletion paused"; return 0; fi
  local keep g
  keep=$(retention_keep)
  for g in $(generations 'gen-*'; generations 'uzun-*'); do
    grep -qx "$g" <<< "$keep" && continue
    btrfs -q subvolume delete "$GEN_DIR/$g" && log "retention: $g deleted"
  done
}

# Disk full: with no suspect, only the oldest daily generations go (never weekly, monthly,
# pinned or the newest). With a suspect present nothing is deleted.
disk_make_room() {   # returns 0 when there is room for a new generation
  local g keep
  [ "$(disk_free_pct)" -ge "$DISK_MIN_FREE_PCT" ] && return 0
  deletion_paused && return 1
  keep=$( { pinned | sed 's/^/gen-/'; generations 'gen-*' | tail -1; } | LC_ALL=C sort -u)
  for g in $(generations 'gen-*'); do
    [ "$(disk_free_pct)" -ge "$DISK_MIN_FREE_PCT" ] && return 0
    grep -qx "$g" <<< "$keep" && continue
    btrfs -q subvolume delete "$GEN_DIR/$g"
    btrfs -q subvolume sync "$GEN_DIR" 2>/dev/null || true
    log "disk full: oldest daily generation $g deleted"
  done
  [ "$(disk_free_pct)" -ge "$DISK_MIN_FREE_PCT" ]
}
