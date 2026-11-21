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
