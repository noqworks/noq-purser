#!/bin/bash
# Tests of the image tools (flash.sh, purser-card-migrate) in a disposable container. The
# card-migrate test attaches loop devices, so it takes the host-wide loop lock.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d /tmp/purser-image-tests.XXXXXX); trap 'rm -rf "$W"' EXIT
rc=0
docker run --rm -v "$REPO:/src:ro" -v "$W:/t" purser-test:trixie bash /src/image/tests/flash.sh || rc=1
exec 8>"${PURSER_LOOP_LOCK:-/tmp/noq-purser-loop.lock}"; flock 8
docker run --rm --privileged -v "$REPO:/src:ro" -v "$W:/t" purser-test:trixie bash /src/image/tests/card-migrate.sh | tee "$W/m.out" || rc=1
grep -q 'migrate tests: [0-9]* passed, 0 failed' "$W/m.out" || rc=1
exit $rc
