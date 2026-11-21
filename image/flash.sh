#!/bin/bash
# NOQ Purser: write the box image to an SD card (Linux and macOS).
#
#   image/flash.sh <noq-purser-....img.xz | ....img> <device> [--force-size]
#     a plain .img is the one purser-card-migrate wrote the box state into (it writes a new
#     .img.sha256 next to it)
#     Linux:  device is the whole card, e.g. /dev/sdb or /dev/mmcblk0
#     macOS:  device is the whole card, e.g. /dev/disk4 (see "diskutil list")
#   --force-size   allow a card larger than 256 GB
#
# Before anything is written: the image is checked against its .sha256 file; the device must
# be a whole, removable disk (USB or SD reader), not the disk the running system lives on, at
# most 256 GB; you type the device name back. Then its partitions are unmounted and the
# image is written and flushed. Nothing is written without the typed confirmation.
set -euo pipefail
export LC_ALL=C
MAX_BYTES=$(( 256 * 1000 * 1000 * 1000 ))
die() { echo "flash.sh: $*" >&2; exit 1; }

# Pure decision, separated so it can be tested: prints "ok" or the reason for refusing.
judge() {   # judge <whole 0|1> <removable 0|1> <system 0|1> <bytes> <force-size 0|1>
  [ "$1" = 1 ] || { echo "not a whole disk (give the disk, not a partition)"; return; }
  [ "$3" = 0 ] || { echo "this disk holds the running system"; return; }
  [ "$2" = 1 ] || { echo "not a removable disk (internal disks are refused)"; return; }
  [[ $4 =~ ^[0-9]+$ ]] && [ "$4" -gt 0 ] || { echo "size unknown (no medium?)"; return; }
  [ "$4" -le "$MAX_BYTES" ] || [ "$5" = 1 ] || { echo "larger than 256 GB; use --force-size if this really is the card"; return; }
  echo ok
}
if [ "${1:-}" = --judge ]; then shift; judge "$@"; exit 0; fi

IMG=${1:-} DEV=${2:-} FORCE_SIZE=0 TO_FILE=0
[ "${3:-}" = --force-size ] && FORCE_SIZE=1
# --to-file: test seam, writes into an existing regular file instead of a device
[ "${3:-}" = --to-file ] && TO_FILE=1
[ -n "$IMG" ] && [ -n "$DEV" ] || { sed -n '2,13p' "$0"; exit 2; }
[ -r "$IMG" ] || die "cannot read $IMG"
case $IMG in *.img.xz) CAT=(xz -dc) ;; *.img) CAT=(cat) ;; *) die "expected an .img.xz or .img file" ;; esac

# 1. checksum
SUM=$IMG.sha256
[ -r "$SUM" ] || die "missing $SUM (the checksum file published with the image)"
want=$(awk '{ print $1; exit }' "$SUM")
[[ $want =~ ^[0-9a-f]{64}$ ]] || die "$SUM does not hold a sha256"
echo "checking $IMG ..."
if command -v sha256sum >/dev/null; then have=$(sha256sum "$IMG" | cut -c1-64); else have=$(shasum -a 256 "$IMG" | cut -c1-64); fi
[ "$have" = "$want" ] || die "checksum mismatch: the image is damaged or not the published one"
echo "checksum ok"

# 2. facts about the device
OS=$(uname -s)
whole=0 removable=0 system=0 bytes=0 model="" raw=$DEV
if [ $TO_FILE = 1 ]; then
  [ -f "$DEV" ] || die "--to-file needs an existing regular file"
  whole=1 removable=1 system=0 bytes=$(( 8 * 1000 * 1000 * 1000 )) model="test file"
