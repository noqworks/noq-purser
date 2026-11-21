#!/bin/bash
# Test lab inside the privileged, systemd-booted test container: a server (gate on
# 127.0.0.1:2222) and a box: a real btrfs on a loop file stands in for the USB disk, LUKS is
# simulated, and the box sees a FAKE sysfs tree (/run/sim/sys: the USB device of the disk and a
# board LED). The container is privileged, so its real /sys is the host's: the box
# configuration never points there (assert.sh refuses to run tests if it does).
#   setup.sh            full lab (server + box)
#   setup.sh reset-box  fresh disk and box state, same server
set -euo pipefail
. /src/tests/lib/assert.sh >/dev/null
SRC=/src
SIM=/run/sim
DISK_IMG=/var/tmp/purser-disk.img

sanitize_dev() {
  # The container's /dev is its own tmpfs, but privileged containers see the host's device
  # nodes. Remove every node the code could touch by mistake.
  rm -f /dev/sd* /dev/nvme* /dev/mmcblk* /dev/gpiochip* /dev/i2c-* /dev/rtc* /dev/hidraw* /dev/sg* /dev/dm-* 2>/dev/null || true
}

fake_tools() {
  install -d /usr/local/sbin "$SIM"
  cat > /usr/local/sbin/cryptsetup <<'EOF2'
#!/bin/bash
# fake cryptsetup for the test lab: the "LUKS" device is the loop device itself
set -euo pipefail
M=${FAKE_MAPPER_DIR:-/run/sim/mapper}
case $1 in
  open) dev=$4; name=$5; [ "$2" = --key-file ] && [ -r "$3" ] || exit 2; mkdir -p "$M"; ln -sfn "$dev" "$M/$name"
        echo $(( $(cat /run/sim/luks-opens 2>/dev/null || echo 0) + 1 )) > /run/sim/luks-opens ;;
  close) [ -e /run/sim/close-fails ] && exit 5; rm -f "$M/$2" ;;
  luksUUID) echo test-0001 ;;
  isLuks) exit 0 ;;
  *) exit 0 ;;
esac
EOF2
  # chrony: the state comes from /run/sim/chrony (synced | unsynced) and /run/sim/chrony-offset
  cat > /usr/local/sbin/chronyc <<'EOF2'
#!/bin/bash
st=$(cat /run/sim/chrony 2>/dev/null || echo synced)
off=$(cat /run/sim/chrony-offset 2>/dev/null || echo 0.000120)
case "$*" in
  "-c tracking")
    if [ "$st" = synced ]; then echo "C0000201,192.0.2.1,3,1767225600.0,0.000010,0.000020,0.000030,1.5,0.001,0.01,0.002,0.001,64.0,Normal"
    else echo "00000000,,0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0,0.0,Not synchronised"; fi ;;
  "-c sourcestats") echo "192.0.2.1,8,4,300,0.1,0.2,$off,0.0001" ;;
  *) exit 1 ;;
esac
EOF2
  # smartctl: a healthy SSD unless /run/sim/smart-rc says otherwise
  cat > /usr/local/sbin/smartctl <<'EOF2'
#!/bin/bash
rc=$(cat /run/sim/smart-rc 2>/dev/null || echo 0)
cat <<'S'
SMART overall-health self-assessment test result: PASSED
  9 Power_On_Hours          0x0032   100   100   000    Old_age   Always       -       1234
  5 Reallocated_Sector_Ct   0x0033   100   100   010    Pre-fail  Always       -       0
197 Current_Pending_Sector  0x0032   100   100   000    Old_age   Always       -       0
202 Percent_Lifetime_Remain 0x0030   099   099   001    Old_age   Offline      -       1
194 Temperature_Celsius     0x0022   070   050   000    Old_age   Always       -       30
S
exit "$rc"
EOF2
  # udevadm settle: a "hung bridge" comes back once its USB device was re-authorized
  cat > /usr/local/sbin/udevadm <<'EOF2'
#!/bin/bash
[ "${1:-}" = settle ] || exec /usr/bin/udevadm "$@"
h=/run/sim/bridge-hung a=/run/sim/sys/bus/usb/devices/1-1/authorized
if [ "$(cat "$h" 2>/dev/null)" = once ] && [ "$a" -nt "$h" ]; then
  ln -sfn "$(cat /run/sim/loopdev)" /run/sim/by-uuid/test-0001; rm -f "$h"
