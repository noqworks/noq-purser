#!/bin/bash
# NOQ Purser: install the box software onto a Debian/Armbian root.
#   box/install.sh                  install onto this running system (needs network once, for apt)
#   box/install.sh --root DIR       install into an image root (no apt, no services started)
#   box/install.sh --packages       print the package list and exit
# Re-runnable. Does not touch an existing /etc/purser/purser.conf or anything in the state area.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=""
PACKAGES=(rsync openssh-client openssh-server btrfs-progs cryptsetup-bin curl ca-certificates nftables chrony
          util-linux util-linux-extra argon2 smartmontools kmod udev)
case ${1:-} in
  --packages) printf '%s\n' "${PACKAGES[@]}"; exit 0 ;;
  --root) ROOT=$(readlink -f "${2:?image root}") ;;
  "") ;;
  *) echo "usage: $0 [--root DIR | --packages]" >&2; exit 2 ;;
esac
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
LIB=$ROOT/usr/local/lib/purser
in_root() { if [ -n "$ROOT" ]; then chroot "$ROOT" "$@"; else "$@"; fi; }

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
install -m 0755 "$HERE/purser" "$HERE/purser-console" "$ROOT/usr/local/sbin/"
install -m 0755 "$HERE/../image/purser-card-migrate" "$ROOT/usr/local/sbin/" 2>/dev/null || true
install -m 0644 "$HERE"/systemd/*.service "$HERE"/systemd/*.timer "$ROOT/etc/systemd/system/"
install -d "$ROOT/etc/udev/rules.d" "$ROOT/etc/modprobe.d"
install -m 0644 "$HERE/conf/purser-usb.rules" "$ROOT/etc/udev/rules.d/90-purser-usb.rules"
install -m 0644 "$HERE/conf/purser-wireless.conf" "$ROOT/etc/modprobe.d/purser-wireless.conf"

for u in purser-rsync purser-dogrula; do
  in_root id "$u" >/dev/null 2>&1 || in_root useradd --system --no-create-home --shell /usr/sbin/nologin "$u"
done
install -d -m 0755 "$ROOT/etc/purser" "$ROOT/etc/purser/ssh" "$ROOT/srv/purser"
install -d -m 0700 "$ROOT/etc/purser/sirlar" "$ROOT/var/lib/purser"

# Serial console: agetty starts the restricted console instead of login.
install -d "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -n -l /usr/local/sbin/purser-console --keep-baud 115200,57600,38400,9600 %%I $TERM\n' \
  > "$ROOT/etc/systemd/system/serial-getty@ttyS0.service.d/purser.conf"

if [ -n "$ROOT" ]; then
  systemctl --root="$ROOT" enable purser-boot.service purser-firstboot.service serial-getty@ttyS0.service >/dev/null
  systemctl --root="$ROOT" disable ssh.service ssh.socket >/dev/null 2>&1 || true
  systemctl --root="$ROOT" mask ssh.service getty@tty1.service >/dev/null 2>&1 || true
else
  systemctl daemon-reload
  systemctl enable purser-boot.service purser-firstboot.service >/dev/null
  echo "Installed. Next: purser setup (on the serial console), or reboot to run the first-boot service."
fi
