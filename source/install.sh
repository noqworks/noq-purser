#!/bin/bash
# NOQ Purser server side: one command, re-runnable.
#   source/install.sh --listen 192.0.2.10 [--port 2222] [--base /srv/purser] [--user purser]
#                     [--timer 04:30] [--prefix /usr/local] [--no-deps]
#   source/install.sh --uninstall      removes programs and units; keeps the data under BASE and
#                                      moves /etc/purser aside (nothing is deleted)
# Then: edit /etc/purser/source.conf, and once the box shows its key: purser-admit <ip> '<key>'
set -euo pipefail
umask 022   # the gate user reads source.conf and the programs, whatever umask root has
HERE=$(cd "$(dirname "$0")" && pwd)
LISTEN="" PORT=2222 BASE=/srv/purser GATE_USER=purser TIMER_AT=04:30 PREFIX=/usr/local DEPS=1 UNINSTALL=0
while [ $# -gt 0 ]; do
  case $1 in
    --listen) LISTEN=$2; shift 2 ;;
    --port) PORT=$2; shift 2 ;;
    --base) BASE=$2; shift 2 ;;
    --user) GATE_USER=$2; shift 2 ;;
    --timer) TIMER_AT=$2; shift 2 ;;
    --prefix) PREFIX=$2; shift 2 ;;
    --no-deps) DEPS=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
SHARE=$PREFIX/share/noq-purser
UNITS=(purser-source.service purser-source.timer purser-source-watch.service purser-source-watch.timer purser-source-notes.service purser-source-notes.path purser-sshd.service)
step() { printf '== %s\n' "$*"; }

if [ $UNINSTALL = 1 ]; then
  step "stopping units"
  [ -x "$PREFIX/sbin/purser-admit" ] && "$PREFIX/sbin/purser-admit" --revoke >/dev/null 2>&1 || true
  for u in "${UNITS[@]}"; do systemctl disable --now "$u" >/dev/null 2>&1 || true; rm -f "/etc/systemd/system/$u"; done
  rm -rf /etc/systemd/system/purser-sshd.service.d
  systemctl daemon-reload
  step "removing programs"
  rm -f "$PREFIX"/sbin/purser-source "$PREFIX"/sbin/purser-gate "$PREFIX"/sbin/purser-admit "$PREFIX"/sbin/purser-pair "$PREFIX"/sbin/purser; rm -rf "$SHARE"
  if [ -d /etc/purser ]; then
    keep=/etc/purser.removed-$(date -u +%Y%m%dT%H%M%SZ)
    mv /etc/purser "$keep"; echo "configuration moved to $keep"
  fi
  echo "The data under the configured BASE and the user '$GATE_USER' are left in place."
  exit 0
fi

# no --listen: the address used before, otherwise the address this server reaches the network with
if [ -z "$LISTEN" ] && [ -r /etc/purser/gate.conf ]; then
  LISTEN=$(sed -n 's/^LISTEN_ADDR=//p' /etc/purser/gate.conf | tail -1)
  ip -4 -o addr show 2>/dev/null | grep -q " $LISTEN/" || LISTEN=""
