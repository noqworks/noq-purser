#!/bin/bash
# NOQ Purser image build, inside the builder container (started by image/build-image.sh).
#   /src    repository (read-only)   /cache  downloads and stages   /out  result
#   /lock   host lock file for loop devices   /setup.conf  optional unattended first boot
# arm64 programs of the image run under "proot -q qemu-aarch64" with no /proc, /sys or /dev of
# the build host inside (only null, zero, random, urandom): nothing in the image can reach
# the host kernel's settings. "enosys" (image/builder/enosys.py) makes the few syscalls this
# proot cannot translate fail with ENOSYS, so glibc uses older ones it does translate.
set -euo pipefail
: "${BASE_XZ:?}" "${BASE_FILE:?}" "${BASE_SHA256:?}" "${REBUILD_BASE:=0}" "${UPGRADE:=1}" "${GIT_COMMIT:=unknown}"
W=/cache/work
MNT=/mnt/img
STAGE1_REV=6
mkdir -p "$W" "$MNT"
step() { printf '== %s\n' "$*"; }
PACKAGES=$(bash /src/box/install.sh --packages | tr '\n' ' ')
VERSION=$(sed -n 's/^PURSER_VERSION=//p' /src/box/lib/common.sh)
[ -n "$VERSION" ] || { echo "no PURSER_VERSION" >&2; exit 1; }

