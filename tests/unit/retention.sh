#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Retention counts generations and never trusts a date; disk full; deletion paused.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
mount_disk
area() { btrfs -q subvolume delete "$G"/* >/dev/null 2>&1; rm -rf "${G:?}" "${A:?}"; install -d "$G" "$A"/{liste,meta,supheli,temiz,pin}; }
mkgen() { btrfs -q subvolume create "$G/gen-$1"; echo "bayt=1" > "$A/meta/$1"; }
mkuzun() { btrfs -q subvolume create "$G/uzun-$1"; }
ids() { local start=$1 n=$2 step=${3:-1} i; for (( i = 0; i < n; i++ )); do date -u -d "$start +$(( i * step )) days" +%Y-%m-%dT03-10Z; done; }

# --- daily by count; a wrong clock changes nothing ---
area
for id in $(ids 2026-03-01 20); do mkgen "$id"; done
for id in 2026-02-01T03-10Z 2026-02-08T03-10Z 2026-02-15T03-10Z; do mkuzun "$id"; done
k0=$(retention_keep)
eq "same keep set with the clock in 2100" "$k0" "$(PURSER_FAKE_NOW=4102444800 retention_keep)"
eq "same keep set with the clock at 1970" "$k0" "$(PURSER_FAKE_NOW=86400 retention_keep)"
retention_apply 2>/dev/null
eq "14 daily generations kept" 14 "$(generations 'gen-*' | wc -l)"
eq "the oldest kept daily is the 7th" gen-2026-03-07T03-10Z "$(generations 'gen-*' | head -1)"
eq "weekly copies untouched" 3 "$(generations 'uzun-*' | wc -l)"

# --- forged ids: every night looks like a new week ---
area; cuts=0
for id in $(ids 2026-03-01 20 7); do
  mkgen "$id"
  if long_cut_due "$id"; then long_cut "$id" >/dev/null 2>&1; cuts=$(( cuts + 1 )); fi
done
eq "20 nights of forged weekly ids: one weekly copy per $LONG_MIN_NIGHTS nights at most" 5 "$cuts"
area; cuts=0
for id in $(ids 2026-03-01 21); do
  mkgen "$id"
  if long_cut_due "$id"; then long_cut "$id" >/dev/null 2>&1; cuts=$(( cuts + 1 )); fi
done
eq "21 honest nights from a Sunday: three weekly copies" 3 "$cuts"
eq "the weekly copies are the Sundays" "uzun-2026-03-01T03-10Z uzun-2026-03-08T03-10Z uzun-2026-03-15T03-10Z" "$(generations 'uzun-*' | tr '\n' ' ' | sed 's/ $//')"

# --- monthly picks ---
area
for id in $(ids 2026-01-04 26 7); do mkuzun "$id"; done
eq "26 honest weeks: one monthly copy per month (6)" 6 "$(monthly_picks | wc -l)"
area
for id in $(ids 2026-01-01 24 31); do mkuzun "$id"; done
eq "24 weekly copies forged a month apart: one monthly per $MONTHLY_MIN_WEEKS weekly copies (8)" 8 "$(monthly_picks | wc -l)"

# --- disk full ---
area
for id in $(ids 2026-03-01 6); do mkgen "$id"; done
mkuzun 2026-02-01T03-10Z; mkuzun 2026-02-08T03-10Z; : > "$A/pin/2026-03-02T03-10Z"
disk_free_pct() { echo $(( 4 + 3 * (6 - $(generations 'gen-*' | wc -l)) )); }
DISK_MIN_FREE_PCT=10
disk_make_room 2>/dev/null; eq "room made" 0 $?
eq "only the oldest unpinned dailies went" "gen-2026-03-02T03-10Z gen-2026-03-04T03-10Z gen-2026-03-05T03-10Z gen-2026-03-06T03-10Z" "$(generations 'gen-*' | tr '\n' ' ' | sed 's/ $//')"
eq "weekly/monthly copies never deleted for room" 2 "$(generations 'uzun-*' | wc -l)"
disk_free_pct() { echo 1; }
disk_make_room 2>/dev/null
eq "hopelessly full: the newest and the pinned stay" "gen-2026-03-02T03-10Z gen-2026-03-06T03-10Z" "$(generations 'gen-*' | tr '\n' ' ' | sed 's/ $//')"
area
for id in $(ids 2026-03-01 6); do mkgen "$id"; done
: > "$A/supheli/2026-03-05T03-10Z"
disk_free_pct() { echo 2; }
disk_make_room 2>/dev/null; ok "with a suspect: no room is made" test $? -ne 0
eq "with a suspect: nothing deleted" 6 "$(generations 'gen-*' | wc -l)"
retention_apply 2>/dev/null; KEEP_DAILY=2
retention_apply 2>/dev/null; eq "with a suspect: retention deletes nothing" 6 "$(generations 'gen-*' | wc -l)"
: > "$A/temiz/2026-03-05T03-10Z"; retention_apply 2>/dev/null
eq "suspect cleared: retention resumes" 2 "$(generations 'gen-*' | wc -l)"
KEEP_DAILY=14
unset -f disk_free_pct
area; umount_disk

# --- the full night: disk full with a suspect -> no new generation ---
first_night 2026-03-01T03-10Z
mount_disk; : > "$A/supheli/2026-03-01T03-10Z"; umount_disk
conf DISK_MIN_FREE_PCT 101
night_activity 20260302 1; publish_generation 2026-03-02T03-10Z; clear_notes; run_box full
eq "disk full: result" disk_full "$(last)"
ok "disk full notified" notified "The disk is full"
eq "no new generation taken" "gen-2026-03-01T03-10Z" "$(gens 'gen-*')"
ok "disk locked" locked
unconf DISK_MIN_FREE_PCT

# --- deletion paused N days ---
clear_notes
echo 2026-03-01T03-10Z > "$ST_SUSPECT_FLAG"
kv_set "$ST_MAINT" paused_since "$(( $(date +%s) - 3 * 86400 - 60 ))"
paused_report
ok "deletion paused for 3 days notified" notified "Deletion has been paused for 3 days"
done_testing
