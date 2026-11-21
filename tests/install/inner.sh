#!/bin/bash
# Inside a fresh systemd container: install the server side, publish a generation, admit a box
# key, use the gate as the box would, re-install, watch alert, uninstall.
set -uo pipefail
P=0 F=0
ok() { local d=$1; shift; if "$@" >/dev/null 2>&1; then P=$((P + 1)); echo "  ok    $d"; else F=$((F + 1)); echo "  FAIL  $d"; fi; }
. /etc/os-release; echo "== $PRETTY_NAME"
ID_=2026-03-01T03-10Z
inst() { bash /src/source/install.sh --listen 127.0.0.1 --port 2222 --base /srv/purser "$@"; }
ok "install.sh runs (installs its own dependencies)" inst
ok "rsync installed by the installer" command -v rsync
ok "sshd installed by the installer" test -x /usr/sbin/sshd
ok "gate user exists without a password" sh -c "getent shadow purser | cut -d: -f2 | grep -qx '\*'"
mkdir -p /srv/data/dumps && head -c 4096 /dev/urandom > /srv/data/dumps/dump-1.sql.gz
cat > /etc/purser/source.conf <<'C'
BASE="/srv/purser"
GATE_USER="purser"
SOURCES=("dir:/srv/data/dumps")
FREEZE="auto"
ALERT_CMD=(sh -c 'echo "$1 $2" >> /run/alerts' _)
ACK_ALERT_H="1"
C
ok "purser-source check" /usr/local/sbin/purser-source check
ok "a generation is published" env PURSER_SOURCE_ID=$ID_ /usr/local/sbin/purser-source run
ok "LATEST names it" grep -qx "$ID_" /srv/purser/generation/LATEST
ok "its list starts with the version line" sh -c "head -1 /srv/purser/generation/$ID_.list | grep -qx '# purser-list 1'"
ssh-keygen -q -t ed25519 -N '' -C box -f /root/box
ok "purser-admit" /usr/local/sbin/purser-admit 127.0.0.1 "$(cat /root/box.pub)"
for _ in 1 2 3 4 5; do systemctl -q is-active purser-sshd && break; sleep 1; done
ok "gate sshd active" systemctl -q is-active purser-sshd
ssh-keyscan -p 2222 -t ed25519 127.0.0.1 2>/dev/null > /root/kh
S=(ssh -i /root/box -p 2222 -o UserKnownHostsFile=/root/kh -o StrictHostKeyChecking=yes -o BatchMode=yes purser@127.0.0.1)
ok "gate: latest" sh -c "$(printf '%q ' "${S[@]}") latest | grep -qx $ID_"
ok "gate: rsync of the list (read-only)" rsync -e "ssh -i /root/box -p 2222 -o UserKnownHostsFile=/root/kh -o BatchMode=yes" "purser@127.0.0.1:$ID_.list" /root/
ok "gate: rsync upload refused" sh -c "! rsync -e 'ssh -i /root/box -p 2222 -o UserKnownHostsFile=/root/kh -o BatchMode=yes' /etc/hostname purser@127.0.0.1:x"
ok "gate: ack" "${S[@]}" ack "$ID_" tamam
ok "ack file written" grep -q '^tamam ' "/srv/purser/ack/$ID_"
ok "gate: bad ack refused" sh -c "! $(printf '%q ' "${S[@]}") ack ../../etc/passwd"
ok "gate: other commands refused" sh -c "! $(printf '%q ' "${S[@]}") cat /etc/shadow"
ok "gate: no interactive shell" sh -c "! $(printf '%q ' "${S[@]}") </dev/null"
ok "install.sh is re-runnable" inst
ok "admitted key kept by the re-run" grep -q 'command=' /etc/purser/ssh/authorized_keys
ok "gate still answers after the re-run" sh -c "$(printf '%q ' "${S[@]}") latest | grep -qx $ID_"
touch -d '-3 hours' "/srv/purser/ack/$ID_"; rm -f /run/alerts
ok "watch: no-ack alert through ALERT_CMD" sh -c "/usr/local/sbin/purser-source watch && grep -q '^no_ack ' /run/alerts"
ok "timers enabled" systemctl -q is-enabled purser-source.timer purser-source-watch.timer
ok "uninstall" bash /src/source/install.sh --uninstall
ok "programs removed" sh -c "! ls /usr/local/sbin/purser-* 2>/dev/null | grep -q ."
ok "units removed" sh -c "! ls /etc/systemd/system/purser-* 2>/dev/null | grep -q ."
ok "configuration moved aside, not deleted" sh -c "ls -d /etc/purser.removed-* && test ! -e /etc/purser"
ok "data under BASE kept" test -s "/srv/purser/generation/$ID_.list"
echo "RESULT $ID $VERSION_ID $P $F"
[ "$F" -eq 0 ]
