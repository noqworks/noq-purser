#!/bin/bash
# purser-card-migrate against loop-backed fake cards (run by image/tests/run.sh inside a container).
# shellcheck disable=SC2034  # rc / oldsum are read inside the eval of t()
set -uo pipefail
M=/src/image/purser-card-migrate
cd /t || exit 1; rm -rf old old2 new newdir plain ./*.img out.txt
mk() {   # mk <dir> <img>
  truncate -s 64M "$2"; echo 'start=2048, type=83' | sfdisk -q "$2"
  mkfs.ext4 -q -F -E offset=1048576 -d "$1" "$2" 60M
}
mkdir -p old/etc/purser/sirlar old/etc/purser/ssh old/var/lib/purser new/usr/local/lib/purser new/etc/purser/ssh new/var/lib/purser
printf 'SERVER=192.0.2.10\nRELAY_LINE=71\nLED_G_LINE=69\nLUKS_UUID=test-0001\n' > old/etc/purser/purser.conf
echo SECRETMARKER-KEY > old/etc/purser/sirlar/luks.key; chmod 0400 old/etc/purser/sirlar/luks.key
echo 'NTFY_URL="https://ntfy.example.org/SECRETMARKER"' > old/etc/purser/sirlar/bildirim; chmod 0600 old/etc/purser/sirlar/bildirim
echo SECRETMARKER-SSH > old/etc/purser/ssh/id_ed25519; chmod 0600 old/etc/purser/ssh/id_ed25519; chown 997:997 old/etc/purser/ssh/id_ed25519
echo "ssh-ed25519 AAAA test" > old/etc/purser/ssh/id_ed25519.pub; echo "[192.0.2.10]:2222 ssh-ed25519 AAAA" > old/etc/purser/ssh/known_hosts
echo 2026-01-07T03-10Z > old/var/lib/purser/son-yayin; printf 'state=done\nhostkey=done\n' > old/var/lib/purser/setup
echo VERSION=1.0.0 > new/usr/local/lib/purser/image-release
mk old old.img; mk new new.img
oldsum=$(sha256sum old.img)
pass=0 fail=0; t() { if eval "$2"; then echo "  ok    $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
bash $M --from /t/old.img --to /t/new.img > out.txt 2>&1; rc=$?
cat out.txt
t "migrate into the .img succeeds" '[ $rc = 0 ]'
t "no secret printed" '! grep -q SECRETMARKER out.txt'
t "old card unchanged" '[ "$(sha256sum old.img)" = "$oldsum" ]'
t "migrated image got a new .sha256" '(cd /t && sha256sum -c --quiet new.img.sha256)'
d=$(losetup -f | grep -o "/dev/loop[0-9]*"); [ -e "$d" ] || mknod "$d" b 7 "${d#/dev/loop}"
losetup -r -o 1048576 "$d" new.img; mkdir -p /m; mount -o ro "$d" /m
t "purser.conf copied (old keys kept as they are)" 'grep -q RELAY_LINE /m/etc/purser/purser.conf'
t "luks.key mode 0400, owner root" '[ "$(stat -c %a:%u /m/etc/purser/sirlar/luks.key)" = 400:0 ]'
t "ssh key mode 0600, owner root (firstboot chowns by name)" '[ "$(stat -c %a:%u /m/etc/purser/ssh/id_ed25519)" = 600:0 ]'
t "state copied" '[ "$(cat /m/var/lib/purser/son-yayin)" = 2026-01-07T03-10Z ]'
t "setup state reset so first boot runs" '! grep -q "^state=" /m/var/lib/purser/setup && grep -q hostkey=done /m/var/lib/purser/setup'
t "migration marker" 'test -s /m/var/lib/purser/migrated'
umount /m; losetup -d "$d"
sed -i 's/SERVER=192.0.2.10/SERVER=192.0.2.11/' old/etc/purser/purser.conf; mk old old2.img
bash $M --from /t/old2.img --to /t/new.img >/dev/null 2>&1; rc=$?
t "different purser.conf on target refused" '[ $rc != 0 ]'
bash $M --from /t/old2.img --to /t/new.img --force >/dev/null 2>&1; rc=$?
t "--force replaces it" '[ $rc = 0 ]'
bash $M --from /t/new.img --to /t/old.img >/dev/null 2>&1; rc=$?
t "source without a purser box refused" '[ $rc != 0 ]'
mkdir -p plain/etc/purser; echo x > plain/etc/purser/purser.conf; mkdir -p plain/var/lib/purser; mk plain plain.img
bash $M --from /t/old.img --to /t/plain.img >/dev/null 2>&1; rc=$?
t "target that is not a NOQ Purser image refused" '[ $rc != 0 ]'
mkdir -p newdir; cp -a new/. newdir/
bash $M --from /t/old --to /t/newdir >/dev/null 2>&1; rc=$?
t "directory to directory works" '[ $rc = 0 ] && [ -e newdir/etc/purser/sirlar/luks.key ]'
t "no loop device left" '[ -z "$(losetup -l -n -O BACK-FILE | grep /t/)" ]'
echo "migrate tests: $pass passed, $fail failed"
