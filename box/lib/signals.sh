# shellcheck shell=bash
# The box's own signals. They do not trust the server: they are derived from the previous
# verified list, the new list and what the transfer actually touched.
#
# Reason codes are "code" or "code/arg/arg"; they are written to the audit area and turned
# into text only when shown (catalog keys R_<CODE>). Two levels:
#   warning: notification, LED leaves green, deletion continues
#   suspect: generation kept and flagged, automatic deletion stops

WARN=() SUSPECT=()

# Split two validated lists into path sets: changed (both, other hash), added, deleted.
list_diff() {   # list_diff <prev list|/dev/null> <new list> <work dir>
  local prev=$1 new=$2 w=$3
  awk '!/^# / { print substr($0, 67) "\t" substr($0, 1, 64) }' "$prev" | LC_ALL=C sort > "$w/prev.ph"
  awk '!/^# / { print substr($0, 67) "\t" substr($0, 1, 64) }' "$new" | LC_ALL=C sort > "$w/new.ph"
  awk -F'\t' -v c="$w/changed" -v a="$w/added" -v d="$w/deleted" '
    NR == FNR { h[$1] = $2; next }
    { if ($1 in h) { if (h[$1] != $2) print $1 > c; delete h[$1] } else print $1 > a }
    END { for (p in h) print p > d }' "$w/prev.ph" "$w/new.ph"
  touch "$w/changed" "$w/added" "$w/deleted"
  local f; for f in changed added deleted; do LC_ALL=C sort -o "$w/$f" "$w/$f"; done
}

under() { awk -v d="$1/" 'index($0, d) == 1' "$2"; }        # paths below a source dir
count() { awk 'END { print NR }' "$1"; }
has() { grep -Eq -- "$1" "$2"; }                            # grep: mawk lacks {n} intervals

signals() {   # signals <prev list|/dev/null> <new list> <id> <bytes> <work dir>
  local prev=$1 new=$2 id=$3 bytes=$4 w=$5 dow kd type dir days q
  dow=$(id_dow "$id")
  hdr() { sed -n "s/^# $1=//p" "$new" | head -1; }
  [ "$(hdr clean)" = no ] && SUSPECT+=(server_clean_no)
  [ "$(hdr fresh)" = no ] && WARN+=(server_fresh_no)
  [ "$prev" = /dev/null ] && return 0
  list_diff "$prev" "$new" "$w"

  mass_check "$w" ALL "$(count "$w/prev.ph")" "$w/deleted" "$w/changed"
  for kd in $KINDS; do
    type=$(kind_type "$kd"); dir=$(kind_dir "$kd"); days=$(kind_prune "$kd")
    q=$(printf '%s' "$dir" | sed 's/[.]/\\./g')
    under "$dir" "$w/changed" > "$w/k.changed"; under "$dir" "$w/deleted" > "$w/k.deleted"
    under "$dir" "$w/added" > "$w/k.added"
    case $type in
      pgbackrest) signals_pgbackrest "$q" "$dir" "$days" "$dow" "$w" "$new" "$id" ;;
      borg)
        has "^$q/data/" "$w/k.changed" && SUSPECT+=("borg_segment_changed/$dir")
        if has "^$q/data/" "$w/k.deleted" && ! prune_allowed "$days" "$dow"; then SUSPECT+=("borg_delete_offday/$dir"); fi ;;
      restic)
        has "^$q/(data|index|snapshots|keys)/" "$w/k.changed" && SUSPECT+=("restic_object_changed/$dir")
        if has "^$q/(data|index|snapshots|keys)/" "$w/k.deleted" && ! prune_allowed "$days" "$dow"; then SUSPECT+=("restic_delete_offday/$dir"); fi
        # restic names every object after the SHA-256 of its content
        if awk '!/^# / { print substr($0, 67) " " substr($0, 1, 64) }' "$new" \
             | grep -E "^$q/(data/[0-9a-f]{2}|index|snapshots|keys)/[0-9a-f]{64} " \
             | awk '{ n = split($1, c, "/"); if (c[n] != $2) bad = 1 } END { exit !bad }'; then
          SUSPECT+=("restic_name_mismatch/$dir")
        fi ;;
    esac
    mass_check "$w" "$dir" "$(under "$dir" "$w/prev.ph" | awk 'END { print NR }')" "$w/k.deleted" "$w/k.changed"
    # stale source: nothing under it changed, appeared or disappeared
    local f=$ST_STALE_PREFIX$dir n=0
    if [ -s "$w/k.changed" ] || [ -s "$w/k.deleted" ] || [ -s "$w/k.added" ]; then echo 0 > "$f"
    else
      n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$f"
      [ "$n" -ge "$STALE_NIGHTS" ] && WARN+=("stale_source/$dir/$n")
    fi
  done

  # large transfer: compared with the median of the same weekday over the last 4 weeks
  local median
  echo "$id $dow $bytes" >> "$ST_TRANSFER_HISTORY"
  median=$(awk -v d="$dow" -v id="$id" '$2 == d && $1 != id { print $3 }' "$ST_TRANSFER_HISTORY" | tail -4 | sort -n \
           | awk '{ a[NR] = $1 } END { if (NR >= 2) print a[int((NR + 1) / 2)] }')
  if [ -n "$median" ] && [ "$median" -gt 0 ] && [ "$bytes" -gt $(( median * WARN_FACTOR )) ]; then
    WARN+=("big_transfer/$(( bytes / median ))")
  fi
}

