# shellcheck shell=bash
# Disk power, LUKS and btrfs. The disk is energized only while this code needs it.

disk_dev() { readlink -f "$BY_UUID_DIR/$LUKS_UUID" 2>/dev/null; }
disk_present() { [ -n "$LUKS_UUID" ] && [ -e "$BY_UUID_DIR/$LUKS_UUID" ]; }
disk_is_open() { mountpoint -q "$MNT" 2>/dev/null || [ -e "$MAPPER_DIR/$MAP" ]; }

disk_open() {
  need_config LUKS_UUID
  local dev i
  relay_set 1
  for (( i = 0; i < DISK_WAIT; i++ )); do disk_present && break; sleep 1; done
  if ! disk_present; then
    relay_set 0
    notify disk_not_seen high N_DISK_NOT_SEEN
    return 1
  fi
  [ "$(sense_get)" = 1 ] || log "disk is visible but the voltage sense reads 0 (check the sense divider)"
  dev=$(disk_dev)
  [ -e "$MAPPER_DIR/$MAP" ] || cryptsetup open --key-file "$LUKS_KEY" "$dev" "$MAP"
  install -d -m 0755 "$MNT"
  mountpoint -q "$MNT" || mount -o noatime "$MAPPER_DIR/$MAP" "$MNT"
  install -d -m 0755 "$GEN_DIR" "$AUDIT"
  install -d -m 0700 "$AUDIT/liste" "$AUDIT/meta" "$AUDIT/supheli" "$AUDIT/temiz" "$AUDIT/pin"
  disk_usage_record
}

# sync -> unmount -> close LUKS -> flush + stop + detach the USB device -> 5 s -> relay off.
# Returns 0 only when the voltage sense actually reads 0 afterwards.
disk_close() {
  local dev base
  dev=$(disk_dev || true)
  sync
  if mountpoint -q "$MNT" 2>/dev/null; then umount "$MNT"; fi
  if [ -e "$MAPPER_DIR/$MAP" ]; then cryptsetup close "$MAP"; fi
  if [ -n "$dev" ] && [ -b "$dev" ]; then
    base=$(basename "$dev")
    blockdev --flushbufs "$dev" 2>/dev/null || true
    sg_start --stop "$dev" 2>/dev/null || true
    [ -w "/sys/block/$base/device/delete" ] && echo 1 > "/sys/block/$base/device/delete" 2>/dev/null || true
  fi
  sleep "${DISK_SPINDOWN_WAIT:-5}"
  relay_set 0
  if ! wait_sense 0 5; then
    notify power_not_off urgent N_POWER_NOT_OFF
    return 1
  fi
  return 0
}

disk_free_pct() { df -P "$MNT" | awk 'NR == 2 { gsub("%", "", $5); print 100 - $5 }'; }

disk_usage_record() {
  local used total
  read -r total used < <(df -P -B1 "$MNT" | awk 'NR == 2 { print $2, $3 }')
  printf 'used=%s\ntotal=%s\nat=%s\n' "$used" "$total" "$(now)" > "$ST_DISK_USAGE"
}

# Monthly SMART reading through the USB-SATA bridge.
smart_read() {
  local dev out health hours realloc pending life temp
  dev=$(disk_dev) || return 0
  command -v smartctl >/dev/null 2>&1 || { log "smartctl not installed"; return 0; }
  out=$(smartctl -d sat -H -A "$dev" 2>/dev/null || true)
  health=$(awk -F': *' '/overall-health self-assessment test result/ { print $2 }' <<< "$out" | tr -cd '[:upper:]')
  hours=$(awk '$2 == "Power_On_Hours" { print $10 }' <<< "$out")
  realloc=$(awk '$2 == "Reallocated_Sector_Ct" { print $10 }' <<< "$out")
  pending=$(awk '$2 == "Current_Pending_Sector" { print $10 }' <<< "$out")
  life=$(awk '$2 ~ /Percent_Lifetime_Remain|Wear_Leveling_Count|SSD_Life_Left/ { print $4 + 0; exit }' <<< "$out")
  temp=$(awk '$2 ~ /^Temperature_Celsius|^Airflow_Temperature_Cel/ { print $10; exit }' <<< "$out")
  printf 'health=%s\nhours=%s\nrealloc=%s\npending=%s\nlife=%s\ntemp=%s\nat=%s\n' \
    "${health:-UNKNOWN}" "${hours:-}" "${realloc:-}" "${pending:-}" "${life:-}" "${temp:-}" "$(now)" > "$ST_SMART"
  kv_set "$ST_MAINT" smart_at "$(now)"
  if [ -n "$health" ] && [ "$health" != PASSED ]; then
    notify smart_failed urgent N_SMART_FAILED "$health"
  elif [[ ${realloc:-0} =~ ^[0-9]+$ ]] && [[ ${pending:-0} =~ ^[0-9]+$ ]] && [ $(( ${realloc:-0} + ${pending:-0} )) -gt 0 ]; then
    notify smart_sectors high N_SMART_SECTORS "${realloc:-0}" "${pending:-0}"
  fi
}