# --- loop devices: attached only while /lock is held, always detached ---
LOOP=""
exec 7>/lock
loop_attach() {   # loop_attach <image> <offset> ro|rw
  flock 7
  local d ro=()
  [ "$3" = ro ] && ro=(-r)
  d=$(losetup -f 2>/dev/null | grep -o '/dev/loop[0-9]*' | head -1)
  [ -n "$d" ] || { echo "no free loop device" >&2; exit 1; }
  [ -e "$d" ] || mknod "$d" b 7 "${d#/dev/loop}"
  losetup "${ro[@]}" -o "$2" "$d" "$1"
  LOOP=$d
}
loop_detach() {
  mountpoint -q "$MNT" && umount "$MNT"
  [ -n "$LOOP" ] && losetup -d "$LOOP"
  LOOP=""
  flock -u 7
}
cleanup() {
  mountpoint -q "$MNT" && umount -l "$MNT" 2>/dev/null
  [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null
  return 0
}
trap cleanup EXIT

part_offset() { sfdisk -d "$1" | awk -F'[=,]' '/: start=/ { gsub(/ /, "", $2); print $2 * 512; exit }'; }

# --- running programs of the arm64 root ---
in_root() {   # in_root <root> command...
  local r=$1; shift
  enosys proot -q qemu-aarch64 -r "$r" -b /dev/null -b /dev/zero -b /dev/random -b /dev/urandom -w / \
    /usr/bin/env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=/root LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive "$@"
}

# --- the base image ---
if [ ! -s "$W/base.img" ] || [ "$(cat "$W/base.img.sha256" 2>/dev/null)" != "$BASE_SHA256" ]; then
  step "decompressing $BASE_FILE"
  echo "$BASE_SHA256  $BASE_XZ" | sha256sum -c --quiet -
  xz -dc "$BASE_XZ" > "$W/base.img.part"; mv "$W/base.img.part" "$W/base.img"
  echo "$BASE_SHA256" > "$W/base.img.sha256"
fi
OFFSET=$(part_offset "$W/base.img")
[ "$OFFSET" -gt 0 ] || { echo "no root partition found" >&2; exit 1; }

tar_out() { tar -C "$1" --numeric-owner --xattrs --xattrs-include='*' --acls -cpf - .; }
tar_in() { tar -C "$1" --numeric-owner --xattrs --xattrs-include='*' --acls -xpf -; }

# --- stage 1: base rootfs + upgrade + packages (cached) ---
KEY=$(printf '%s\n' "$BASE_SHA256" "$PACKAGES" "$UPGRADE" "$STAGE1_REV" | sha256sum | cut -c1-16)
S1=$W/stage1-$KEY.tar
if [ "$REBUILD_BASE" = 1 ] || [ ! -s "$S1" ]; then
  step "stage 1: base rootfs"
  R=$W/s1root; rm -rf "$R"; mkdir -p "$R"
  loop_attach "$W/base.img" "$OFFSET" ro
  mount -o ro "$LOOP" "$MNT"
  tar_out "$MNT" | tar_in "$R"
  loop_detach

  step "stage 1: packages (${PACKAGES% })"
  # name resolution for apt only; the image's own resolv.conf link is put back afterwards
  rc=$(readlink "$R/etc/resolv.conf" || true)
  rm -f "$R/etc/resolv.conf"; cp /etc/resolv.conf "$R/etc/resolv.conf"
  printf '#!/bin/sh\nexit 101\n' > "$R/usr/sbin/policy-rc.d"; chmod 0755 "$R/usr/sbin/policy-rc.d"
  # the kernel is not changed, so its initrd stays valid; it is not rebuilt under emulation
  in_root "$R" dpkg-divert --local --rename --add /usr/sbin/update-initramfs >/dev/null
  printf '#!/bin/sh\nexit 0\n' > "$R/usr/sbin/update-initramfs"; chmod 0755 "$R/usr/sbin/update-initramfs"
  # apt drops to the user _apt for downloads; under proot a program cannot start after that
  # (the emulator belongs to root), so apt's methods run as root during the build only
  APT=(apt-get -q -o APT::Sandbox::User=root)
  # Only Debian's repositories: Armbian's packages (kernel, boot loader, board support) stay
  # exactly at the pinned release, and their stale index of the base must not be used.
  install -d "$W/apt-aside"
  for f in "$R"/etc/apt/sources.list.d/armbian*.sources "$R"/etc/apt/sources.list.d/armbian*.list; do
    [ -e "$f" ] && mv "$f" "$W/apt-aside/"
  done
  rm -rf "$R"/var/lib/apt/lists/*
  in_root "$R" "${APT[@]}" update
  # Armbian's kernel, device tree, boot loader and board support stay at the pinned release
  in_root "$R" sh -c 'dpkg-query -W -f "\${Package}\n" | grep -E "^(linux-|armbian-)" | xargs -r apt-mark hold' >/dev/null
  if [ "$UPGRADE" = 1 ]; then
    in_root "$R" "${APT[@]}" -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade
  fi
  # shellcheck disable=SC2086  # package list
  in_root "$R" "${APT[@]}" -y -o Dpkg::Options::=--force-confold --no-install-recommends install $PACKAGES
  in_root "$R" sh -c 'dpkg-query -W -f "\${Package}\n" | grep -E "^(linux-|armbian-)" | xargs -r apt-mark unhold' >/dev/null
  # every name of the list must really be installed
  for p in $PACKAGES; do
    in_root "$R" dpkg-query -W -f '${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed' \
      || { echo "package $p did not install" >&2; exit 1; }
  done
  in_root "$R" "${APT[@]}" clean
  rm -f "$R/usr/sbin/update-initramfs"
  in_root "$R" dpkg-divert --local --rename --remove /usr/sbin/update-initramfs >/dev/null
  rm -f "$R/usr/sbin/policy-rc.d" "$R/etc/resolv.conf"
  [ -n "$rc" ] && ln -s "$rc" "$R/etc/resolv.conf"
  for f in "$W"/apt-aside/*; do [ -e "$f" ] && mv "$f" "$R/etc/apt/sources.list.d/"; done
  rm -rf "$R"/var/lib/apt/lists/* "$R"/var/cache/apt/*.bin
  in_root "$R" dpkg-query -W -f '${Package} ${Version}\n' > "$W/stage1-$KEY.packages"
  tar_out "$R" > "$S1.part"; mv "$S1.part" "$S1"
  rm -rf "$R"
fi

# --- stage 2: NOQ Purser, hygiene, smoke test ---
step "stage 2: NOQ Purser $VERSION"
R=$W/root; rm -rf "$R"; mkdir -p "$R"
tar_in "$R" < "$S1"
TTY=$(sed -n 's/.*console=\(ttyS[0-9]\+\),.*/\1/p' "$R/boot/boot.cmd" | head -1)
[ -n "$TTY" ] || { echo "serial console not found in boot.cmd" >&2; exit 1; }
ROOT_EXEC="enosys proot -q qemu-aarch64 -r $R -b /dev/null -b /dev/zero -b /dev/urandom -w /" SERIAL_TTY=$TTY \
  bash /src/box/install.sh --root "$R"
BUILD_DATE=${SOURCE_DATE_EPOCH:-$(date +%s)}
printf 'VERSION=%s\nBUILD_DATE=%s\nBASE=%s\nBASE_SHA256=%s\nCOMMIT=%s\nSERIAL_TTY=%s\n' \
  "$VERSION" "$BUILD_DATE" "$BASE_FILE" "$BASE_SHA256" "$GIT_COMMIT" "$TTY" > "$R/usr/local/lib/purser/image-release"
cp "$W/stage1-$KEY.packages" "$R/usr/local/lib/purser/packages.txt"

step "stage 2: image hygiene"
: > "$R/etc/machine-id"
[ -L "$R/var/lib/dbus/machine-id" ] || rm -f "$R/var/lib/dbus/machine-id"
rm -f "$R"/etc/ssh/ssh_host_*                         # Armbian's first run makes the box's own keys
sed -i 's/^root:[^:]*:/root:*:/' "$R/etc/shadow"      # no root password; there is no login anyway
rm -f "$R/root/.not_logged_in_yet" "$R/root/.bash_history"
sed -i 's/^console=.*/console=serial/' "$R/boot/armbianEnv.txt"
# the light stick: SPI1 MOSI (header pin 19). The board's device tree gives spi1 no pin setting, and
# Armbian's spidev1_0 would take PH5 (pin 3) as chip select 0, which is I2C3 SDA for the battery
# clock: our own overlay muxes MOSI/MISO/CLK and chip select 1 (PH9, pin 26, unused) -> /dev/spidev1.1
install -d "$R/boot/overlay-user"
cat > /tmp/purser-spi1.dts <<'DTS'
/dts-v1/;
/plugin/;
/ {
	compatible = "allwinner,sun50i-h616";
	fragment@0 {
		target = <&spi1>;
		__overlay__ {
			status = "okay";
			pinctrl-names = "default";
			pinctrl-0 = <&spi1_pins>, <&spi1_cs1_pin>;
			#address-cells = <1>;
			#size-cells = <0>;
			spidev@1 {
				compatible = "rohm,dh2228fv";
				status = "okay";
				reg = <1>;
				spi-max-frequency = <10000000>;
			};
		};
	};
};
DTS
dtc -q -@ -I dts -O dtb -o "$R/boot/overlay-user/purser-spi1.dtbo" /tmp/purser-spi1.dts
rm -f /tmp/purser-spi1.dts
sed -i 's/^overlays=.*/overlays=i2c3-ph/' "$R/boot/armbianEnv.txt"
grep -q '^overlays=' "$R/boot/armbianEnv.txt" || echo 'overlays=i2c3-ph' >> "$R/boot/armbianEnv.txt"
grep -q '^user_overlays=' "$R/boot/armbianEnv.txt" || echo 'user_overlays=purser-spi1' >> "$R/boot/armbianEnv.txt"
[ -e "$R/boot/dtb/allwinner/overlay/sun50i-h616-i2c3-ph.dtbo" ] || { echo "i2c3-ph overlay missing" >&2; exit 1; }
echo noq-purser > "$R/etc/hostname"
sed -i 's/^127\.0\.1\.1.*/127.0.1.1\tnoq-purser/' "$R/etc/hosts"
# ssh is not masked: purser-maint starts it while the maintenance switch is on (it is disabled)
for u in getty@tty1.service wpa_supplicant.service bluetooth.service aw859a-wifi.service \
         aw859a-bluetooth.service apt-daily.timer apt-daily-upgrade.timer armbian-led-state.service \
         systemd-timesyncd.service unattended-upgrades.service armbian-resize-filesystem.service; do
  in_root "$R" systemctl --root=/ mask "$u" >/dev/null 2>&1 || true
done
[ "$(readlink "$R/etc/resolv.conf")" = /run/systemd/resolve/stub-resolv.conf ] \
  || { echo "resolv.conf is not the image's own link" >&2; exit 1; }
find "$R/var/log" -type f -exec truncate -s 0 {} +
rm -rf "${R:?}"/tmp/* "${R:?}"/var/tmp/*
if [ -r /setup.conf ]; then
  install -m 0600 /setup.conf "$R/etc/purser/setup.conf"; step "setup.conf embedded (unattended first boot)"
fi

step "stage 2: smoke test inside the rootfs"
install -d "$R/tmp/smoke"
cp /src/image/smoke-test.sh "$R/tmp/smoke/run.sh"
in_root "$R" bash /tmp/smoke/run.sh
rm -rf "$R/tmp/smoke"

# --- write back into the base image's own file system ---
step "writing the root file system"
IMG=$W/purser.img
cp --sparse=always "$W/base.img" "$IMG"
need=$(( $(du -sx -B1 "$R" | cut -f1) * 115 / 100 ))
size=$(( $(stat -c %s "$IMG") - OFFSET ))
if [ "$need" -gt "$size" ]; then
  grow=$(( (need - size) / 1048576 + 128 ))
  step "growing the image by $grow MiB"
  truncate -s +"${grow}M" "$IMG"
  echo ", +" | sfdisk -q -N 1 "$IMG"
  loop_attach "$IMG" "$OFFSET" rw
  e2fsck -fy "$LOOP" >/dev/null || [ $? -le 1 ]
  resize2fs -p "$LOOP" >/dev/null
  loop_detach
fi
loop_attach "$IMG" "$OFFSET" rw
base_uuid=$(blkid -s UUID -o value "$LOOP")
mount "$LOOP" "$MNT"
rsync -aHAX --numeric-ids --delete "$R/" "$MNT/"
sync
umount "$MNT"
e2fsck -fy "$LOOP" >/dev/null || [ $? -le 1 ]
zerofree "$LOOP" 2>/dev/null || true
[ "$(blkid -s UUID -o value "$LOOP")" = "$base_uuid" ] || { echo "root UUID changed" >&2; exit 1; }

step "verifying the image"
mount -o ro "$LOOP" "$MNT"
bash /src/image/verify-image.sh "$MNT" "$base_uuid"
loop_detach

# the setup partition: 16 MiB FAT after the root file system ("purser setup" writes into it on the
# user's computer; the first boot takes the files over and overwrites the partition). The root
# file system is not grown at first boot (armbian-resize-filesystem is masked): it has room enough.
step "setup partition (FAT, PURSERSET)"
end=$(( $(stat -c %s "$IMG") / 512 ))
start=$(( (end + 2047) / 2048 * 2048 ))
truncate -s $(( (start + 32768) * 512 )) "$IMG"
echo "start=$start, size=32768, type=c" | sfdisk -q --append "$IMG"
SOURCE_DATE_EPOCH=$BUILD_DATE mkfs.vfat -n PURSERSET -i "$(printf %08x $(( BUILD_DATE & 0xffffffff )))" -C /tmp/purserset.img 16384 >/dev/null
printf 'NOQ Purser: "purser setup" writes the settings for the first boot here.\r\n' > /tmp/README.TXT
SOURCE_DATE_EPOCH=$BUILD_DATE mcopy -i /tmp/purserset.img /tmp/README.TXT ::README.TXT
dd if=/tmp/purserset.img of="$IMG" bs=512 seek="$start" conv=notrunc status=none
rm -f /tmp/purserset.img /tmp/README.TXT
sfdisk -d "$IMG" | sed -n 's/^[^ ]*img\([0-9]\) : /part \1: /p'

DATE=$(date -u -d "@$BUILD_DATE" +%Y%m%d)
NAME=noq-purser-$VERSION-orangepizero3-$DATE.img
step "compressing $NAME.xz"
xz -T0 -6 -c "$IMG" > "/out/$NAME.xz.part"; mv "/out/$NAME.xz.part" "/out/$NAME.xz"
(cd /out && sha256sum "$NAME.xz" > "$NAME.xz.sha256")
cp "$W/stage1-$KEY.packages" "/out/$NAME.packages.txt"
rm -f "$IMG"; rm -rf "$R"
ls -l "/out/$NAME.xz"; cat "/out/$NAME.xz.sha256"