elif [ "$OS" = Linux ]; then
  [ -b "$DEV" ] || die "$DEV is not a block device"
  [ "$(lsblk -dno TYPE "$DEV")" = disk ] && whole=1
  name=$(basename "$DEV")
  [ "$(cat "/sys/block/$name/removable" 2>/dev/null)" = 1 ] && removable=1
  case $(lsblk -dno TRAN "$DEV" 2>/dev/null | tr -d ' ') in usb|mmc) removable=1 ;; esac
  case $name in mmcblk*) removable=1 ;; esac
  bytes=$(lsblk -bdno SIZE "$DEV" | tr -d ' ')
  model=$(lsblk -dno VENDOR,MODEL "$DEV" | sed 's/  */ /g')
  for m in / /boot /boot/efi /usr /var /home; do
    src=$(findmnt -no SOURCE "$m" 2>/dev/null || true)
    [ -b "$src" ] || continue
    for p in $(lsblk -nso NAME "$src" 2>/dev/null | sed 's/^[^a-z0-9]*//'); do
      [ "/dev/$p" = "$DEV" ] && system=1
    done
  done
  swapon --show=NAME --noheadings 2>/dev/null | while read -r s; do [ -b "$s" ] && lsblk -nso NAME "$s" 2>/dev/null | sed "s/^[^a-z0-9]*//" | grep -qx "$name" && echo hit; done | grep -q hit && system=1
elif [ "$OS" = Darwin ]; then
  [[ $DEV =~ ^/dev/disk[0-9]+$ ]] || die "give the whole disk, e.g. /dev/disk4"
  info=$(diskutil info "$DEV") || die "diskutil does not know $DEV"
  [ "$(awk -F': *' '/Whole:/ { print $2; exit }' <<< "$info")" = Yes ] && whole=1
  grep -Eq 'Removable Media: *(Removable|Yes)' <<< "$info" && removable=1
  grep -Eq 'Device Location: *External' <<< "$info" && removable=1
  grep -Eq 'Protocol: *(USB|Secure Digital)' <<< "$info" && removable=1
  bytes=$(sed -n 's/.*Disk Size:.*(\([0-9]*\) Bytes).*/\1/p' <<< "$info" | head -1)
  model=$(awk -F': *' '/Device \/ Media Name:/ { print $2; exit }' <<< "$info")
  boot=$(diskutil info / | awk -F': *' '/Part of Whole:/ { print $2; exit }')
  [ "/dev/$boot" = "$DEV" ] && system=1
  diskutil apfs list 2>/dev/null | grep -q "Physical Store.*${DEV#/dev/}s" && system=1
  raw=/dev/r${DEV#/dev/}
else
  die "unsupported system $OS (Linux or macOS)"
fi
verdict=$(judge "$whole" "$removable" "$system" "$bytes" "$FORCE_SIZE")
[ "$verdict" = ok ] || die "refusing $DEV: $verdict"

# 3. confirmation
echo
echo "  device: $DEV  ($model, $(( bytes / 1000000000 )) GB)"
echo "  EVERYTHING ON IT WILL BE ERASED."
printf 'type the device name (%s) to continue: ' "$(basename "$DEV")"
read -r answer || answer=""
[ "$answer" = "$(basename "$DEV")" ] || die "not confirmed; nothing written"

# 4. unmount, write, flush
if [ $TO_FILE = 0 ]; then
  if [ "$OS" = Linux ]; then
    for p in $(lsblk -lnpo NAME,MOUNTPOINT "$DEV" | awk 'NF == 2 { print $1 }'); do umount "$p"; done
  else
    diskutil unmountDisk "$DEV" >/dev/null
  fi
fi
echo "writing ..."
if [ "$OS" = Darwin ] && [ $TO_FILE = 0 ]; then
  "${CAT[@]}" "$IMG" | dd of="$raw" bs=4m
else
  "${CAT[@]}" "$IMG" | dd of="$raw" bs=4M conv=fsync,notrunc status=progress
fi
sync
if [ $TO_FILE = 0 ]; then
  if [ "$OS" = Linux ]; then blockdev --flushbufs "$DEV" 2>/dev/null || true; else diskutil eject "$DEV" >/dev/null || true; fi
fi
echo
echo "done. Next:"
echo "  1. moving from an older card? run image/purser-card-migrate --from <old card> --to $DEV first"
echo "     (or migrate into the .img before flashing)"
echo "  2. put the card into the board, connect the USB-SATA cable with the disk, Ethernet and power"
echo "  3. watch the serial console (115200 8N1): first boot, then \"setup\" if it asks for it"
