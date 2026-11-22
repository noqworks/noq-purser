#!/bin/bash
# NOQ Purser test suite. Runs on any Linux host with Docker; everything happens inside a
# disposable privileged container booted with systemd (the box sandbox is the real
# systemd-run). No hardware: LUKS and the box's sysfs are simulated, btrfs is a loop file.
#   tests/run.sh                      all suites
#   tests/run.sh unit e2e attack      selected suites (shellcheck unit e2e attack compat)
#   tests/run.sh --make-fixture <original core> <out dir>   rebuild the compatibility fixture
#   tests/run.sh --server-install     server install on Debian 13, Ubuntu 24.04, Ubuntu 26.04
#   tests/run.sh --image-tools        flash.sh and purser-card-migrate (image/tests)
#   PURSER_TEST_BASE=debian:bookworm tests/run.sh   the same suites on the box image's Debian
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
BASE=${PURSER_TEST_BASE:-debian:trixie}   # debian:bookworm = the box image's Debian
IMAGE=purser-test:${BASE#debian:}
NAME=purser-lab-$$
command -v docker >/dev/null || { echo "docker is required" >&2; exit 2; }
[ -e /.dockerenv ] && { echo "run this on the host, not inside a container" >&2; exit 2; }

if [ "${1:-}" = --server-install ]; then shift; exec bash "$REPO/tests/install/server-install.sh" "$@"; fi
if [ "${1:-}" = --image-tools ]; then exec bash "$REPO/image/tests/run.sh"; fi

# Loop devices are global to the host kernel: lab runs and the image build take turns.
exec 8>"${PURSER_LOOP_LOCK:-/tmp/noq-purser-loop.lock}"
flock 8
docker build --pull -q --build-arg BASE="$BASE" -t "$IMAGE" "$REPO/tests/container" >/dev/null
mounts=(-v "$REPO:/src:ro")
if [ "${1:-}" = --make-fixture ]; then
  old=$(readlink -f "${2:?original core}"); out=$(readlink -f "${3:?out dir}"); mkdir -p "$out"
  mounts+=(-v "$old:/old/purser-v0:ro" -v "$out:/out")
fi
before=$(losetup -l -n -O BACK-FILE 2>/dev/null | sort | md5sum)
cleanup() {
  docker exec "$NAME" sh -c 'umount -R /srv/purser 2>/dev/null; for l in $(cat /run/purser-test/loops 2>/dev/null); do losetup -d "$l" 2>/dev/null; done' >/dev/null 2>&1 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # the image is rebuilt (pulled + patched) on every run; do not leave it on the host for scanners and attackers
  [ "${PURSER_KEEP_IMAGE:-0}" = 1 ] || docker rmi -f "$IMAGE" >/dev/null 2>&1 || true
  after=$(losetup -l -n -O BACK-FILE 2>/dev/null | sort | md5sum)
  [ "$before" = "$after" ] && echo "host loop devices: unchanged" || echo "WARNING: host loop device list changed" >&2
}
trap cleanup EXIT
docker run -d --name "$NAME" --privileged --cgroupns=private --tmpfs /run:rw,exec,nosuid,size=512m --tmpfs /run/lock --tmpfs /tmp:rw,exec,size=1g \
  "${mounts[@]}" "$IMAGE" >/dev/null
for _ in $(seq 1 30); do
  s=$(docker exec "$NAME" systemctl is-system-running 2>/dev/null || true)
  case $s in running|degraded) break ;; esac; sleep 1
done
if [ "${1:-}" = --make-fixture ]; then
  docker exec "$NAME" bash /src/tests/lab/setup.sh full
  docker exec "$NAME" bash /src/tests/compat/make-fixture.sh /old/purser-v0 /out
  exit 0
fi
docker exec "$NAME" bash /src/tests/inner.sh "$@"
