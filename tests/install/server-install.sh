#!/bin/bash
# Server-side install test on Debian 13, Ubuntu 24.04 and Ubuntu 26.04, each in a fresh
# systemd container (needs network inside the container for apt). Runs on the host.
#   tests/install/server-install.sh [image ...]
set -uo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
IMAGES=("$@"); [ ${#IMAGES[@]} -gt 0 ] || IMAGES=(debian:trixie ubuntu:24.04 ubuntu:26.04)
rc=0; summary=()
for base in "${IMAGES[@]}"; do
  tag=purser-srv-test:${base//[:.\/]/-}; name=purser-srv-$$-${base//[:.\/]/-}
  if ! docker build --pull -q --build-arg BASE="$base" -t "$tag" "$REPO/tests/install" >/dev/null; then
    summary+=("$base: image build failed (untested)"); rc=1; continue
  fi
  docker run -d --name "$name" --privileged --cgroupns=private --tmpfs /run:rw,exec,nosuid,size=64m --tmpfs /run/lock \
    -v "$REPO:/src:ro" "$tag" >/dev/null
  for _ in $(seq 1 30); do s=$(docker exec "$name" systemctl is-system-running 2>/dev/null || true); case $s in running|degraded) break ;; esac; sleep 1; done
  out=$(docker exec "$name" bash /src/tests/install/inner.sh 2>&1); r=$?
  printf '%s\n' "$out" | grep -E '^(==|  ok|  FAIL)'
  [ $r -eq 0 ] || { rc=1; printf '%s\n' "$out" | grep -vE '^(  ok|  FAIL)' | tail -25; }
  summary+=("$(printf '%s\n' "$out" | sed -n 's/^RESULT //p' | awk '{ printf "%s %s: %s passed, %s failed", $1, $2, $3, $4 }')")
  docker rm -f "$name" >/dev/null
  [ "${PURSER_KEEP_IMAGE:-0}" = 1 ] || docker rmi -f "$tag" >/dev/null 2>&1 || true
done
echo; echo "== server install"; printf '  %s\n' "${summary[@]}"
exit $rc
