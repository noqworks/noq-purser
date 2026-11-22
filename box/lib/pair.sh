# shellcheck shell=bash
# Pairing with a server, the operation-code check for the page, and maintenance notes.
#
# The pairing token comes from "purser pair" on the server (shown as a line and as a QR code):
#   purser-pair:<base64url of "v1|host|port|user|server host key|one-time private key">
# The one-time key is accepted by the server's gate for ten minutes, once, from the local subnet,
# and can do one thing: hand over this box's id and public key. The server host key in the token
# is the only one the box will talk to (no trust on first use).

pair_decode() {   # pair_decode <token> -> fields on separate lines
  local b=${1#purser-pair:}
  [[ $b =~ ^[A-Za-z0-9_-]{40,4000}$ ]] || return 1
  b=$(printf '%s' "$b" | tr '_-' '/+')
  while [ $(( ${#b} % 4 )) -ne 0 ]; do b+="="; done
  printf '%s' "$b" | base64 -d 2>/dev/null | tr '|' '\n'
}

# v2 (binary, short QR): 0x02 | IPv4 | port | user | host key 32 | seed 32 | public key 32.
# Prints host, port, user, the host key line and the one-time private key body (OpenSSH format).
pair_decode_v2() {
  python3 -I - "${1#purser-pair:}" <<'PY' 2>/dev/null
import base64, ipaddress, os, struct, sys
t = sys.argv[1]
raw = base64.urlsafe_b64decode(t + "=" * (-len(t) % 4))
if not raw or raw[0] != 2:
    sys.exit(1)
host = str(ipaddress.IPv4Address(raw[1:5])); port = struct.unpack(">H", raw[5:7])[0]
n = raw[7]; user = raw[8:8 + n].decode("ascii"); i = 8 + n
hk, seed, pub = raw[i:i + 32], raw[i + 32:i + 64], raw[i + 64:i + 96]
if len(pub) != 32:
    sys.exit(1)
s = lambda b: struct.pack(">I", len(b)) + b
kt = b"ssh-ed25519"
blob = s(kt) + s(pub)
chk = os.urandom(4)
priv = chk + chk + s(kt) + s(pub) + s(seed + pub) + s(b"")
k = 1
while len(priv) % 8:
    priv += bytes([k]); k += 1
body = b"openssh-key-v1\0" + s(b"none") + s(b"none") + s(b"") + struct.pack(">I", 1) + s(blob) + s(priv)
print(host); print(port); print(user)
print("ssh-ed25519 " + base64.b64encode(s(kt) + s(hk)).decode())
print(base64.b64encode(body).decode())
PY
}

cmd_pair() {   # pair <token> [--later]   --later: the page asked; the firewall closes a moment after it got its answer
  local token=${1:-} later=${2:-} f=() host port user hostkey key tmp out pub
  [ "$(id -u)" = 0 ] || { say "$(msg E_ROOT)" >&2; return 1; }
  mapfile -t f < <(pair_decode "$token") || true
  if [ "${#f[@]}" -ge 6 ] && [ "${f[0]}" = v1 ]; then
    host=${f[1]} port=${f[2]} user=${f[3]} hostkey=${f[4]} key=${f[5]}
  else
    mapfile -t f < <(pair_decode_v2 "$token") || true
    [ "${#f[@]}" -eq 5 ] || { say "$(msg E_PAIR_TOKEN)" >&2; return 2; }
    host=${f[0]} port=${f[1]} user=${f[2]} hostkey=${f[3]} key=${f[4]}
  fi
  [[ $host =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && [[ $port =~ ^[0-9]{1,5}$ ]] && [[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
    && [[ $hostkey =~ ^ssh-ed25519\ [A-Za-z0-9+/]+=*$ ]] && [[ $key =~ ^[A-Za-z0-9+/=]+$ ]] || { say "$(msg E_PAIR_TOKEN)" >&2; return 2; }
  ensure_users; ensure_ssh_key
  [ -s /etc/purser/id ] || box_id_new
  tmp=$(mktemp -d "$RUN_DIR/pair.XXXXXX"); chmod 0700 "$tmp"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'; pair_firewall close '$host' '$port'" RETURN
  printf '[%s]:%s %s\n' "$host" "$port" "$hostkey" > "$tmp/known_hosts"
  { echo "-----BEGIN OPENSSH PRIVATE KEY-----"; printf '%s\n' "$key" | fold -w 70; echo "-----END OPENSSH PRIVATE KEY-----"; } > "$tmp/key"
  chmod 0600 "$tmp/key"
  pair_firewall open "$host" "$port"
  pub=$(cut -d' ' -f1,2 "$SSH_DIR/id_ed25519.pub")
  out=$(ssh -F none -i "$tmp/key" -o IdentitiesOnly=yes -o UserKnownHostsFile="$tmp/known_hosts" -o GlobalKnownHostsFile=/dev/null \
        -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=15 -p "$port" "$user@$host" \
        "pair $(cat /etc/purser/id) $pub" 2>&1) || true
  case $out in
    ok*) ;;
    *) log "pairing refused: $(safe_text "$out")"; say "$(msg E_PAIR_FAILED "$(safe_text "$out")")" >&2; return 3 ;;
  esac
  conf_set SERVER "$host"; conf_set SERVER_PORT "$port"; conf_set SERVER_USER "$user"
  # the server names its sources (type:directory inside each generation)
  local kinds; kinds=$(printf '%s' "${out#ok}" | tr -cd 'a-z0-9:._ -' | sed 's/^ *//')
  [ -n "$kinds" ] && conf_set KINDS "$kinds"
  printf '[%s]:%s %s\n' "$host" "$port" "$hostkey" > "$SSH_DIR/known_hosts"; chmod 0644 "$SSH_DIR/known_hosts"
  load_config
  setup_mark hostkey "done"; setup_mark paired "$(now)"
  setup_finish_if_complete
  notify paired default N_PAIRED "$(cat /etc/purser/id)"
  if [ "$later" = --later ] && systemd_up && systemd-run --quiet --no-block --on-active=5 --unit="purser-apply-$$" \
       "$PURSER_LIB/../../sbin/purser" apply-config >/dev/null 2>&1; then
    :   # the page gets its answer now; the firewall is applied in five seconds
  else
    apply_config || true
  fi
  led_update
  say "$(msg I_PAIRED "$host")"
}

# While pairing, the box may talk to the server named in the token (the switch is on anyway).
pair_firewall() {   # pair_firewall open|close <host> <port>
  nft list chain inet "$NFT_TABLE" maint_out >/dev/null 2>&1 || return 0
  if [ "$1" = open ]; then
    nft add rule inet "$NFT_TABLE" maint_out ip daddr "$2" tcp dport "$3" accept comment '"pairing"' 2>/dev/null || true
  else
    local h
    for h in $(nft -a list chain inet "$NFT_TABLE" maint_out 2>/dev/null | sed -n 's/.*comment "pairing".*# handle \([0-9]*\)/\1/p'); do
      nft delete rule inet "$NFT_TABLE" maint_out handle "$h" 2>/dev/null || true
    done
  fi
}

# NOQ-PURSER-<4>: no 0/O, no 1/I/L; at least one letter and one digit.
box_id_new() {
  local a=ABCDEFGHJKMNPQRSTUVWXYZ d=23456789 all id
  all=$a$d
  while :; do
    id=""
    for b in $(od -An -tu1 -N16 /dev/urandom); do
      [ "$b" -lt 248 ] || continue
      id+=${all:$(( b % ${#all} )):1}; [ ${#id} -eq 4 ] && break
    done
    [[ $id =~ [A-Z] ]] && [[ $id =~ [0-9] ]] && break
  done
  install -d -m 0755 /etc/purser; printf '%s\n' "$id" > /etc/purser/id
}

# The box answers to <id>.local (avahi, only while the switch is on): the host name is the id.
box_hostname() {
  local h; h=$(tr '[:upper:]' '[:lower:]' < /etc/purser/id 2>/dev/null)
  [[ $h =~ ^[a-z0-9]{4}$ ]] || return 0
  [ "$(hostname)" = "$h" ] && return 0
  if command -v hostnamectl >/dev/null 2>&1 && systemd_up; then hostnamectl set-hostname "$h" 2>/dev/null || true
  else echo "$h" > /etc/hostname; hostname "$h" 2>/dev/null || true; fi
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $h/" /etc/hosts 2>/dev/null || true
}

# The page asks the core: the same counter and lock as the serial console.
#   0 right, 1 wrong, 2 typo (check digit), 3 locked, 4 no code set
cmd_check_code() {
  local c rc=0
  code_is_set || return 4
  read -r c || c=""
  code_check "$c" || rc=$?
  return "$rc"
}

cmd_notify_maint() {   # notify-maint on | off | still-on <hours>
  case ${1:-} in
    on) notify maint_on high N_MAINT_ON ;;
    off) notify maint_off default N_MAINT_OFF ;;
    still-on) notify maint_still_on high N_MAINT_STILL_ON "${2:-2}" ;;
  esac
  led_update
}
