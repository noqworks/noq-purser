# shellcheck shell=bash
# Hardware: relay, voltage sense, LEDs, RTC, USB link.
#
# Output lines (relay, LEDs) are owned by the purser-gpio service; the core sends it commands
# through a FIFO and writes the wanted LED pattern to $RUN_DIR/led. GPIO_MODE=sim keeps all
# state in files under $SIM_DIR (tests, no hardware).

gpio_mode() {
  case $GPIO_MODE in
    sim|sysfs|gpiod) echo "$GPIO_MODE" ;;
    *) if [ -n "$GPIO_BASE" ] && [ -d /sys/class/gpio ]; then echo sysfs; else echo gpiod; fi ;;
  esac
}

gpio_cmd() {   # send one command line to purser-gpio
  timeout 3 sh -c 'printf "%s\n" "$1" > "$2"' _ "$1" "$GPIO_FIFO" || log "GPIO command not delivered (is purser-gpio running?)"
}

relay_set() {   # relay_set 1 = disk energized, 0 = off (RELAY_ACTIVE_LOW handled by purser-gpio)
  if [ "$(gpio_mode)" = sim ]; then
    echo "$1" > "$SIM_DIR/relay"
    [ -x "$SIM_DIR/on-relay" ] && "$SIM_DIR/on-relay" "$1"
    return 0
  fi
  gpio_cmd "relay $1"
}

sense_get() {   # 1 = disk 5 V present
  local n v
  case $(gpio_mode) in
    sim)
      if [ -e "$SIM_DIR/sense-stuck" ]; then echo 1
      elif [ -e "$SIM_DIR/sense-dead" ]; then echo 0
      else cat "$SIM_DIR/relay" 2>/dev/null || echo 0; fi ;;
    sysfs)
      n=$(( GPIO_BASE + SENSE_LINE ))
      if [ ! -d "/sys/class/gpio/gpio$n" ]; then
        echo "$n" > /sys/class/gpio/export 2>/dev/null || true; sleep 0.2
        echo in > "/sys/class/gpio/gpio$n/direction" 2>/dev/null || true
      fi
      cat "/sys/class/gpio/gpio$n/value" ;;
    *)
      v=$(gpioget --numeric -c "$GPIO_CHIP" "$SENSE_LINE" 2>/dev/null) || v=x
      echo "$v" ;;
  esac
}

wait_sense() {   # wait_sense <0|1> <seconds>
  local i
  for (( i = 0; i < $2 * 5; i++ )); do
    [ "$(sense_get)" = "$1" ] && return 0
    sleep 0.2
  done
  return 1
}

led_set() {   # led_set green|red|red-blink|both|off
  if [ "$(gpio_mode)" = sim ]; then echo "$1" > "$SIM_DIR/led"; return 0; fi
  install -d -m 0755 "$RUN_DIR"
  write_atomic "$RUN_DIR/led" "$1"
}

# DS3231 on any I2C bus at 0x68. Sets the system clock from it at boot.
rtc_device() {
  local b n r
  if [ "$(gpio_mode)" = sim ]; then [ -e "$SIM_DIR/rtc" ] && { echo "$SIM_DIR/rtc"; return 0; }; return 1; fi
  for b in /sys/bus/i2c/devices/i2c-*; do
    [ -e "$b" ] || continue
    n=${b##*-}
    i2cget -y "$n" 0x68 0x00 >/dev/null 2>&1 || continue
    [ -e "/sys/bus/i2c/devices/$n-0068" ] || { echo ds3231 0x68 > "$b/new_device" 2>/dev/null || true; sleep 1; }
    r=$(basename "$(readlink -f /sys/bus/i2c/devices/"$n"-0068/rtc/rtc* 2>/dev/null)" 2>/dev/null || true)
    [ -n "$r" ] && [ -e "/dev/$r" ] && { echo "/dev/$r"; return 0; }
  done
  return 1
}

# USB link speed (Mbit/s) of the block device: 480 = High Speed.
usb_speed() {   # usb_speed /dev/sdX
  local p
  if [ "$(gpio_mode)" = sim ]; then cat "$SIM_DIR/usb-speed" 2>/dev/null || echo 480; return 0; fi
  p=$(readlink -f "/sys/class/block/$(basename "$1")" 2>/dev/null) || return 1
  while [ -n "$p" ] && [ "$p" != / ]; do
    [ -r "$p/speed" ] && [ -r "$p/idVendor" ] && { cat "$p/speed"; return 0; }
    p=$(dirname "$p")
  done
  return 1
}

# Find the GPIO chip and sysfs base by label; kernels renumber them, labels stay.
gpio_detect() {   # prints "CHIP BASE" (BASE may be empty)
  local chip="" base="" c
  if command -v gpiodetect >/dev/null 2>&1; then
    chip=$(gpiodetect 2>/dev/null | awk -v l="$GPIO_CHIP_LABEL" 'index($0, "[" l "]") { print $1; exit }')
  fi
  for c in /sys/class/gpio/gpiochip*; do
    [ -r "$c/label" ] || continue
    [ "$(cat "$c/label")" = "$GPIO_CHIP_LABEL" ] && base=$(cat "$c/base")
  done
  echo "${chip:-} ${base:-}"
}
