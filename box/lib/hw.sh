# shellcheck shell=bash
# Hardware. The box is a board, a USB-SATA cable in its USB-A port and a disk. Nothing else.
#   - the disk stays attached; "off" means locked (LUKS closed) and not mounted
#   - a hung USB-SATA bridge is reset in software (authorized 0/1, else unbind/bind), once
#   - the only indicator is the board's own LED under /sys/class/leds, if it has one
# Every /sys path goes through SYS_DIR so the test suite can point it at a fake tree.

# --- USB disks ---

# One line per USB block device: "<dev> <size bytes> <model>"; found through sysfs, not lsblk.
usb_disks() {
  local b name path size model
  for b in "$SYS_DIR"/block/*; do
    [ -e "$b" ] || continue
    name=${b##*/}
    path=$(readlink -f "$b" 2>/dev/null) || continue
    [[ $path == */usb[0-9]*/* ]] || continue
    size=$(( $(cat "$b/size" 2>/dev/null || echo 0) * 512 ))
    model=$(tr -cd 'A-Za-z0-9 ._-' < "$b/device/model" 2>/dev/null | sed 's/  */ /g; s/ $//')
    printf '%s %s %s\n' "$DEV_DIR/$name" "$size" "${model:-?}"
  done
}

# The USB device (port name such as 1-1) a block device hangs off.
usb_port_of() {   # usb_port_of /dev/sdX
  local p
  p=$(readlink -f "$SYS_DIR/class/block/$(basename "$1")" 2>/dev/null) || return 1
  while [ -n "$p" ] && [ "$p" != / ] && [ "$p" != "$SYS_DIR" ]; do
    [ -r "$p/idVendor" ] && [ -r "$p/speed" ] && { basename "$p"; return 0; }
    p=$(dirname "$p")
  done
  return 1
}

# USB link speed (Mbit/s) of the block device: 480 = High Speed (USB 2.0), 5000 = USB 3.
usb_speed() {   # usb_speed /dev/sdX
  local port
  port=$(usb_port_of "$1") || return 1
  cat "$SYS_DIR/bus/usb/devices/$port/speed"
}

# Every USB port that carries a mass-storage interface (class 08), present or not.
usb_storage_ports() {
  local i
  for i in "$SYS_DIR"/bus/usb/devices/*:*; do
    [ -r "$i/bInterfaceClass" ] || continue
    [ "$(cat "$i/bInterfaceClass")" = 08 ] || continue
    i=${i##*/}; echo "${i%%:*}"
  done | sort -u
}

# Software reset of a hung bridge: de-authorize and re-authorize the USB device; when that is
# not possible, unbind and bind it at the USB core. The disk keeps its power throughout.
usb_reset() {   # usb_reset <port>
  local port=$1 d=$SYS_DIR/bus/usb/devices/$1
  [[ $port =~ ^[0-9]+-[0-9.]+$ ]] || return 1
  if [ -w "$d/authorized" ]; then
    echo 0 > "$d/authorized" && sleep 2 && echo 1 > "$d/authorized" && { log "USB $port re-authorized"; return 0; }
  fi
  if [ -w "$SYS_DIR/bus/usb/drivers/usb/unbind" ]; then
    echo "$port" > "$SYS_DIR/bus/usb/drivers/usb/unbind" 2>/dev/null || true
    sleep 2
    echo "$port" > "$SYS_DIR/bus/usb/drivers/usb/bind" && { log "USB $port unbound and bound"; return 0; }
  fi
  return 1
}

settle() { udevadm settle --timeout=30 >/dev/null 2>&1 || sleep 3; }

# --- the board LED ---

board_led() {   # prints the LED directory, or nothing
  local l
  case $BOARD_LED in
    none) return 0 ;;
    auto) ;;
    *) [ -d "$SYS_DIR/class/leds/$BOARD_LED" ] && echo "$SYS_DIR/class/leds/$BOARD_LED"; return 0 ;;
  esac
  for l in "$SYS_DIR"/class/leds/*status* "$SYS_DIR"/class/leds/*green* "$SYS_DIR"/class/leds/*; do
    [ -d "$l" ] || continue
    case ${l##*/} in *mmc*|*::*|*phy*|*eth*|*lan*|*bt*|*usb*) continue ;; esac
    echo "$l"; return 0
  done
}

