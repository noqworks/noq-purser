#!/bin/bash
# NOQ Purser: install the box software onto a Debian/Armbian root.
#   box/install.sh                  install onto this running system (needs network once, for apt)
#   box/install.sh --root DIR       install into an image root (no apt, no services started)
#   box/install.sh --packages       print the package list and exit
# Re-runnable. Does not touch an existing /etc/purser/purser.conf or anything in the state area.
#   ROOT_EXEC   command prefix that runs a program inside DIR (default: chroot DIR). The image
#               build sets it to proot + qemu, so an arm64 root is prepared on any host.
#   SERIAL_TTY  UART of the restricted console (default ttyS0, the Orange Pi Zero 3 debug UART)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=""
PACKAGES=(rsync openssh-client openssh-server btrfs-progs cryptsetup-bin nftables chrony
          util-linux util-linux-extra argon2 smartmontools kmod udev usbutils
          python3 gpiod openssl avahi-daemon)
case ${1:-} in
  --packages) printf '%s\n' "${PACKAGES[@]}"; exit 0 ;;
  --root) ROOT=$(readlink -f "${2:?image root}") ;;
  "") ;;
  *) echo "usage: $0 [--root DIR | --packages]" >&2; exit 2 ;;
esac
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
LIB=$ROOT/usr/local/lib/purser
SERIAL_TTY=${SERIAL_TTY:-ttyS0}
[[ $SERIAL_TTY =~ ^tty[A-Za-z0-9]+$ ]] || { echo "bad SERIAL_TTY" >&2; exit 2; }
in_root() {
  if [ -z "$ROOT" ]; then "$@"
  elif [ -n "${ROOT_EXEC:-}" ]; then
    # shellcheck disable=SC2086  # ROOT_EXEC is a command prefix
    $ROOT_EXEC "$@"
  else chroot "$ROOT" "$@"; fi
}
root_systemctl() {   # systemctl on the image root: offline, through the image's own binary if needed
  if [ -n "${ROOT_EXEC:-}" ]; then in_root systemctl --root=/ "$@"; else systemctl --root="$ROOT" "$@"; fi
}

if [ -z "$ROOT" ]; then
  # Packages are fetched only here. The box firewall (applied later by "purser apply-config")
  # has no rule for HTTP/HTTPS out, so after setup nothing can be installed or fetched.
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "${PACKAGES[@]}"
fi

install -d -m 0755 "$LIB" "$LIB/messages" "$LIB/templates" "$ROOT/usr/local/sbin"
install -m 0644 "$HERE"/lib/*.sh "$LIB/"
install -m 0644 "$HERE"/messages/en "$HERE"/messages/tr "$LIB/messages/"
install -m 0644 "$HERE"/templates/*.in "$LIB/templates/"
install -m 0644 "$HERE/purser.conf.example" "$LIB/purser.conf.example"
install -m 0755 "$HERE/purser-verify" "$LIB/purser-verify"
install -m 0755 "$HERE/purser" "$HERE/purser-console" "$HERE/purser-light" "$HERE/purser-maint" "$HERE/purser-ui" "$ROOT/usr/local/sbin/"
install -d -m 0755 "$LIB/ui"
install -m 0644 "$HERE"/ui/* "$LIB/ui/"
printf '%s\n' "$(sed -n 's/^PURSER_VERSION=//p' "$HERE/lib/common.sh")" > "$LIB/version"
install -m 0755 "$HERE/../image/purser-card-migrate" "$ROOT/usr/local/sbin/" 2>/dev/null || true
install -m 0644 "$HERE"/systemd/*.service "$HERE"/systemd/*.timer "$ROOT/etc/systemd/system/"
install -d "$ROOT/etc/udev/rules.d" "$ROOT/etc/modprobe.d" "$ROOT/etc/ssh/sshd_config.d"
# maintenance SSH (only while the switch is on): keys only, no passwords
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\nX11Forwarding no\n' \
  > "$ROOT/etc/ssh/sshd_config.d/10-purser.conf"
install -m 0644 "$HERE/conf/purser-usb.rules" "$ROOT/etc/udev/rules.d/90-purser-usb.rules"
install -m 0644 "$HERE/conf/purser-wireless.conf" "$ROOT/etc/modprobe.d/purser-wireless.conf"

for u in purser-rsync purser-dogrula; do
  in_root id "$u" >/dev/null 2>&1 || in_root useradd --system --no-create-home --shell /usr/sbin/nologin "$u"
done
install -d -m 0755 "$ROOT/etc/purser" "$ROOT/etc/purser/ssh" "$ROOT/srv/purser"
install -d -m 0700 "$ROOT/etc/purser/sirlar" "$ROOT/var/lib/purser"

# Serial console: agetty starts the restricted console instead of login.
install -d "$ROOT/etc/systemd/system/serial-getty@$SERIAL_TTY.service.d"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -n -l /usr/local/sbin/purser-console --keep-baud 115200,57600,38400,9600 %%I $TERM\n' \
  > "$ROOT/etc/systemd/system/serial-getty@$SERIAL_TTY.service.d/purser.conf"

if [ -n "$ROOT" ]; then
  root_systemctl enable purser-boot.service purser-firstboot.service purser-light.service purser-maint.service "serial-getty@$SERIAL_TTY.service" >/dev/null
  # SSH, the page and the .local name run only while the maintenance switch is on (purser-maint)
  root_systemctl disable ssh.service ssh.socket avahi-daemon.service avahi-daemon.socket >/dev/null 2>&1 || true
  root_systemctl mask getty@tty1.service >/dev/null 2>&1 || true
else
  systemctl daemon-reload
  systemctl enable purser-boot.service purser-firstboot.service purser-light.service >/dev/null
  # purser-maint is enabled by the image (and by "purser setup"); on a running system enabling it
  # here would close SSH as soon as the switch reads "off": enable it yourself when you are at the box.
  echo "Installed. Next: purser setup (on the serial console), or reboot to run the first-boot service."
fi
