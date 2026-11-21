#!/bin/bash
# Builds the compatibility fixture by running the ORIGINAL box core (prototype, not part of
# this repository) for seven nights against the lab server, with retention, a long-retention
# Sunday, a pin, a suspect generation and a failed acknowledgement.
#   inside the lab container: make-fixture.sh <path to the original core> <output dir>
set -euo pipefail
. /src/tests/lib/assert.sh >/dev/null
OLD=${1:?original core}; OUT=${2:?output dir}
. /src/tests/lab/data.sh
bash /src/tests/lab/setup.sh reset-all >/dev/null
install -d "$OUT" /old-shim /dev/disk/by-uuid /run/purser
printf '#!/bin/sh\ncat /run/sim/relay\n' > /old-shim/gpioget; chmod 0755 /old-shim/gpioget

# configuration exactly as the original installer wrote it, with lab values
cat > /etc/purser/purser.conf <<'X'
# NOQ Purser — kutu yapılandırması. Sır içermez; sırlar /etc/purser/sirlar ve /etc/purser/ssh altında.
SERVER=127.0.0.1
SERVER_PORT=2222
SERVER_USER=purser
LUKS_UUID=test-0001
MNT=/srv/purser
STATE=/var/lib/purser
GPIO_CHIP=gpiochip9
GPIO_BASE=
RELAY_LINE=71
RELAY_ACTIVE_LOW=1
SENSE_LINE=75
LED_G_LINE=69
LED_R_LINE=72
POLL_UNTIL=00:00
POLL_EVERY=1
MAX_MIN=80
LONG_DOW=7
KINDS="pgbackrest:pgdemo borg:borgdemo"
KEEP_DAILY=3
X

# the original core drives the relay through this FIFO ("set <line>=<value>", active low)
rm -f /run/purser/gpio; mkfifo -m 0600 /run/purser/gpio
( exec 3<>/run/purser/gpio
  while read -r _ kv <&3; do
    [ "${kv%%=*}" = 71 ] || continue
    if [ "${kv#*=}" = 0 ]; then echo 1 > /run/sim/relay; ln -sfn "$(cat /run/sim/loopdev)" /dev/disk/by-uuid/test-0001
    else echo 0 > /run/sim/relay; rm -f /dev/disk/by-uuid/test-0001; fi
  done ) &
FIFO_PID=$!
trap 'kill $FIFO_PID 2>/dev/null || true; chmod 0770 /srv/server/ack' EXIT

old() { PATH=/old-shim:$PATH FAKE_MAPPER_DIR=/dev/mapper bash "$OLD" "$@"; }

src_init
ids=(2026-01-01T03-10Z 2026-01-02T03-10Z 2026-01-03T03-10Z 2026-01-04T03-10Z 2026-01-05T03-10Z 2026-01-06T03-10Z 2026-01-07T03-10Z)
for i in "${!ids[@]}"; do
  id=${ids[$i]}; day=${id:0:4}${id:5:2}${id:8:2}
  [ "$i" -gt 0 ] && night_activity "$day" "$(date -u -d "${id:0:10}" +%u)"
  if [ "$i" = 5 ]; then   # night 6: a pgBackRest file that never changes is changed
    f=$(find /srv/src/pgdemo/backup/demo -path '*F/pg_data/base/1/2608.zst' | sort | tail -1); echo tamper >> "$f"
  fi
  [ "$i" = 6 ] && chmod 0550 /srv/server/ack   # night 7: the acknowledgement cannot be written
  publish_generation "$id"
  old run > "$OUT/night-$((i + 1)).log" 2>&1 || echo "night $((i + 1)): exit $?" >> "$OUT/nights.txt"
  [ "$i" = 1 ] && old pin "$id" >> "$OUT/night-2.log" 2>&1
  echo "night $((i + 1)) $id done" >> "$OUT/nights.txt"
done
chmod 0770 /srv/server/ack

mountpoint -q /srv/purser && { echo "disk still mounted after the original core finished" >&2; exit 1; }
sync
xz -T0 -c /var/tmp/purser-disk.img > "$OUT/disk.img.xz"
tar -C / -czf "$OUT/state.tar.gz" var/lib/purser etc/purser/purser.conf
tar -C / -czf "$OUT/server.tar.gz" srv/server/generation srv/server/ack srv/server/cache srv/src
echo "fixture written to $OUT"