mass_check() {   # mass_check <work> <scope> <files before> <deleted file> <changed file>
  local before=$3 del ch
  [ "$before" -gt 0 ] || return 0
  del=$(count "$4"); ch=$(count "$5")
  if [ "$MASS_DELETE_PCT" -gt 0 ] && [ "$del" -ge "$MASS_MIN_FILES" ] && [ $(( del * 100 / before )) -ge "$MASS_DELETE_PCT" ]; then
    SUSPECT+=("mass_delete/$2/$(( del * 100 / before ))")
  fi
  if [ "$MASS_CHANGE_PCT" -gt 0 ] && [ "$ch" -ge "$MASS_MIN_FILES" ] && [ $(( ch * 100 / before )) -ge "$MASS_CHANGE_PCT" ]; then
    SUSPECT+=("mass_change/$2/$(( ch * 100 / before ))")
  fi
}

# pgBackRest: backup label directories and WAL segments are written once and never change.
# Normal cleanup removes a whole label directory, or the oldest segments of the archive.
signals_pgbackrest() {   # <dir regex> <dir> <prune days> <weekday> <work> <new list> <id>
  local q=$1 dir=$2 days=$3 dow=$4 w=$5 new=$6 id=$7 label smallest largest newest age
  local immutable="^$q/(backup/[^/]+/[^/]+/|archive/[^/]+/[^/]+/[0-9A-F]{16}/)"
  has "$immutable" "$w/k.changed" && SUSPECT+=("pgb_immutable_changed/$dir")
  if has "$immutable" "$w/k.deleted"; then
    if ! prune_allowed "$days" "$dow"; then SUSPECT+=("pgb_delete_offday/$dir")
    else
      awk '!/^# / { print substr($0, 67) }' "$new" > "$w/k.newpaths"
      # shellcheck disable=SC2013  # label paths contain no spaces (list alphabet)
      for label in $(grep -Eo "^$q/backup/[^/]+/[^/]+/" "$w/k.deleted" | sort -u); do
        if awk -v d="$label" 'index($0, d) == 1 { f = 1 } END { exit !f }' "$w/k.newpaths"; then
          SUSPECT+=("pgb_delete_in_label/$dir"); break
        fi
      done
      smallest=$(grep -E "^$q/archive/[^/]+/[^/]+/[0-9A-F]{16}/[0-9A-F]{24}" "$w/k.newpaths" | awk -F/ '{ print $NF }' | sort | head -1 || true)
      largest=$(grep -E "^$q/archive/[^/]+/[^/]+/[0-9A-F]{16}/[0-9A-F]{24}" "$w/k.deleted" | awk -F/ '{ print $NF }' | sort | tail -1 || true)
      if [ -n "$smallest" ] && [ -n "$largest" ] && [[ $largest > $smallest ]]; then SUSPECT+=("pgb_delete_mid_archive/$dir"); fi
    fi
  fi
  # newest backup label older than LABEL_MAX_DAYS (label = start time of the backup)
  newest=$(awk '!/^# / { print substr($0, 67) }' "$new" \
    | grep -Eo "^$q/backup/[^/]+/[0-9]{8}-[0-9]{6}F(_[0-9]{8}-[0-9]{6}[DI])?/" \
    | grep -Eo '[0-9]{8}-[0-9]{6}[FDI]/$' | sort | tail -1 || true)
  if [ -n "$newest" ]; then
    age=$(( ( $(id_epoch "$id") - $(date -u -d "${newest:0:8} ${newest:9:2}:${newest:11:2}" +%s) ) / 86400 ))
    [ "$age" -gt "$LABEL_MAX_DAYS" ] && WARN+=("label_old/$dir/$age")
  fi
  return 0
}
