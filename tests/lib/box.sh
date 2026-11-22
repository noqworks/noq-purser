# shellcheck shell=bash
# shellcheck disable=SC2034  # shared names for the test files
# Helpers shared by the unit, attack and compat suites (sourced after assert.sh).
# shellcheck source=../lab/data.sh
. /src/tests/lab/data.sh
M=/srv/purser G=/srv/purser/nesil A=/srv/purser/denetim ST=/var/lib/purser
NOTES=/srv/server/ack/.notes NCUR=/run/purser-test/notify.cursor
P=purser_lab
LOGDIR=/run/purser-test/logs
mkdir -p "$LOGDIR"

lab_reset() { bash /src/tests/lab/setup.sh reset-all >/dev/null; }
conf() { sed -i "/^$1=/d" /etc/purser/purser.conf; echo "$1=\"$2\"" >> /etc/purser/purser.conf; }
unconf() { sed -i "/^$1=/d" /etc/purser/purser.conf; }
last() { sed -n 's/^result=//p' "$ST/last-run" 2>/dev/null; }
opens() { cat /run/sim/luks-opens 2>/dev/null || echo 0; }
locked() { ! mountpoint -q "$M" && [ ! -e /run/sim/mapper/purser ]; }
mount_disk() { mountpoint -q "$M" || mount "$(cat /run/sim/loopdev)" "$M"; }
umount_disk() { if mountpoint -q "$M"; then umount "$M"; fi; }
gens() { mount_disk; find "$G" -mindepth 1 -maxdepth 1 -name "${1:-gen-*}" -printf '%f\n' | LC_ALL=C sort; umount_disk; }

# Notifications the box raised since clear_notes, from its journal: "<event> <prio> <text>"
raised() {
  journalctl --sync 2>/dev/null || true
  local after=(); [ -s "$NCUR" ] && after=(--after-cursor "$(cat "$NCUR")")
  journalctl -q -t purser -o cat "${after[@]}" 2>/dev/null | sed -n 's/^notify \([a-z_]*\) (\([a-z]*\)): /\1 \2 /p'
}
bodies() { raised | cut -d' ' -f3-; }
notified() { bodies | grep -qF -- "$1"; }
ncount() { bodies | grep -cF -- "$1"; }
last_prio() { raised | tail -1 | cut -d' ' -f2; }
# events that reached the server through the gate since clear_notes
delivered() { tail -n +"$(( $(cat /run/purser-test/notes.mark 2>/dev/null || echo 0) + 1 ))" "$NOTES" 2>/dev/null | awk '{ print $3 }'; }
clear_notes() {
  journalctl --sync 2>/dev/null || true
  journalctl -q -n 1 --show-cursor -o cat 2>/dev/null | sed -n 's/^-- cursor: //p' > "$NCUR"
  wc -l < "$NOTES" 2>/dev/null > /run/purser-test/notes.mark || echo 0 > /run/purser-test/notes.mark
}

dayof() { local id=$1; echo "${id:0:4}${id:5:2}${id:8:2}"; }
dowof() { date -u -d "${1:0:10}" +%u; }
run_box() { $P run > "$LOGDIR/run-${1:-x}.log" 2>&1; }
# first_night <id>: fresh sources, one generation, one window
first_night() { src_init; publish_generation "$1"; run_box "$1"; }
# night <id>: ordinary activity, publish, window
night() { night_activity "$(dayof "$1")" "$(dowof "$1")"; publish_generation "$1"; run_box "$1"; }

# Load the box core into this shell (functions only), with the lab configuration.
core() {
  lab_guard
  export PURSER_LIB=/usr/local/lib/purser
  local f
  for f in common msg notify hw sandbox disk signals retention maint night code status selftest setup; do
    # shellcheck source=/dev/null
    . "$PURSER_LIB/$f.sh"
  done
  load_config; load_messages
  install -d -m 0700 "$STATE"
}
