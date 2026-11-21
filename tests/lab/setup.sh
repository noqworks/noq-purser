#!/bin/bash
# Test lab inside the privileged, systemd-booted test container: a server (gate on
# 127.0.0.1:2222) and a box (simulated GPIO, simulated LUKS, a real btrfs on a loop file).
# Nothing here may run on a real machine; assert.sh refuses outside the container.
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
  install -d /usr/local/sbin
  cat > /usr/local/sbin/cryptsetup <<'EOF'
#!/bin/bash
# fake cryptsetup for the test lab: the "LUKS" device is the loop device itself
set -euo pipefail
M=${FAKE_MAPPER_DIR:-/run/sim/mapper}
case $1 in
  open) dev=$4; name=$5; [ "$2" = --key-file ] && [ -r "$3" ] || exit 2; mkdir -p "$M"; ln -sfn "$dev" "$M/$name" ;;
  close) rm -f "$M/$2" ;;
  luksUUID) echo test-0001 ;;
  isLuks) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod 0755 /usr/local/sbin/cryptsetup
  # tools that must never reach hardware from the lab
  for t in i2cget i2cdetect hwclock sg_start smartctl gpioget gpioset gpiodetect udisksctl; do
    printf '#!/bin/sh\nexit 1\n' > "/usr/local/sbin/$t"; chmod 0755 "/usr/local/sbin/$t"
  done
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
  systemctl disable --now purser-firstboot.service purser-gpio.service >/dev/null 2>&1 || true
  rm -rf "$SIM"; install -d "$SIM" "$SIM/by-uuid" "$SIM/mapper"
  echo 0 > "$SIM/relay"; echo 0 > "$SIM/relay-ons"
  cat > "$SIM/on-relay" <<'EOF'
#!/bin/bash
# simulated relay: the disk "appears" on USB only while it has power
if [ "$1" = 1 ]; then
  ln -sfn "$(cat /run/sim/loopdev)" /run/sim/by-uuid/test-0001
  echo $(( $(cat /run/sim/relay-ons) + 1 )) > /run/sim/relay-ons
else rm -f /run/sim/by-uuid/test-0001; fi
EOF
  chmod 0755 "$SIM/on-relay"
  cat > /etc/purser/purser.conf <<'EOF'
SERVER="127.0.0.1"
SERVER_PORT="2222"
SERVER_USER="purser"
KINDS="pgbackrest:pgdemo borg:borgdemo restic:resticdemo dir:dumps"
LUKS_UUID="test-0001"
LANG_UI="en"
NOTIFY_KIND="ntfy"
NOTIFY_CA="/etc/purser/test-ca.pem"
POLL_UNTIL="00:00"
POLL_EVERY="1"
MAX_MIN="80"
LONG_DOW="7"
GPIO_MODE="sim"
SIM_DIR="/run/sim"
BY_UUID_DIR="/run/sim/by-uuid"
MAPPER_DIR="/run/sim/mapper"
DISK_WAIT="5"
DISK_SPINDOWN_WAIT="0"
MAX_FILE_SIZE="64M"
RELAY_LINE="71"
SENSE_LINE="75"
LED_G_LINE="69"
LED_R_LINE="72"
EOF
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

disk_up() {
  if [ -s "$SIM/loopdev" ]; then losetup -d "$(cat "$SIM/loopdev")" 2>/dev/null || true; fi
  rm -f "$DISK_IMG"; truncate -s "${LAB_DISK_SIZE:-1536M}" "$DISK_IMG"
  local n dev
  n=$(cat /sys/module/loop/parameters/max_loop 2>/dev/null || echo 0)
  # the container's /dev may lack the node the host kernel hands out ("/dev/loopN (lost)")
  dev=$(losetup -f 2>/dev/null | grep -o '/dev/loop[0-9]*' | head -1)
  [ -n "$dev" ] || { echo "no free loop device" >&2; exit 1; }
  [ -e "$dev" ] || mknod "$dev" b 7 "${dev#/dev/loop}"
  losetup "$dev" "$DISK_IMG"
  echo "$dev" > "$SIM/loopdev"; echo "$dev" >> /run/purser-test/loops
  mkfs.btrfs -q -L purser "$dev"
  : "$n"
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
  umount /srv/purser 2>/dev/null || true; rm -f "$SIM/mapper/purser" "$SIM/by-uuid/test-0001"; echo 0 > "$SIM/relay"
}

install -d /run/purser-test
case ${1:-full} in
  full) sanitize_dev; fake_tools; server_up; box_up; disk_up; notify_endpoint ;;
  reset-box) reset_box_state; disk_up; : > /run/purser-test/notify.log ;;
  reset-all) reset_box_state; rm -rf /srv/server/generation/* /srv/server/ack/* /srv/server/ack/.contact /srv/server/cache/* /srv/src/*
             disk_up; : > /run/purser-test/notify.log ;;
esac
