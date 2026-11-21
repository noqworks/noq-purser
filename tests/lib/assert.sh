# shellcheck shell=bash
# Minimal test helpers. Each test file is a bash script that sources this file.
T_PASS=0 T_FAIL=0 T_NAME=${T_NAME:-$(basename "${0%.sh}")}
T_RESULTS=${T_RESULTS:-/run/purser-test/results}
mkdir -p "$(dirname "$T_RESULTS")"

ok() {   # ok <description> <command...>
  local d=$1; shift
  if "$@" >/dev/null 2>&1; then T_PASS=$((T_PASS + 1)); printf '  ok    %s\n' "$d"
  else T_FAIL=$((T_FAIL + 1)); printf '  FAIL  %s\n' "$d"; fi
}
not() { ! "$@"; }
eq() {   # eq <description> <expected> <actual>
  if [ "$2" = "$3" ]; then T_PASS=$((T_PASS + 1)); printf '  ok    %s\n' "$1"
  else T_FAIL=$((T_FAIL + 1)); printf '  FAIL  %s (expected [%s], got [%s])\n' "$1" "$2" "$3"; fi
}
contains() { grep -qF -- "$2" "$1"; }
done_testing() {
  printf '%s %s %s\n' "$T_NAME" "$T_PASS" "$T_FAIL" >> "$T_RESULTS"
  printf '%s: %s passed, %s failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
in_container() { [ -e /.dockerenv ] || [ "${PURSER_TEST_CONTAINER:-}" = 1 ]; }
in_container || { echo "tests run only inside the test container (tests/run.sh)" >&2; exit 3; }

# The test container is privileged: its /sys is the host's. Every box call in the lab goes
# through this wrapper, which refuses a configuration that would let the box use the real /sys
# (USB reset, LED) or the real /dev/disk (the host's disks).
lab_guard() {
  local c=${PURSER_CONF:-/etc/purser/purser.conf}
  [ -e "$c" ] || return 0
  grep -qx 'SYS_DIR="/run/sim/sys"' "$c" && grep -qx 'BY_UUID_DIR="/run/sim/by-uuid"' "$c" && return 0
  echo "lab_guard: $c does not point SYS_DIR/BY_UUID_DIR at the fake tree; refusing" >&2
  exit 3
}
purser_lab() { lab_guard; /usr/local/sbin/purser "$@"; }
