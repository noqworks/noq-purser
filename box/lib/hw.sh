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

# The light stick (purser-light draws it): the core only writes the state it decided.
#   ready | unpaired | pulling [percent] | checking | done | warning | fault | suspect | off
light_set() {   # light_set <state> [arg]
  install -d -m 0755 "$RUN_DIR" 2>/dev/null || return 0
  printf '%s\n' "$*" > "$RUN_DIR/light.new" 2>/dev/null && mv -f "$RUN_DIR/light.new" "$RUN_DIR/light" 2>/dev/null || true
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

# --- the clock: network time through chrony, or the optional battery clock (DS3231) ---
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
  built=$(kv_get "$IMAGE_RELEASE" BUILD_DATE)
  if [[ $built =~ ^[0-9]+$ ]] && [ "$w" -lt "$built" ]; then rm -f "$f"; echo early; return 0; fi
  # The wall/monotonic reference is kept only while the clock has a source: the step made after
  # boot (network time, or the battery clock) is the clock being set, not a jump.
  local src=ntp e
  if ! chrony_synced; then
    if ! rtc_trusted; then rm -f "$f"; echo unsynced; return 0; fi
    src=rtc
  fi
  if read -r rw rm < "$f" 2>/dev/null && [[ ${rw:-} =~ ^[0-9]+$ ]] && [[ ${rm:-} =~ ^[0-9]+$ ]]; then
    d=$(( (w - rw) - (m - rm) )); d=${d#-}
    if [ "$d" -gt "$CLOCK_JUMP_MAX" ]; then echo "$m $d" > "$j"; fi
  fi
  echo "$w $m" > "$f"
  if read -r ref _ < "$j" 2>/dev/null && [[ ${ref:-} =~ ^[0-9]+$ ]] && [ $(( m - ref )) -lt 3600 ]; then echo jump; return 0; fi
  if [ "$src" = rtc ]; then
    # no network time: the battery clock is the reference; the system clock must stay with it
    e=$(rtc_epoch) || { echo unsynced; return 0; }
    d=$(( w - e )); d=${d#-}
    if [ "$d" -gt "$CLOCK_JUMP_MAX" ]; then echo "$d" > "$RUN_DIR/clock.diff"; echo disagree; return 0; fi
    echo ok; return 0
  fi
  worst=$(chrony_worst_offset)
  if [[ $worst =~ ^[0-9]+$ ]] && [ "$worst" -gt "$CLOCK_JUMP_MAX" ]; then echo "$worst" > "$RUN_DIR/clock.diff"; echo disagree; return 0; fi
  # network time is good: it keeps the battery clock right (and sets it the first time)
  if rtc_sys >/dev/null; then
    if rtc_trusted; then
      e=$(rtc_epoch); d=$(( w - e )); d=${d#-}
      if [ "$d" -gt "$CLOCK_JUMP_MAX" ]; then echo "$d" > "$RUN_DIR/clock.diff"; echo disagree; return 0; fi
      [ "$d" -lt 2 ] || rtc_write ntp >/dev/null 2>&1 || true
    else
      rtc_write ntp >/dev/null 2>&1 || true
    fi
  fi
  echo ok
}

# --- battery clock: DS3231 on I2C3 (header pin 1 VCC 3.3 V, 3 SDA, 5 SCL, 25 GND) ---
# Optional. It is trusted only after it was set on purpose (network time, or the phone at
# pairing / with the operation code) and while its oscillator ran without a stop (the driver
# refuses to read it after a power loss without battery). The server cannot touch it. The SoC's
# own RTC has no battery and is ignored.
RTC_I2C_NODE=5002c00.i2c
rtc_sys() {   # sysfs directory of the battery clock
  local r
  for r in "$SYS_DIR"/class/rtc/rtc*; do
    [ -r "$r/name" ] || continue
    case $(cat "$r/name" 2>/dev/null) in *ds1307*|*ds3231*) echo "$r"; return 0 ;; esac
  done
  return 1
}
rtc_probe() {   # at boot: bind the driver to address 0x68 on I2C3; leaves nothing behind without a chip
  local b n
  rtc_sys >/dev/null && return 0
  modprobe rtc-ds1307 2>/dev/null || true
  for b in "$SYS_DIR"/bus/i2c/devices/i2c-*; do
    [ -e "$b/new_device" ] || continue
    case $(readlink -f "$b") in *"$RTC_I2C_NODE"*) ;; *) continue ;; esac
    n=${b##*i2c-}
    [ -e "$b/$n-0068" ] || echo "ds3231 0x68" > "$b/new_device" 2>/dev/null || true
    sleep 1
    rtc_sys >/dev/null && return 0
    echo 0x68 > "$b/delete_device" 2>/dev/null || true
  done
  return 1
}
rtc_epoch() {
  local r e
  r=$(rtc_sys) || return 1
  e=$(cat "$r/since_epoch" 2>/dev/null) || return 1
  [[ $e =~ ^[0-9]+$ ]] && echo "$e"
}
rtc_trusted() {
  local e built
  [ -s "$STATE/rtc" ] || return 1
  e=$(rtc_epoch) || return 1
  built=$(kv_get "$IMAGE_RELEASE" BUILD_DATE)
  if [[ $built =~ ^[0-9]+$ ]] && [ "$e" -lt "$built" ]; then return 1; fi
  return 0
}
rtc_write() {   # rtc_write <source>: system clock -> battery clock, and mark it set
  local r
  r=$(rtc_sys) || return 1
  hwclock -f "$DEV_DIR/${r##*/}" --systohc --utc 2>/dev/null || return 1
  printf 'at=%s\nsource=%s\n' "$(now)" "$1" > "$STATE/rtc"
}
clock_source() {   # ntp | rtc | none
  if chrony_synced; then echo ntp; elif rtc_trusted; then echo rtc; else echo none; fi
}
# At boot, before chrony: bind the battery clock and take the time from it when it is trusted.
rtc_boot() {
  local e
  rtc_probe >/dev/null 2>&1 || return 0
  rtc_trusted || { log "battery clock present, not set yet"; return 0; }
  e=$(rtc_epoch) || return 0
  date -u -s "@$e" >/dev/null 2>&1 && log "clock taken from the battery clock"
}
# purser rtc-set <epoch> [--if-unset]: the phone's time (pairing, or the page with the code).
# Network time decides when it is there; a time before the image build is refused.
cmd_rtc_set() {
  local e=${1:-} mode=${2:-} built
  [[ $e =~ ^[0-9]{9,11}$ ]] || { say "rtc-set: epoch seconds expected" >&2; return 2; }
  rtc_sys >/dev/null || { say "rtc-set: no battery clock" >&2; return 3; }
  if chrony_synced; then say "rtc-set: network time is synchronised; it keeps the battery clock" >&2; return 4; fi
  if [ "$mode" = --if-unset ] && rtc_trusted; then return 0; fi
  built=$(kv_get "$IMAGE_RELEASE" BUILD_DATE)
  if [[ $built =~ ^[0-9]+$ ]] && [ "$e" -lt "$built" ]; then say "rtc-set: earlier than the image build" >&2; return 5; fi
  date -u -s "@$e" >/dev/null || return 1
  rtc_write phone || return 1
  rm -f "$RUN_DIR/clock.ref" "$RUN_DIR/clock.jump"
  log "battery clock set from the phone"
  notify clock_set default N_CLOCK_SET "$(date -u -d "@$e" +%Y-%m-%dT%H:%MZ)"
}