fi
if [ -z "$LISTEN" ]; then LISTEN=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -1); fi
[[ $LISTEN =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "give --listen <IPv4 address the box connects to>" >&2; exit 2; }
ip -4 -o addr show 2>/dev/null | grep -q " $LISTEN/" || { echo "$LISTEN is not an address of this server; give --listen <one of: $(ip -4 -o addr show scope global | awk '{ sub(/\/.*/, "", $4); printf "%s ", $4 }')>" >&2; exit 2; }
echo "gate address: $LISTEN (the box connects here)"
# the port must be free (another sshd, a tarpit, ...), unless it is our own gate
if ss -Hltnp "sport = :$PORT" 2>/dev/null | grep -v '"sshd"' | grep -q .; then
  if ! systemctl -q is-active purser-sshd 2>/dev/null; then
    echo "port $PORT is already in use on this server ($(ss -Hltnp "sport = :$PORT" | grep -o 'users:(("[^"]*' | head -1 | cut -d'"' -f2)); give --port <a free port>" >&2; exit 2
  fi
fi
[[ $PORT =~ ^[0-9]+$ ]] && [ "$PORT" -gt 0 ] && [ "$PORT" -lt 65536 ] || { echo "bad --port" >&2; exit 2; }
[[ $TIMER_AT =~ ^[0-2][0-9]:[0-5][0-9]$ ]] || { echo "bad --timer (HH:MM)" >&2; exit 2; }
[[ $BASE =~ ^/[A-Za-z0-9._/-]+$ ]] || { echo "bad --base" >&2; exit 2; }

step "dependencies"
need=()
command -v rsync >/dev/null || need+=(rsync)
command -v sshd >/dev/null 2>&1 || [ -x /usr/sbin/sshd ] || need+=(openssh-server)
command -v runuser >/dev/null || need+=(util-linux)
# rrsync (the read-only rsync wrapper of the rsync package) is a python3 script on current
# distributions; rsync only "suggests" python3.
command -v python3 >/dev/null || need+=(python3)
if [ ${#need[@]} -gt 0 ]; then
  if [ $DEPS = 1 ] && command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "${need[@]}" \
      || { apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends "${need[@]}"; }
  else echo "missing packages: ${need[*]}" >&2; exit 1; fi
fi
# optional: the pairing QR code in the terminal (without it "purser pair" shows the line only)
if ! command -v qrencode >/dev/null && [ $DEPS = 1 ] && command -v apt-get >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends qrencode >/dev/null 2>&1 \
    || echo "note: qrencode not installed; purser pair will show the pairing line without a QR code"
fi
RRSYNC=$(command -v rrsync || true)
if [ -n "$RRSYNC" ] && head -1 "$RRSYNC" | grep -q python && ! command -v python3 >/dev/null; then
  echo "rrsync needs python3, which is missing" >&2; exit 1
fi
if [ -z "$RRSYNC" ] && [ -r /usr/share/doc/rsync/scripts/rrsync.gz ]; then
  install -d "$SHARE"; gunzip -c /usr/share/doc/rsync/scripts/rrsync.gz > "$SHARE/rrsync"; chmod 0755 "$SHARE/rrsync"; RRSYNC=$SHARE/rrsync
fi
[ -n "$RRSYNC" ] || { echo "rrsync not found (part of the rsync package)" >&2; exit 1; }

step "user $GATE_USER"
if ! id "$GATE_USER" >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$BASE" --no-create-home --shell /bin/sh "$GATE_USER"
fi
usermod -p '*' "$GATE_USER"

step "programs"
install -d -m 0755 "$PREFIX/sbin" "$SHARE"
# install(1) replaces an existing symlink instead of writing through it
install -m 0755 "$HERE/purser-source" "$HERE/purser-admit" "$HERE/purser-pair" "$PREFIX/sbin/"
install -m 0755 "$HERE/purser" "$PREFIX/sbin/purser"
sed "s|^RRSYNC=.*|RRSYNC=\${RRSYNC:-$RRSYNC}|" "$HERE/purser-gate" > "$PREFIX/sbin/purser-gate.new"
chmod 0755 "$PREFIX/sbin/purser-gate.new"; mv -f "$PREFIX/sbin/purser-gate.new" "$PREFIX/sbin/purser-gate"
# a copy of this installer and its files, so "purser install" can run again from the installed system
if [ "$HERE" != "$SHARE" ]; then
  install -m 0644 "$HERE/sshd_config.in" "$HERE/source.conf.example" "$SHARE/"
  cp -r "$HERE/examples" "$SHARE/"
  install -m 0755 "$HERE/install.sh" "$HERE/purser-source" "$HERE/purser-gate" "$HERE/purser-admit" "$HERE/purser-pair" "$HERE/purser" "$SHARE/"
  install -d "$SHARE/systemd"; install -m 0644 "$HERE"/systemd/* "$SHARE/systemd/"
fi
[ -n "${PURSER_VERSION:-}" ] && printf '%s\n' "$PURSER_VERSION" > "$SHARE/version"
[ -s "$SHARE/version" ] || printf '%s\n' "$(cat "$HERE/version" 2>/dev/null || echo 1.1.0)" > "$SHARE/version"

step "configuration"
install -d -m 0755 /etc/purser /etc/purser/ssh
[ -f /etc/purser/ssh/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N '' -C purser-gate -f /etc/purser/ssh/ssh_host_ed25519_key
touch /etc/purser/ssh/authorized_keys; chmod 0644 /etc/purser/ssh/authorized_keys
if [ ! -e /etc/purser/source.conf ]; then
  sed "s|^BASE=.*|BASE=\"$BASE\"|; s|^GATE_USER=.*|GATE_USER=\"$GATE_USER\"|" "$HERE/source.conf.example" > /etc/purser/source.conf
  echo "wrote /etc/purser/source.conf (edit SOURCES)"
fi
printf 'LISTEN_ADDR=%s\nPORT=%s\nGATE_USER=%s\nPREFIX=%s\nSHARE=%s\n' "$LISTEN" "$PORT" "$GATE_USER" "$PREFIX" "$SHARE" > /etc/purser/gate.conf
install -d -m 0751 -o root -g "$GATE_USER" "$BASE" "$BASE/generation"
install -d -m 0770 -o root -g "$GATE_USER" "$BASE/ack"
install -d -m 0700 "$BASE/cache"
# the gate user must be able to walk down to BASE
p=$BASE
while p=$(dirname "$p") && [ "$p" != / ]; do
  if ! runuser -u "$GATE_USER" -- test -x "$p"; then
    if command -v setfacl >/dev/null; then setfacl -m "u:$GATE_USER:--x" "$p"; echo "$p: traverse permission for $GATE_USER (ACL)"
    else echo "warning: $GATE_USER cannot enter $p; give it execute permission" >&2; fi
  fi
done

step "units"
# Written to a new file and renamed: an existing unit may be a symlink ("systemctl link") into
# another tree, and writing through it would change that tree.
for u in "${UNITS[@]}"; do
  sed "s|@PREFIX@|$PREFIX|g; s|@TIMER_AT@|$TIMER_AT|g" "$HERE/systemd/$u" > "/etc/systemd/system/.$u.new"
  mv -f "/etc/systemd/system/.$u.new" "/etc/systemd/system/$u"
done
systemctl daemon-reload
systemctl enable --now purser-source-watch.timer purser-source-notes.path >/dev/null
if "$PREFIX/sbin/purser-source" check >/dev/null 2>&1; then
  systemctl enable --now purser-source.timer >/dev/null; echo "purser-source.timer enabled ($TIMER_AT)"
else
  echo "purser-source.timer NOT enabled yet: fix /etc/purser/source.conf ('purser-source check'), then"
  echo "    systemctl enable --now purser-source.timer"
fi

step "self-check"
SSH_ORIGINAL_COMMAND="cat /etc/shadow" runuser -u "$GATE_USER" -- "$PREFIX/sbin/purser-gate" >/dev/null 2>&1 \
  && { echo "ERROR: the gate accepted a forbidden request" >&2; exit 1; } || echo "gate refuses unknown requests"
# exit 3 = the gate cannot read BASE from the configuration (permissions of source.conf or its directory)
rc=0; SSH_ORIGINAL_COMMAND=latest runuser -u "$GATE_USER" -- "$PREFIX/sbin/purser-gate" >/dev/null 2>&1 || rc=$?
[ "$rc" != 3 ] || { echo "ERROR: $GATE_USER cannot read BASE from /etc/purser/source.conf (check its permissions)" >&2; exit 1; }
echo "gate reads its configuration"
case $(command -v ufw >/dev/null && ufw status 2>/dev/null | head -1) in
  *active*) echo "firewall: ufw active (purser-admit adds the rule)" ;;
  *) if command -v firewall-cmd >/dev/null && firewall-cmd --state >/dev/null 2>&1; then echo "firewall: firewalld (purser-admit adds the rule)"
     elif command -v nft >/dev/null && [ -n "$(nft list ruleset 2>/dev/null | head -1)" ]; then echo "firewall: nftables (purser-admit prints the rule to add)"
     else echo "firewall: none detected"; fi ;;
esac
echo "gate host key: $(ssh-keygen -lf /etc/purser/ssh/ssh_host_ed25519_key.pub)"
echo "next: sudo purser pair   (shows a QR code for the box page; boxes already paired stay admitted)"
"$PREFIX/sbin/purser-admit" render >/dev/null 2>&1 || true
