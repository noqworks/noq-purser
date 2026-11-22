#!/bin/bash
# NOQ Purser: smoke test INSIDE the built rootfs (run by build-inner.sh under proot + qemu, so
# these are the image's own arm64 bash, coreutils, systemd and tools). Writes only to /tmp/smoke.
set -euo pipefail
T=/tmp/smoke
export TMPDIR=$T   # purser-verify leaves its mktemp dir behind when it rejects (inside the box sandbox: PrivateTmp)
fail=0
check() { if "${@:2}" >/dev/null 2>&1; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }

for f in /usr/local/sbin/purser /usr/local/sbin/purser-console /usr/local/lib/purser/purser-verify /usr/local/lib/purser/*.sh; do
  check "bash -n ${f##*/}" bash -n "$f"
done
for f in /usr/local/sbin/purser-light /usr/local/sbin/purser-maint /usr/local/sbin/purser-ui; do
  check "python compiles ${f##*/}" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f"
done
check "page present" test -s /usr/local/lib/purser/ui/index.html
check "QR decoder present" test -s /usr/local/lib/purser/ui/jsqr.min.js
check "units enabled: light, switch" sh -c 'test -L /etc/systemd/system/multi-user.target.wants/purser-light.service && test -L /etc/systemd/system/multi-user.target.wants/purser-maint.service'
check "ssh and avahi start only with the switch" sh -c '! test -L /etc/systemd/system/multi-user.target.wants/ssh.service && ! test -L /etc/systemd/system/multi-user.target.wants/avahi-daemon.service'
check "python3 runs" python3 -c "import ssl, http.server, ipaddress, shlex"
check "purser version" sh -c '/usr/local/sbin/purser version | grep -q "^NOQ Purser "'
check "purser version in Turkish catalog" sh -c 'grep -q "^USAGE|" /usr/local/lib/purser/messages/tr'

# the list format check, with the image's own grep/awk/sort
id=2026-01-14T03-10Z
{ echo "# purser-list 1"; echo "# generation=$id"; echo "# created=2026-01-14T03:11:52Z"
  echo "# clean=yes"; echo "# fresh=yes"; echo "# note=sample"
  printf '%064d  demo/backup/a.zst\n' 0; printf '%064d  demo/archive/b.zst\n' 1; } > "$T/good.list"
check "purser-verify list: good list accepted" /usr/local/lib/purser/purser-verify list "$T/good.list" "$id"
sed 's#demo/backup/a.zst#../etc/shadow#' "$T/good.list" > "$T/bad.list"
check "purser-verify list: '../' rejected" sh -c "! /usr/local/lib/purser/purser-verify list $T/bad.list $id"
r=$(/usr/local/lib/purser/purser-verify list "$T/bad.list" "$id" || true)
check "purser-verify list: reason LIST_PATH" test "$r" = LIST_PATH

mkdir -p "$T/tree/d"; printf 'hello\n' > "$T/tree/d/f"
out=$(cd "$T" && echo d/f | /usr/local/lib/purser/purser-verify hash "$T/tree")
check "purser-verify hash" sh -c "printf '%s\n' \"$out\" | grep -q '^5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03  d/f$'"
check "purser-verify hash: bytes" sh -c "printf '%s\n' \"$out\" | grep -qx '#bytes 6'"

# systemd 252 has no --expand-environment: the sandbox must take the escaping path
probe=$(PURSER_LIB=/usr/local/lib/purser bash -c '. /usr/local/lib/purser/sandbox.sh; if sandbox_expands_env; then echo escape; else echo option; fi')
v=$(systemctl --version | awk 'NR == 1 { print $2 }')
if [ "$v" -lt 254 ]; then check "sandbox probe on systemd $v: escape" test "$probe" = escape
else check "sandbox probe on systemd $v: option" test "$probe" = option; fi
esc=$(bash -c 'a="x\$HOME y"; printf "%s" "${a//\$/\$\$}"')
check "sandbox escaping" test "$esc" = 'x$$HOME y'
/lib/systemd/systemd --dump-configuration-items 2>/dev/null | sed -n 's/^\([A-Za-z]*=\).*/\1/p' | sort -u > "$T/items"
check "systemd lists its unit settings" test -s "$T/items"
for p in User Group ProtectSystem ProtectHome PrivateTmp PrivateDevices NoNewPrivileges CapabilityBoundingSet \
         RestrictSUIDSGID ProtectKernelTunables ProtectKernelModules ProtectControlGroups LockPersonality \
         SystemCallFilter SystemCallErrorNumber RuntimeMaxSec LimitFSIZE InaccessiblePaths ReadWritePaths \
         RestrictAddressFamilies PrivateNetwork; do
  check "systemd $v knows $p=" grep -qx -- "$p=" "$T/items"
done

# every tool the core calls
for b in rsync ssh ssh-keygen ssh-keyscan btrfs cryptsetup nft chronyc argon2 smartctl flock setpriv timeout \
         udevadm mountpoint systemd-run sha256sum dd shred agetty mkfs.btrfs wipefs blockdev netplan \
         python3 gpioget gpiodetect openssl avahi-daemon lsusb blkid; do
  check "tool $b" command -v "$b"
done
check "argon2 runs" sh -c 'printf 123456789012 | argon2 00112233445566778899aabbccddeeff -id -t 1 -m 10 -p 1 -e | grep -q "^.argon2id.v=19"'
check "users purser-rsync, purser-dogrula" sh -c 'id purser-rsync && id purser-dogrula'
check "chrony replaces systemd-timesyncd" sh -c '! dpkg-query -W -f "\${Status}" systemd-timesyncd 2>/dev/null | grep -q "install ok installed"'

rm -rf "$T/tree" "$T"/*.list "$T/items"
[ $fail = 0 ] && echo "smoke test: all passed" || { echo "smoke test: FAILURES"; exit 1; }
