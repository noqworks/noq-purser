#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Operation code: Damm check digit, argon2id hash only, doubling wait, notifications, and the
# commands at the box that must refuse without it.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
rm -f "$ST_CODE" "$ST_CODE_LOCK"

# --- Damm ---
c=$(code_generate)
ok "generated code has 12 digits" test "${#c}" = 12
ok "generated code passes the Damm check" damm_valid "$c"
bad=0 all=0
for _ in 1 2 3 4 5; do
  v=$(code_generate)
  damm_valid "$v" || bad=$((bad + 1))
  for (( i = 0; i < 12; i++ )); do
    for d in 0 1 2 3 4 5 6 7 8 9; do
      [ "$d" = "${v:$i:1}" ] && continue
      all=$((all + 1)); m=${v:0:$i}$d${v:$((i + 1))}
      damm_valid "$m" && bad=$((bad + 1))
    done
  done
  for (( i = 0; i < 11; i++ )); do
    [ "${v:$i:1}" = "${v:$((i + 1)):1}" ] && continue
    all=$((all + 1)); m=${v:0:$i}${v:$((i + 1)):1}${v:$i:1}${v:$((i + 2))}
    damm_valid "$m" && bad=$((bad + 1))
  done
done
eq "every single-digit error and adjacent transposition is caught ($all variants)" 0 "$bad"
ok "code with spaces and dashes normalizes" test "$(code_normalize "${c:0:4} ${c:4:4}-${c:8:4}")" = "$c"

# --- storage ---
code_store "$c"
ok "only an argon2id hash is stored" grep -q '^hash=\$argon2id\$' "$ST_CODE"
ok "the code itself is not on the SD card" not grep -rqF "$c" "$STATE"
eq "state file mode 0600" 600 "$(stat -c %a "$ST_CODE")"
code_check "$c"; eq "right code accepted" 0 $?

# --- typos are not counted ---
typo=${c:0:11}$(( (${c:11:1} + 1) % 10 ))
code_check "$typo"; eq "Damm typo -> 2 (not counted)" 2 $?
eq "no failure counted for a typo" "" "$(kv_get "$ST_CODE_LOCK" fails)"

# --- doubling wait: 1 min, 2, 4 ... capped at 24 h ---
clear_notes
w=$(code_generate); while [ "$w" = "$c" ]; do w=$(code_generate); done
T=$(date +%s)
waits=()
for level in $(seq 1 12); do
  export PURSER_FAKE_NOW=$T
  for _ in 1 2 3; do code_check "$w"; done
  left=$(code_locked_for)
  waits+=("$left")
  T=$(( T + left + 1 ))
done
eq "waits double from 1 minute to the 24 h cap" "60 120 240 480 960 1920 3840 7680 15360 30720 61440 86400" "${waits[*]}"
export PURSER_FAKE_NOW=$(( T - 100 ))
code_check "$c"; eq "right code refused while locked" 3 $?
ok "lock notification sent" notified "entered wrongly"
eq "one lock notification per lock" 12 "$(ncount "entered wrongly")"
# a new process (as after a reboot) sees the same lock
out=$(PURSER_FAKE_NOW=$(( T - 100 )) $P status 2>&1)
ok "lock survives a new process (status shows it)" grep -q 'locked for' <<< "$out"
unset PURSER_FAKE_NOW
rm -f "$ST_CODE_LOCK" /run/purser/clock.ref /run/purser/clock.jump   # the fake time above is not a clock jump

# --- reset-code always notifies ---
clear_notes
printf 'no\n' | $P reset-code >/dev/null 2>&1
eq "reset-code without RESET does nothing" 0 "$(ncount "was reset")"
printf 'RESET\n000000000000\n' | $P reset-code >/dev/null 2>&1
ok "reset-code notifies even when the new code is not confirmed" notified "The operation code was reset"
ok "old code still valid after an unconfirmed reset" code_check "$c"

# --- commands at the box refuse without the code ---
first_night 2026-03-01T03-10Z
o=$(opens)
for cmd in "clear 2026-03-01T03-10Z" "pin 2026-03-01T03-10Z" "first-fill" "disk-on" "new-code" "shell"; do
  # shellcheck disable=SC2086
  printf '123\n456\n789\n' | $P $cmd >/dev/null 2>&1; rc=$?
  ok "'$cmd' refused with typed garbage (rc $rc)" test "$rc" -ne 0
done
eq "the disk was never unlocked by a refused command" "$o" "$(opens)"
eq "garbage is not counted as wrong codes" "" "$(kv_get "$ST_CODE_LOCK" fails)"
rm -f "$ST_CODE"
out=$(printf '\n' | $P pin 2026-03-01T03-10Z 2>&1); rc=$?
ok "without any code set, pin refuses" test "$rc" -ne 0
ok "and says how to create one" grep -q 'setup-code' <<< "$out"
eq "still never unlocked" "$o" "$(opens)"
# with the code: pin works
code_store "$c"
printf '%s\n' "$c" | $P pin 2026-03-01T03-10Z > "$LOGDIR/pin.txt" 2>&1
mount_disk; ok "with the right code, pin writes denetim/pin/<id>" test -e "$A/pin/2026-03-01T03-10Z"; umount_disk
ok "disk locked again after pin" locked
rm -f "$ST_CODE" "$ST_CODE_LOCK"
done_testing
