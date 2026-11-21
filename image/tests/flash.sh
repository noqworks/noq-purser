#!/bin/bash
# image/flash.sh: decision table, checksum, confirmation and the write path (into a regular
# file; no device is ever written). Run by image/tests/run.sh inside a container.
# shellcheck disable=SC2034  # rc is read inside the eval of t()
set -uo pipefail
F=/src/image/flash.sh
cd /t || exit 1
pass=0 fail=0; t() { if eval "$2"; then echo "  ok    $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
j() { bash "$F" --judge "$@"; }
t "judge: removable whole card"        '[ "$(j 1 1 0 32000000000 0)" = ok ]'
t "judge: partition refused"           '[ "$(j 0 1 0 32000000000 0)" != ok ]'
t "judge: system disk refused"         '[ "$(j 1 1 1 32000000000 0)" != ok ]'
t "judge: internal disk refused"       '[ "$(j 1 0 0 32000000000 0)" != ok ]'
t "judge: no medium refused"           '[ "$(j 1 1 0 0 0)" != ok ]'
t "judge: 512 GB refused"              '[ "$(j 1 1 0 512000000000 0)" != ok ]'
t "judge: 512 GB with --force-size"    '[ "$(j 1 1 0 512000000000 1)" = ok ]'
head -c 3000000 /dev/urandom > t.img; xz -T0 -c t.img > t.img.xz; sha256sum t.img.xz > t.img.xz.sha256
cp t.img.xz bad.img.xz; printf '%064d  bad.img.xz\n' 0 > bad.img.xz.sha256
truncate -s 8M target.bin
echo nope | bash "$F" t.img.xz target.bin --to-file >/dev/null 2>&1; rc=$?
t "wrong confirmation: refused, nothing written" '[ $rc != 0 ] && ! cmp -s <(head -c 3000000 target.bin) t.img'
echo target.bin | bash "$F" bad.img.xz target.bin --to-file >/dev/null 2>&1; rc=$?
t "checksum mismatch refused" '[ $rc != 0 ]'
rm -f nosum.img.xz.sha256; cp t.img.xz nosum.img.xz
echo target.bin | bash "$F" nosum.img.xz target.bin --to-file >/dev/null 2>&1; rc=$?
t "missing checksum file refused" '[ $rc != 0 ]'
echo target.bin | bash "$F" t.img.xz target.bin --to-file >/dev/null 2>&1; rc=$?
t "write path: image content written" '[ $rc = 0 ] && cmp -s <(head -c 3000000 target.bin) t.img'
truncate -s 8M target.bin; sha256sum t.img > t.img.sha256
echo target.bin | bash "$F" t.img target.bin --to-file >/dev/null 2>&1; rc=$?
t "plain .img (migrated) with its .sha256 written" '[ $rc = 0 ] && cmp -s <(head -c 3000000 target.bin) t.img'
bash "$F" t.img.xz /t/target.bin </dev/null >/dev/null 2>&1; rc=$?
t "regular file without --to-file refused" '[ $rc != 0 ]'
rm -f t.img* bad.img* nosum.img* target.bin
echo "flash tests: $pass passed, $fail failed"; [ $fail = 0 ]