fi
exit 0
EOF2
  chmod 0755 /usr/local/sbin/cryptsetup /usr/local/sbin/chronyc /usr/local/sbin/smartctl /usr/local/sbin/udevadm
  # tools that must never reach hardware from the lab
  for t in i2cget i2cdetect hwclock sg_start gpioget gpioset gpiodetect udisksctl hdparm; do
    printf '#!/bin/sh\nexit 1\n' > "/usr/local/sbin/$t"; chmod 0755 "/usr/local/sbin/$t"
  done
}

# The box's view of sysfs: the loop device hangs off USB port 1-1 (mass storage, High Speed),
# and the board has one LED, green:status.
fake_sys() {   # fake_sys <loop device>
  local name=${1##*/} S=$SIM/sys U
  rm -rf "$S"
  U=$S/devices/platform/soc/5200000.usb/usb1/1-1
  local B=$U/1-1:1.0/host0/target0:0:0/0:0:0:0
  install -d "$B/block/$name" "$S/block" "$S/class/block" "$S/bus/usb/devices" "$S/bus/usb/drivers/usb" "$S/class/leds/green:status"
  echo 480 > "$U/speed"; echo 152d > "$U/idVendor"; echo 1 > "$U/authorized"
  echo 08 > "$U/1-1:1.0/bInterfaceClass"
  echo "TestDisk SSD" > "$B/model"; ln -s ../.. "$B/block/$name/device"
  echo $(( $(blockdev --getsize64 "$1") / 512 )) > "$B/block/$name/size"
  ln -s "../devices/platform/soc/5200000.usb/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0/block/$name" "$S/block/$name"
  ln -s "../../devices/platform/soc/5200000.usb/usb1/1-1/1-1:1.0/host0/target0:0:0/0:0:0:0/block/$name" "$S/class/block/$name"
  ln -s ../../../devices/platform/soc/5200000.usb/usb1/1-1 "$S/bus/usb/devices/1-1"
  ln -s "../../../devices/platform/soc/5200000.usb/usb1/1-1/1-1:1.0" "$S/bus/usb/devices/1-1:1.0"
  : > "$S/bus/usb/drivers/usb/bind"; : > "$S/bus/usb/drivers/usb/unbind"
  local L=$S/class/leds/green:status
  echo none > "$L/trigger"; echo 0 > "$L/brightness"; echo 1 > "$L/max_brightness"; : > "$L/delay_on"; : > "$L/delay_off"
}

server_up() {
  bash "$SRC/source/install.sh" --listen 127.0.0.1 --port 2222 --base /srv/server --timer 04:30 --no-deps >/dev/null
  install -d /srv/src
  cat > /etc/purser/source.conf <<'EOF'
BASE="/srv/server"
GATE_USER="purser"
SOURCES=("pgbackrest:/srv/src/pgdemo" "borg:/srv/src/borgdemo" "restic:/srv/src/resticdemo" "dir:/srv/src/dumps")
FREEZE="auto"
WAIT_UNITS=()
FRESH_MAX_H="1000000"
KEEP_UNACKED="3"
ALERT_CMD=(logger -t purser-alert)
EOF
  systemctl disable --now purser-source.timer >/dev/null 2>&1 || true
}

box_up() {
  bash "$SRC/box/install.sh" --root / >/dev/null
  systemctl disable --now purser-firstboot.service >/dev/null 2>&1 || true
  rm -rf "$SIM/by-uuid" "$SIM/mapper"; install -d "$SIM" "$SIM/by-uuid" "$SIM/mapper"
  lab_conf > /etc/purser/purser.conf
  install -d -m 0700 /etc/purser/sirlar
  head -c 64 /dev/urandom > /etc/purser/sirlar/luks.key; chmod 0400 /etc/purser/sirlar/luks.key
  rm -f /etc/purser/ssh/id_ed25519 /etc/purser/ssh/id_ed25519.pub
  ssh-keygen -q -t ed25519 -N '' -C purser@lab -f /etc/purser/ssh/id_ed25519
  chown purser-rsync:purser-rsync /etc/purser/ssh/id_ed25519 /etc/purser/ssh/id_ed25519.pub
  /usr/local/sbin/purser-admit 127.0.0.1 "$(cat /etc/purser/ssh/id_ed25519.pub)" >/dev/null
  sleep 1
  ssh-keyscan -T 5 -p 2222 -t ed25519 127.0.0.1 2>/dev/null > /etc/purser/ssh/known_hosts
  [ -s /etc/purser/ssh/known_hosts ] || { echo "gate did not answer" >&2; exit 1; }
}

# Lab paths every box configuration in the lab must carry (also appended to old fixtures).
lab_paths() {
  cat <<'EOF2'
SYS_DIR="/run/sim/sys"
DEV_DIR="/dev"
BY_UUID_DIR="/run/sim/by-uuid"
MAPPER_DIR="/run/sim/mapper"
NOTIFY_CA="/etc/purser/test-ca.pem"
DISK_WAIT="3"
EOF2
}
lab_conf() {
  cat <<'EOF2'
SERVER="127.0.0.1"
SERVER_PORT="2222"
SERVER_USER="purser"
KINDS="pgbackrest:pgdemo borg:borgdemo restic:resticdemo dir:dumps"
LUKS_UUID="test-0001"
LANG_UI="en"
NOTIFY_KIND="ntfy"
POLL_UNTIL="00:00"
POLL_EVERY="1"
MAX_MIN="80"
LONG_DOW="7"
MAX_FILE_SIZE="64M"
EOF2
  lab_paths
}

disk_up() {
  if [ -s "$SIM/loopdev" ]; then losetup -d "$(cat "$SIM/loopdev")" 2>/dev/null || true; fi
  rm -f "$DISK_IMG"
  if [ -n "${LAB_DISK_FROM:-}" ]; then xz -dc "$LAB_DISK_FROM" > "$DISK_IMG"; else truncate -s "${LAB_DISK_SIZE:-1536M}" "$DISK_IMG"; fi
  local dev
  # the container's /dev may lack the node the host kernel hands out ("/dev/loopN (lost)")
  dev=$(losetup -f 2>/dev/null | grep -o '/dev/loop[0-9]*' | head -1)
  [ -n "$dev" ] || { echo "no free loop device" >&2; exit 1; }
  [ -e "$dev" ] || mknod "$dev" b 7 "${dev#/dev/loop}"
  losetup "$dev" "$DISK_IMG"
  echo "$dev" > "$SIM/loopdev"; echo "$dev" >> /run/purser-test/loops
  [ -n "${LAB_DISK_FROM:-}" ] || mkfs.btrfs -q -L purser "$dev"
  fake_sys "$dev"
  # the disk is always attached: its by-uuid link exists unless a test hangs the bridge
  ln -sfn "$dev" "$SIM/by-uuid/test-0001"
  rm -f "$SIM/luks-opens" "$SIM/bridge-hung" "$SIM/close-fails" "$SIM/chrony" "$SIM/chrony-offset" "$SIM/smart-rc"
}

notify_endpoint() {
  # HTTPS endpoint that records every notification exactly as received (headers + body).
  install -d /run/purser-test
  if [ ! -s /etc/purser/test-ca.pem ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=ntfy.test -addext subjectAltName=DNS:ntfy.test \
      -keyout /run/purser-test/key.pem -out /etc/purser/test-ca.pem >/dev/null 2>&1
  fi
  grep -q ' ntfy.test' /etc/hosts || echo '127.0.0.1 ntfy.test' >> /etc/hosts
  printf 'NTFY_URL=https://ntfy.test/purser-lab\nNTFY_TOKEN=\n' > /etc/purser/sirlar/bildirim; chmod 0600 /etc/purser/sirlar/bildirim
  pkill -f purser-test-endpoint 2>/dev/null || true
  cat > /run/purser-test/endpoint.py <<'EOF'
import http.server, json, ssl, sys
LOG = "/run/purser-test/notify.log"
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode("utf-8", "replace")
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"path": self.path, "headers": dict(self.headers), "body": body}, ensure_ascii=False) + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 443), H)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain("/etc/purser/test-ca.pem", "/run/purser-test/key.pem")
s.socket = c.wrap_socket(s.socket, server_side=True)
s.serve_forever()
EOF
  : > /run/purser-test/notify.log
  (exec -a purser-test-endpoint python3 -I /run/purser-test/endpoint.py >/dev/null 2>&1 &)
  sleep 1
}

reset_box_state() {
  rm -rf /var/lib/purser /var/lib/purser-gelen /run/purser; install -d -m 0700 /var/lib/purser
  umount /srv/purser 2>/dev/null || true; rm -f "$SIM/mapper/purser"
  lab_conf > /etc/purser/purser.conf
}

install -d /run/purser-test
case ${1:-full} in
  full) sanitize_dev; fake_tools; server_up; box_up; disk_up; notify_endpoint ;;
  reset-box) reset_box_state; disk_up; : > /run/purser-test/notify.log ;;
  reset-all) reset_box_state; rm -rf /srv/server/generation/* /srv/server/ack/* /srv/server/ack/.contact /srv/server/cache/* /srv/src/*
             disk_up; : > /run/purser-test/notify.log ;;
  paths) lab_paths ;;
esac
