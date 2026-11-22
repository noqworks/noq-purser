#!/bin/bash
# NOQ Purser: checks on a built image's root file system (mounted read-only at $1).
#   verify-image.sh <mounted root> [expected root UUID]
set -euo pipefail
M=${1:?mounted root}; UUID=${2:-}
fail=0
check() { if "${@:2}" >/dev/null 2>&1; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }
link_to() { [ "$(readlink "$M$1")" = "$2" ]; }

check "image-release has VERSION, BUILD_DATE, BASE_SHA256" sh -c "grep -q '^VERSION=' $M/usr/local/lib/purser/image-release && grep -Eq '^BUILD_DATE=[0-9]+$' $M/usr/local/lib/purser/image-release && grep -Eq '^BASE_SHA256=[0-9a-f]{64}$' $M/usr/local/lib/purser/image-release"
for f in usr/local/sbin/purser usr/local/sbin/purser-console usr/local/sbin/purser-card-migrate \
         usr/local/lib/purser/purser-verify usr/local/lib/purser/messages/en usr/local/lib/purser/messages/tr \
         usr/local/lib/purser/templates/nftables.conf.in etc/udev/rules.d/90-purser-usb.rules etc/modprobe.d/purser-wireless.conf; do
  check "present: /$f" test -s "$M/$f"
done
check "no purser.conf yet (first boot or setup writes it)" test ! -e "$M/etc/purser/purser.conf"
tty=$(sed -n 's/^SERIAL_TTY=//p' "$M/usr/local/lib/purser/image-release")
for u in multi-user.target.wants/purser-boot.service multi-user.target.wants/purser-firstboot.service "getty.target.wants/serial-getty@$tty.service"; do
  check "enabled: $u" test -L "$M/etc/systemd/system/$u"
done
check "serial console runs purser-console on $tty" grep -q 'purser-console' "$M/etc/systemd/system/serial-getty@$tty.service.d/purser.conf"
for u in getty@tty1.service apt-daily.timer apt-daily-upgrade.timer wpa_supplicant.service armbian-resize-filesystem.service; do
  check "masked: $u" link_to "/etc/systemd/system/$u" /dev/null
done
for u in ssh.service avahi-daemon.service; do
  check "not enabled (only with the switch): $u" test ! -e "$M/etc/systemd/system/multi-user.target.wants/$u"
done
for u in purser-light.service purser-maint.service; do
  check "enabled: $u" test -L "$M/etc/systemd/system/multi-user.target.wants/$u"
done
check "light stick overlay (SPI1, chip select 1)" grep -q '^user_overlays=.*purser-spi1' "$M/boot/armbianEnv.txt"
check "light stick overlay file" test -s "$M/boot/overlay-user/purser-spi1.dtbo"
check "no spidev1_0 (it would take pin 3 from the clock)" bash -c '! grep -q "^overlays=.*spidev1_0" "$1/boot/armbianEnv.txt"' _ "$M"
check "battery clock bus (I2C3) overlay" grep -q '^overlays=.*i2c3-ph' "$M/boot/armbianEnv.txt"
check "battery clock driver" bash -c 'ls "$1"/lib/modules/*/kernel/drivers/rtc/rtc-ds1307.ko* >/dev/null 2>&1' _ "$M"
check "hwclock present" test -x "$M/usr/sbin/hwclock" -o -x "$M/sbin/hwclock"
for f in usr/local/sbin/purser-light usr/local/sbin/purser-maint usr/local/sbin/purser-ui usr/local/lib/purser/ui/index.html usr/local/lib/purser/pair.sh; do
  check "present: /$f" test -s "$M/$f"
done
check "nightly timer not enabled before setup" test ! -e "$M/etc/systemd/system/timers.target.wants/purser.timer"
check "machine-id empty" test ! -s "$M/etc/machine-id"
check "no SSH host keys" sh -c "! ls $M/etc/ssh/ssh_host_* 2>/dev/null | grep -q ."
check "root has no password" sh -c "grep -q '^root:\*:' $M/etc/shadow"
check "no first-login prompt" test ! -e "$M/root/.not_logged_in_yet"
check "resolv.conf is the image's own link" link_to /etc/resolv.conf /run/systemd/resolve/stub-resolv.conf
check "boot console: serial" grep -qx 'console=serial' "$M/boot/armbianEnv.txt"
check "apt lists empty (the box fetches nothing)" sh -c "[ -z \"\$(ls -A $M/var/lib/apt/lists 2>/dev/null | grep -v '^partial$' | grep -v '^lock$')\" ]"
check "no build-host traces in /tmp" sh -c "[ -z \"\$(ls -A $M/tmp)\" ]"
if [ -n "$UUID" ]; then check "fstab and armbianEnv point at root UUID $UUID" sh -c "grep -q 'UUID=$UUID' $M/etc/fstab && grep -q 'rootdev=UUID=$UUID' $M/boot/armbianEnv.txt"; fi
[ $fail = 0 ] && echo "image checks: all passed" || { echo "image checks: FAILURES"; exit 1; }
