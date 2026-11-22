#!/bin/bash
# NOQ Purser: build the box image (Orange Pi Zero 3) from a pinned, checksummed Armbian release.
#
#   image/build-image.sh [--cache DIR] [--out DIR] [--setup-conf FILE] [--rebuild-base] [--no-upgrade]
#
#   --cache DIR        downloads and build stages (default ./build-cache)
#   --out DIR          result: noq-purser-<version>-orangepizero3-<date>.img.xz + .sha256 (default ./out)
#   --setup-conf FILE  embed FILE as /etc/purser/setup.conf: unattended first boot (image/setup.conf.example)
#   --rebuild-base     redo stage 1 (base + packages) even if it is cached
#   --no-upgrade       stage 1 installs the packages but does not upgrade the base packages
#
# Needs only Docker on the build host. Everything runs in a container; arm64 programs of the
# image run under proot + qemu user emulation, nothing is registered with the host kernel.
# Packages are installed into the image here, at build time. The box itself never fetches code
# or packages: its firewall has no way out for it and its apt timers are masked.
#
# Stage 1 (cached): base image -> rootfs -> distribution upgrade (Armbian kernel and boot loader
# held) -> the packages of box/install.sh --packages. Stage 2 (each build): NOQ Purser files,
# image hygiene, smoke test inside the rootfs, written back into the base image's own file
# system (same partition table, same root UUID), compressed.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)

# The pinned base: Armbian 25.5.1 (stable), Debian 12, kernel 6.12, minimal, Orange Pi Zero 3.
ARMBIAN_FILE=Armbian_25.5.1_Orangepizero3_bookworm_current_6.12.23_minimal.img.xz
ARMBIAN_URL=https://archive.armbian.com/orangepizero3/archive/$ARMBIAN_FILE
ARMBIAN_SHA256=34f76f8266b56e714644610bb792e8932726330b044f15f21505191b8062cf07

CACHE=$PWD/build-cache OUT=$PWD/out SETUP_CONF="" REBUILD_BASE=0 UPGRADE=1
while [ $# -gt 0 ]; do
  case $1 in
    --cache) CACHE=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --setup-conf) SETUP_CONF=$(readlink -f "$2"); shift 2 ;;
    --rebuild-base) REBUILD_BASE=1; shift ;;
    --no-upgrade) UPGRADE=0; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
command -v docker >/dev/null || { echo "docker is required" >&2; exit 2; }
[ -z "$SETUP_CONF" ] || [ -r "$SETUP_CONF" ] || { echo "cannot read $SETUP_CONF" >&2; exit 2; }
mkdir -p "$CACHE" "$OUT"
CACHE=$(readlink -f "$CACHE"); OUT=$(readlink -f "$OUT")

# 1. the base image, verified against the pinned checksum before anything reads it
if [ ! -s "$CACHE/$ARMBIAN_FILE" ]; then
  echo "== downloading $ARMBIAN_FILE"
  curl -fL --retry 3 -o "$CACHE/$ARMBIAN_FILE.part" "$ARMBIAN_URL"
  mv "$CACHE/$ARMBIAN_FILE.part" "$CACHE/$ARMBIAN_FILE"
fi
echo "== verifying $ARMBIAN_FILE"
echo "$ARMBIAN_SHA256  $CACHE/$ARMBIAN_FILE" | sha256sum -c --quiet - \
  || { echo "checksum mismatch: $CACHE/$ARMBIAN_FILE is not the pinned release" >&2; exit 1; }

# 2. the build container
docker build --pull -q -t purser-image-builder:trixie "$REPO/image/builder" >/dev/null

# 3. both stages inside it. The loop lock is shared with tests/run.sh: loop devices are global
# to the host kernel, so a loop device is attached only while the lock is held.
LOCK=${PURSER_LOOP_LOCK:-/tmp/noq-purser-loop.lock}
touch "$LOCK"
commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
[ -n "$(git -C "$REPO" status --porcelain 2>/dev/null)" ] && commit=$commit-dirty
mounts=(-v "$REPO:/src:ro" -v "$CACHE:/cache" -v "$OUT:/out" -v "$LOCK:/lock")
[ -n "$SETUP_CONF" ] && mounts+=(-v "$SETUP_CONF:/setup.conf:ro")
name=purser-image-build-$$
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; [ "${PURSER_KEEP_IMAGE:-0}" = 1 ] || docker rmi -f purser-image-builder:trixie >/dev/null 2>&1 || true' EXIT
docker run --rm --name "$name" --privileged "${mounts[@]}" \
  -e BASE_XZ="/cache/$ARMBIAN_FILE" -e BASE_FILE="$ARMBIAN_FILE" -e BASE_SHA256="$ARMBIAN_SHA256" \
  -e REBUILD_BASE="$REBUILD_BASE" -e UPGRADE="$UPGRADE" -e GIT_COMMIT="$commit" \
  -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}" \
  purser-image-builder:trixie bash /src/image/build-inner.sh
