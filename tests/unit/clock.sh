#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# Clock gate: no battery clock, chrony from the network. Untrusted clock -> no generation, no
# contact with the server, disk stays locked, one notification a day.
. /src/tests/lib/assert.sh
. /src/tests/lib/box.sh
lab_reset
core
fresh() { rm -f "$RUN_DIR"/clock.ref "$RUN_DIR"/clock.jump "$ST_CLOCK_SENT"; }

fresh; eq "synchronised, sources agree: ok" ok "$(clock_state)"
fresh; echo unsynced > /run/sim/chrony; eq "chrony not synchronised" unsynced "$(clock_state)"; rm -f /run/sim/chrony
fresh; echo 900.5 > /run/sim/chrony-offset; eq "network disagrees by 15 min" disagree "$(clock_state)"
echo -900 > /run/sim/chrony-offset; eq "negative offset counts too" disagree "$(clock_state)"; rm -f /run/sim/chrony-offset
fresh; T=1790000000
eq "first look" ok "$(PURSER_FAKE_NOW=$T PURSER_FAKE_MONO=100 clock_state)"
eq "wall clock moves with the monotonic clock: ok" ok "$(PURSER_FAKE_NOW=$((T + 500)) PURSER_FAKE_MONO=600 clock_state)"
eq "wall clock jumps 1 h ahead of the monotonic clock" jump "$(PURSER_FAKE_NOW=$((T + 4600)) PURSER_FAKE_MONO=700 clock_state)"
eq "still untrusted half an hour later" jump "$(PURSER_FAKE_NOW=$((T + 6400)) PURSER_FAKE_MONO=2500 clock_state)"
eq "trusted again an hour after the jump" ok "$(PURSER_FAKE_NOW=$((T + 8300)) PURSER_FAKE_MONO=4400 clock_state)"
eq "a backward jump counts too" jump "$(PURSER_FAKE_NOW=$((T + 1000)) PURSER_FAKE_MONO=4500 clock_state)"
# boot without a battery clock: "status" at console start, before chrony's first step, must not
# turn that step into a jump
fresh; echo unsynced > /run/sim/chrony
eq "boot: unsynced before the first step" unsynced "$(PURSER_FAKE_NOW=$((T - 10800)) PURSER_FAKE_MONO=10 clock_state)"
rm -f /run/sim/chrony
eq "boot: chrony stepped the clock 3 h forward: ok, not a jump" ok "$(PURSER_FAKE_NOW=$T PURSER_FAKE_MONO=40 clock_state)"
eq "boot: and stays ok" ok "$(PURSER_FAKE_NOW=$((T + 600)) PURSER_FAKE_MONO=640 clock_state)"
fresh
printf 'BUILD_DATE=%s\n' "$(( $(date +%s) + 30 * 86400 ))" > /run/purser-test/image-release
IMAGE_RELEASE=/run/purser-test/image-release
eq "clock before the image build date" early "$(clock_state)"
printf 'BUILD_DATE=%s\n' "$(( $(date +%s) - 30 * 86400 ))" > /run/purser-test/image-release
eq "clock after the image build date" ok "$(clock_state)"

# notification once a day per kind
fresh; clear_notes; echo unsynced > /run/sim/chrony
clock_check >/dev/null; clock_check >/dev/null; clock_check >/dev/null
eq "unsynchronised clock notified once a day" 1 "$(ncount "synchronised with network time")"
rm -f /run/sim/chrony; clock_check >/dev/null
ok "back to ok clears the reminder" not test -e "$ST_CLOCK_SENT"
fresh; clear_notes; echo 900 > /run/sim/chrony-offset; clock_check >/dev/null
ok "disagreement notified with minutes" notified "differs from the box clock by 15 minutes"
rm -f /run/sim/chrony-offset

