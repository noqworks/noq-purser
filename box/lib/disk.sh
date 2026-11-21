# shellcheck shell=bash
# The disk: always attached, LUKS2 + btrfs. Outside the window it is locked and not mounted.
#   open:  find the USB device -> (hung bridge: one USB reset) -> LUKS open -> mount
#   close: sync -> unmount -> LUKS close -> check: no mapper, no mount

disk_dev() { readlink -f "$BY_UUID_DIR/$LUKS_UUID" 2>/dev/null; }
disk_present() { [ -n "$LUKS_UUID" ] && [ -e "$BY_UUID_DIR/$LUKS_UUID" ]; }
disk_is_open() { mountpoint -q "$MNT" 2>/dev/null || [ -e "$MAPPER_DIR/$MAP" ]; }
disk_is_closed() { ! disk_is_open; }

# The device answers a small direct read within 20 s (a hung bridge does not).
disk_readable() {
  local dev; dev=$(disk_dev) || return 1
  [ -b "$dev" ] || return 1
  timeout 20 dd if="$dev" of=/dev/null bs=4096 count=1 iflag=direct status=none 2>/dev/null \
    || timeout 20 dd if="$dev" of=/dev/null bs=4096 count=1 status=none 2>/dev/null
}

disk_wait() {   # disk_wait <seconds>: until the LUKS device is present and readable
  local i
  for (( i = 0; i < $1; i++ )); do disk_present && disk_readable && return 0; sleep 1; done
  disk_present && disk_readable
}

# One software reset of the USB device(s) behind the disk, then wait again.
disk_reset_bridge() {
  local p ports=() did=0
  p=$(cat "$ST_USB_PORT" 2>/dev/null || true)
  [[ $p =~ ^[0-9]+-[0-9.]+$ ]] && ports+=("$p")
  [ ${#ports[@]} -gt 0 ] || mapfile -t ports < <(usb_storage_ports)
  for p in "${ports[@]}"; do usb_reset "$p" && did=1; done
  kv_set "$ST_MAINT" usb_reset_at "$(now)"
  [ $did = 1 ] || { log "no USB device could be reset"; return 1; }
  settle
  disk_wait "$DISK_WAIT"
}

disk_find() {   # 0 when the disk is present and readable; resets a hung bridge once
  disk_wait "$DISK_WAIT" && return 0
  log "disk $LUKS_UUID not present or not readable; resetting the USB bridge once"
  if disk_reset_bridge; then
    log "disk is back after the USB reset"
    kv_set "$ST_MAINT" usb_reset_ok "$(now)"
    return 0
  fi
  notify disk_not_seen urgent N_DISK_NOT_SEEN
  return 1
}

disk_open() {
  need_config LUKS_UUID
  local dev port
  disk_find || return 1
  dev=$(disk_dev)
  port=$(usb_port_of "$dev" 2>/dev/null || true)
  [ -n "$port" ] && [ "$port" != "$(cat "$ST_USB_PORT" 2>/dev/null)" ] && echo "$port" > "$ST_USB_PORT"
  [ -e "$MAPPER_DIR/$MAP" ] || cryptsetup open --key-file "$LUKS_KEY" "$dev" "$MAP"
  install -d -m 0755 "$MNT"
  mountpoint -q "$MNT" || mount -o noatime "$MAPPER_DIR/$MAP" "$MNT"
  install -d -m 0755 "$GEN_DIR" "$AUDIT"
  install -d -m 0700 "$AUDIT/liste" "$AUDIT/meta" "$AUDIT/supheli" "$AUDIT/temiz" "$AUDIT/pin"
  disk_usage_record
}

# Returns 0 only when the disk is really closed afterwards (no mapper device, no mount).
disk_close() {
  sync
  if mountpoint -q "$MNT" 2>/dev/null; then umount "$MNT" || umount -l "$MNT" || true; fi
  if [ -e "$MAPPER_DIR/$MAP" ]; then cryptsetup close "$MAP" || { sleep 3; cryptsetup close "$MAP"; } || true; fi
  if ! disk_is_closed; then
    notify disk_not_closed urgent N_DISK_NOT_CLOSED
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

# Monthly SMART reading through the USB-SATA bridge (SAT pass-through).
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
