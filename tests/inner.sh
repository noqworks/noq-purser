#!/bin/bash
# Inside the test container: set up the lab once, run the suites, print a summary.
set -uo pipefail
ssh-keygen -A >/dev/null 2>&1 || true   # the image carries no host keys; this container makes its own
. /src/tests/lib/assert.sh >/dev/null
SUITES=("$@"); [ ${#SUITES[@]} -gt 0 ] || SUITES=(shellcheck unit e2e attack compat)
export T_RESULTS=/run/purser-test/results
mkdir -p /run/purser-test; : > "$T_RESULTS"
bash /src/tests/lab/setup.sh full || { echo "lab setup failed"; exit 1; }
rc=0
for s in "${SUITES[@]}"; do
  case $s in
    shellcheck) bash /src/tests/shellcheck.sh || rc=1 ;;
    unit|e2e|attack|compat)
      for t in /src/tests/"$s"/*.sh; do
        [ -e "$t" ] || continue
        case $t in */make-fixture.sh|*/lib-*.sh) continue ;; esac
        echo "== $s/$(basename "$t")"
        bash "$t" || rc=1
      done ;;
    *) echo "unknown suite $s"; rc=1 ;;
  esac
done
echo
echo "== summary"
awk '{ p += $2; f += $3; printf "  %-28s %4d passed %4d failed\n", $1, $2, $3 } END { printf "  %-28s %4d passed %4d failed\n", "TOTAL", p, f }' "$T_RESULTS"
exit $rc