# an untrusted night: nothing asked, nothing unlocked
fresh
first_night 2026-03-01T03-10Z
eq "trusted night: taken" tamam "$(last)"
night_activity 20260302 1; publish_generation 2026-03-02T03-10Z
c0=$(cat /srv/server/ack/.contact); o=$(opens)
echo unsynced > /run/sim/chrony; clear_notes; sleep 1
run_box untrusted
eq "untrusted clock: result" clock_untrusted "$(last)"
cur=$(cat /srv/server/ack/.contact); case $cur in "$c0"|*" note "*) r=ok ;; *) r=$cur ;; esac
eq "the server was asked for nothing (only the alarm note went out)" ok "$r"
eq "LUKS never opened" "$o" "$(opens)"
ok "disk locked" locked
ok "notified: no generation, clock not trusted" notified "the clock cannot be trusted (not synchronised)"
$P tick >/dev/null 2>&1; $P tick >/dev/null 2>&1
eq "clock notification once a day across run and ticks" 1 "$(ncount "synchronised with network time")"
eq "last published unchanged" 2026-03-01T03-10Z "$(cat "$ST/son-yayin")"
rm -f /run/sim/chrony
run_box trusted-again
eq "clock trusted again: the waiting generation is taken" 2026-03-02T03-10Z "$(cat "$ST/son-yayin")"
# image newer than the clock: early
night_activity 20260303 2; publish_generation 2026-03-03T03-10Z
printf 'BUILD_DATE=%s\n' "$(( $(date +%s) + 30 * 86400 ))" > /run/purser-test/image-release
conf IMAGE_RELEASE /run/purser-test/image-release
clear_notes; run_box early
eq "clock earlier than the image: nothing taken" clock_untrusted "$(last)"
ok "notified: clock earlier than the image" notified "earlier than the build date"
unconf IMAGE_RELEASE

# battery clock (DS3231): simulated sysfs, never written in the lab (/dev/rtc9 does not exist)
R9=/run/sim/sys/class/rtc/rtc9; IMAGE_RELEASE=/run/purser-test/image-release; printf "BUILD_DATE=%s\n" "$(( $(date +%s) - 30 * 86400 ))" > "$IMAGE_RELEASE"
rtc_sim() { mkdir -p "$R9"; echo "rtc-ds1307 3-0068" > "$R9/name"; echo "$1" > "$R9/since_epoch"; }
fresh; rm -f "$STATE/rtc"; echo unsynced > /run/sim/chrony
rtc_sim "$(date +%s)"
eq "battery clock present but never set: not trusted" unsynced "$(clock_state)"
eq "clock source without network time or a set battery clock: none" none "$(clock_source)"
printf 'at=1\nsource=phone\n' > "$STATE/rtc"
eq "battery clock set: trusted without network time" ok "$(clock_state)"
eq "clock source: battery clock" rtc "$(clock_source)"
fresh; rtc_sim "$(( $(date +%s) - 3600 ))"
eq "system clock an hour away from the battery clock: disagree" disagree "$(clock_state)"
eq "the difference is recorded for the alarm" 3600 "$(( $(cat "$RUN_DIR/clock.diff") / 60 * 60 ))"
fresh; rm -f "$R9/since_epoch"
eq "battery clock unreadable (oscillator stopped): not trusted" unsynced "$(clock_state)"
fresh; rtc_sim 1000000000
eq "battery clock before the image build: not trusted" unsynced "$(clock_state)"
rm -f /run/sim/chrony; fresh; rtc_sim "$(( $(date +%s) - 3600 ))"
eq "network time and a set battery clock an hour apart: disagree" disagree "$(clock_state)"
fresh; rtc_sim "$(date +%s)"
eq "network time and the battery clock agree: ok" ok "$(clock_state)"
eq "clock source with network time: ntp" ntp "$(clock_source)"
ok "rtc-set refuses while network time is synchronised" not cmd_rtc_set "$(date +%s)"
rm -rf "$R9" "$STATE/rtc"; fresh
ok "rtc-set refuses without a battery clock" not cmd_rtc_set "$(date +%s)"
eq "no battery clock: network time as before" ok "$(clock_state)"
done_testing