# led_show ok | warn | alarm | setup | off
#   ok: steady on   warn: slow blink   alarm: fast blink   setup: heartbeat   off: dark
# No LED or no timer trigger: the pattern degrades to on/off, or to nothing. Never an error.
led_show() {
  local d max on=1000 off=1000
  d=$(board_led)
  [ -n "$d" ] || return 0
  max=$(cat "$d/max_brightness" 2>/dev/null || echo 1)
  case $1 in
    ok)    { echo none > "$d/trigger" && echo "$max" > "$d/brightness"; } 2>/dev/null ;;
    off)   { echo none > "$d/trigger" && echo 0 > "$d/brightness"; } 2>/dev/null ;;
    setup) { echo heartbeat > "$d/trigger"; } 2>/dev/null || { echo none > "$d/trigger"; echo "$max" > "$d/brightness"; } 2>/dev/null ;;
    warn|alarm)
      [ "$1" = alarm ] && on=150 off=150
      if { echo timer > "$d/trigger"; } 2>/dev/null && [ -w "$d/delay_on" ]; then
        { echo "$on" > "$d/delay_on"; echo "$off" > "$d/delay_off"; } 2>/dev/null
      else { echo none > "$d/trigger"; echo "$max" > "$d/brightness"; } 2>/dev/null; fi ;;
  esac
  return 0
}

# --- the clock: network time through chrony (the board has no battery clock) ---
#
# The clock is trusted when chrony is synchronised, network time agrees with it (chrony refuses
# steps larger than CLOCK_JUMP_MAX after start) and it has not jumped against the monotonic
# clock since the last look. Retention counts generations, so a wrong clock cannot make the box
# delete history faster; an untrusted clock only stops tonight's generation and is reported.

mono() { if [ -n "${PURSER_FAKE_MONO:-}" ]; then echo "$PURSER_FAKE_MONO"; else cut -d. -f1 /proc/uptime; fi; }

chrony_synced() {
  local t ref leap
  t=$(chronyc -c tracking 2>/dev/null) || return 1
  ref=${t%%,*}; leap=${t##*,}
  [ -n "$ref" ] && [ "$ref" != 00000000 ] && [ "$ref" != 7F7F0101 ] && [ "$leap" != "Not synchronised" ]
}

# Largest offset (s) between the box clock and any network source chrony sees.
chrony_worst_offset() {
  chronyc -c sourcestats 2>/dev/null | awk -F, '{ o = $7 + 0; if (o < 0) o = -o; if (o > m) m = o } END { printf "%d", m }'
}

# clock_state -> ok | unsynced | jump | disagree | early   (also records a detected jump)
clock_state() {
  local ref rw rm w m d f=$RUN_DIR/clock.ref j=$RUN_DIR/clock.jump worst built
  install -d -m 0755 "$RUN_DIR"
  w=$(now); m=$(mono)
  if read -r rw rm < "$f" 2>/dev/null && [[ ${rw:-} =~ ^[0-9]+$ ]] && [[ ${rm:-} =~ ^[0-9]+$ ]]; then
    d=$(( (w - rw) - (m - rm) )); d=${d#-}
    if [ "$d" -gt "$CLOCK_JUMP_MAX" ]; then echo "$m $d" > "$j"; fi
  fi
  echo "$w $m" > "$f"
  built=$(kv_get "$IMAGE_RELEASE" BUILD_DATE)
  if [[ $built =~ ^[0-9]+$ ]] && [ "$w" -lt "$built" ]; then echo early; return 0; fi
  if read -r ref _ < "$j" 2>/dev/null && [[ ${ref:-} =~ ^[0-9]+$ ]] && [ $(( m - ref )) -lt 3600 ]; then echo jump; return 0; fi
  chrony_synced || { echo unsynced; return 0; }
  worst=$(chrony_worst_offset)
  if [[ $worst =~ ^[0-9]+$ ]] && [ "$worst" -gt "$CLOCK_JUMP_MAX" ]; then echo disagree; return 0; fi
  echo ok
}
