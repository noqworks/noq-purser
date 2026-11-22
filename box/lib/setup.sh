# shellcheck shell=bash
# First boot, the setup wizard on the serial console, disk preparation (new or adopted) and
# rendering of system configuration (nftables, chrony, DNS, timer, maintenance SSH).
#
# Unattended first boot (setup.conf in the image): configuration, keys, gate host key (only
# when it matches SERVER_HOSTKEY_FP), notification channel and an adopted disk. A NEW disk is
# always prepared at the serial console, because its recovery passphrase is shown exactly once.

SETUP_CONF=${SETUP_CONF:-/etc/purser/setup.conf}
TEMPLATES=${TEMPLATES:-$PURSER_LIB/templates}

conf_set() {   # conf_set <key> <value>: replace or append a key in purser.conf (values are quoted)
  local k=$1 v=$2 t
  [[ $k =~ ^[A-Z_][A-Z0-9_]*$ ]] || return 1
  v=${v//\"/}
  t=$(mktemp "$CONF.XXXXXX")
  { [ -r "$CONF" ] && grep -v "^$k=" "$CONF" || true; printf '%s="%s"\n' "$k" "$v"; } > "$t"
  chmod 0644 "$t"; mv -f "$t" "$CONF"
  printf -v "$k" '%s' "$v"
}
setup_mark() { install -d -m 0700 "$STATE"; kv_set "$ST_SETUP" "$1" "$2"; }
setup_get() { kv_get "$ST_SETUP" "$1"; }

ensure_users() {
  local u
  for u in "$RSYNC_USER" "$VERIFY_USER"; do
    id "$u" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$u"
  done
}

# After moving an SD card: user ids may differ, chown by name.
fix_ownership() {
  install -d -m 0755 /etc/purser "$SSH_DIR"; install -d -m 0700 "$SECRETS" "$STATE"
  [ -e "$SSH_DIR/id_ed25519" ] && chown "$RSYNC_USER:$RSYNC_USER" "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ed25519.pub" && chmod 0600 "$SSH_DIR/id_ed25519"
  [ -e "$SSH_DIR/known_hosts" ] && chown root:root "$SSH_DIR/known_hosts" && chmod 0644 "$SSH_DIR/known_hosts"
  chown -R root:root "$SECRETS" "$STATE"
  [ -e "$LUKS_KEY" ] && chmod 0400 "$LUKS_KEY"
  [ -e "$NOTIFY" ] && chmod 0600 "$NOTIFY"
  return 0
}

# setup.conf, written onto the card by "purser setup" on the user's computer, read once at first
# boot and then shredded. It holds the language, the network and the box id; the secrets the user
# wrote on paper arrive as one-time files next to it (recovery passphrase, operation code) and are
# consumed by the first boot. A disk is erased only when "purser setup" left the one-time marker
# PREPARE_DISK=<box id> after the user typed the id to confirm.
apply_setup_conf() {
  [ -r "$SETUP_CONF" ] || return 0
  local k v
  # shellcheck source=/dev/null
  ( . "$SETUP_CONF"; set | grep -E '^(LANG_UI|NIGHT_AT|POLL_UNTIL|POLL_EVERY|MAX_MIN|LONG_DOW|PRUNE_DOW|DNS_SERVERS|NTP_SERVERS|NTP_POOL|BOARD_LED|SERIAL_TTY|NET_ADDRESS|NET_GATEWAY|LIGHT_KIND|LIGHT_BRIGHTNESS)=' ) \
    > "$RUN_DIR/setup.vars" || true
  [ -r "$CONF" ] || install -m 0644 "$PURSER_LIB/purser.conf.example" "$CONF"
  while IFS='=' read -r k v; do
    v=${v#\'}; v=${v%\'}
    conf_set "$k" "$v"
  done < "$RUN_DIR/setup.vars"
  rm -f "$RUN_DIR/setup.vars"
  v=$(sed -n 's/^TZ=//p' "$SETUP_CONF" | tr -d "\"'" | tail -1)
  [ -n "$v" ] && [ -e "/usr/share/zoneinfo/$v" ] && ln -sf "/usr/share/zoneinfo/$v" /etc/localtime && echo "$v" > /etc/timezone
  v=$(sed -n 's/^BOX_ID=//p' "$SETUP_CONF" | tr -d "\"'" | tail -1)
  if [[ $v =~ ^[A-HJ-NP-Z2-9]{4}$ ]]; then install -d -m 0755 /etc/purser; echo "$v" > /etc/purser/id; fi
  v=$(sed -n 's/^PREPARE_DISK=//p' "$SETUP_CONF" | tr -d "\"'" | tail -1)
  [ -n "$v" ] && [ "$v" = "$(cat /etc/purser/id 2>/dev/null)" ] && setup_mark prepare_disk "$v"
  shred -u "$SETUP_CONF" 2>/dev/null || rm -f "$SETUP_CONF"
  load_config
  net_apply
}

# First boot, no console: erase the one USB disk and make it a Purser disk. Only with the marker
# from "purser setup" (the user typed the box id there); with no disk or more than one it stops.
# The recovery passphrase was generated and shown on the computer; it arrives as a one-time file.
disk_prepare_unattended() {
  local disks dev n cipher=() rec=$SECRETS/recovery.once
  disk_usb_wait || { echo no_disk > "$RUN_DIR/prepare.reason"; return 1; }
  disks=$(usb_disks); n=$(grep -c . <<< "$disks")
  [ "$n" -eq 1 ] || { echo "disks_$n" > "$RUN_DIR/prepare.reason"; return 1; }
  [ -s "$rec" ] || { echo no_recovery > "$RUN_DIR/prepare.reason"; return 1; }
  dev=$(awk '{ print $1 }' <<< "$disks")
  log "first boot: preparing $dev (marker from purser setup)"
  if cryptsetup benchmark -c aes-xts-plain64 -s 512 2>/dev/null | awk '/aes-xts/ { exit !($5 + 0 >= 150) }'; then
    cipher=(--cipher aes-xts-plain64 --key-size 512)
  else
    cipher=(--cipher xchacha12,aes-adiantum-plain64 --key-size 256)
  fi
  install -d -m 0700 "$SECRETS"
  ( umask 077; head -c 64 /dev/urandom > "$LUKS_KEY" ); chmod 0400 "$LUKS_KEY"
  wipefs -a "$dev" >/dev/null 2>&1 || true
  cryptsetup luksFormat --type luks2 --batch-mode "${cipher[@]}" --key-file "$LUKS_KEY" "$dev" || { echo luks > "$RUN_DIR/prepare.reason"; return 1; }
  cryptsetup luksAddKey --key-file "$LUKS_KEY" "$dev" "$rec" || { echo recovery > "$RUN_DIR/prepare.reason"; return 1; }
  shred -u "$rec" 2>/dev/null || rm -f "$rec"
  cryptsetup luksHeaderBackup "$dev" --header-backup-file "$SECRETS/luks-baslik.img"; chmod 0400 "$SECRETS/luks-baslik.img"
  cryptsetup open --key-file "$LUKS_KEY" "$dev" "$MAP"
  mkfs.btrfs -q -f -L purser "$MAPPER_DIR/$MAP"
  conf_set LUKS_UUID "$(cryptsetup luksUUID "$dev")"
  install -d -m 0755 "$MNT"
  mount -o noatime "$MAPPER_DIR/$MAP" "$MNT"
  install -d -m 0755 "$GEN_DIR" "$AUDIT"
  install -d -m 0700 "$AUDIT/liste" "$AUDIT/meta" "$AUDIT/supheli" "$AUDIT/temiz" "$AUDIT/pin"
  disk_close || true
  setup_mark disk new; setup_mark prepare_disk ""
  log "first boot: disk prepared"
}

# The operation code was generated and shown on the computer; the card carries it once.
code_from_card() {
  local f=$SECRETS/code.once c
  [ -s "$f" ] || return 0
  c=$(tr -cd '0-9' < "$f")
  shred -u "$f" 2>/dev/null || rm -f "$f"
  if [[ $c =~ ^[0-9]{12}$ ]] && damm_valid "$c"; then code_store "$c"; log "operation code set from the card"; fi
}

# Wired network. NET_ADDRESS empty: DHCP, as the image comes. NET_ADDRESS="192.0.2.15/24" and
# NET_GATEWAY="192.0.2.1": a fixed address on every Ethernet interface (the server admits the
# box by address). Written for netplan (Armbian), else systemd-networkd, else NetworkManager.
net_apply() {
  local a=${NET_ADDRESS:-} g=${NET_GATEWAY:-} root=${APPLY_ROOT:-} d f
  [ -n "$a" ] || return 0
  [[ $a =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]] || { log "NET_ADDRESS is not an IPv4 address with prefix: $a"; return 1; }
  [ -z "$g" ] || [[ $g =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { log "NET_GATEWAY is not an IPv4 address: $g"; return 1; }
  d=$(printf '%s' "$DNS_SERVERS" | sed 's/ \+/, /g')
  if [ -d "$root/etc/netplan" ]; then
    for f in "$root"/etc/netplan/*.yaml; do
      [ -e "$f" ] && [ "${f##*/}" != 20-purser.yaml ] && mv -f "$f" "$f.purser-off"
    done
    ( umask 077
      { printf 'network:\n  version: 2\n  renderer: networkd\n  ethernets:\n    purser-wired:\n      match:\n        name: "e*"\n'
        printf '      dhcp4: false\n      dhcp6: false\n      addresses: [%s]\n' "$a"
        [ -n "$g" ] && printf '      routes:\n        - to: default\n          via: %s\n' "$g"
        printf '      nameservers:\n        addresses: [%s]\n' "$d"; } > "$root/etc/netplan/20-purser.yaml" )
    [ -z "$root" ] && command -v netplan >/dev/null 2>&1 && { netplan apply || log "netplan apply failed"; }
  elif [ -d "$root/etc/systemd/network" ] && { [ -n "$root" ] || systemctl -q is-enabled systemd-networkd 2>/dev/null; }; then
    { printf '[Match]\nName=e*\n\n[Network]\nAddress=%s\n' "$a"
      [ -n "$g" ] && printf 'Gateway=%s\n' "$g"
      for f in $DNS_SERVERS; do printf 'DNS=%s\n' "$f"; done; } > "$root/etc/systemd/network/20-purser.network"
    [ -z "$root" ] && { networkctl reload 2>/dev/null || systemctl restart systemd-networkd; }
  elif [ -z "$root" ] && command -v nmcli >/dev/null 2>&1; then
    for f in $(nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /ethernet/ { print $1 }'); do
      nmcli con mod "$f" ipv4.method manual ipv4.addresses "$a" ${g:+ipv4.gateway "$g"} && nmcli con up "$f" >/dev/null || true
    done
  else
    log "no netplan, systemd-networkd or NetworkManager: set the address $a by hand"; return 1
  fi
  log "network: fixed address $a${g:+ via $g}"
}

ensure_ssh_key() {
  local k=$SSH_DIR/id_ed25519
  install -d -m 0755 "$SSH_DIR"
  [ -f "$k" ] || ssh-keygen -q -t ed25519 -N '' -C "purser@$(hostname)" -f "$k"
  chown "$RSYNC_USER:$RSYNC_USER" "$k" "$k.pub"; chmod 0600 "$k"
}

server_fingerprint() {   # prints the ed25519 fingerprint of the server gate, stores the key in $1
  ssh-keyscan -T 5 -p "$SERVER_PORT" -t ed25519 "$SERVER" 2>/dev/null > "$1" || true
  [ -s "$1" ] && ssh-keygen -lf "$1" | awk '{ print $2 }'
}

# Unattended: accept the gate key only if it matches SERVER_HOSTKEY_FP from setup.conf.
ensure_known_hosts() {
  local fp want t=$SSH_DIR/known_hosts.new
  [ -s "$SSH_DIR/known_hosts" ] && return 0
  want=$(setup_get hostkey_fp)
  [ -n "$want" ] && [ -n "$SERVER" ] || return 1
  fp=$(server_fingerprint "$t" || true)
  if [ -n "$fp" ] && [ "$fp" = "$want" ]; then mv -f "$t" "$SSH_DIR/known_hosts"; chmod 0644 "$SSH_DIR/known_hosts"; return 0; fi
  rm -f "$t"; return 1
}

render() {   # render <template> <output>: replaces @KEY@ with config values
  local in=$TEMPLATES/$1 out=$2 line k
  local s; s=$(cat "$in")
  for k in SERVER SERVER_PORT CLOCK_JUMP_MAX NTP_POOL; do s=${s//@$k@/${!k}}; done
  if [ -n "$SERVER" ]; then s=${s//@SERVER_RULE@/ip daddr $SERVER tcp dport $SERVER_PORT accept}
  else s=${s//@SERVER_RULE@/# not paired yet: no server}; fi
  if [ -n "$DNS_SERVERS" ]; then
    s=${s//@DNS_RULE@/ip daddr \{ $(printf '%s' "$DNS_SERVERS" | sed 's/ \+/, /g') \} meta l4proto \{ tcp, udp \} th dport 53 accept}
  else s=${s//@DNS_RULE@/# no DNS: the box talks to addresses only}; fi
  # time: the local network's router ("gateway"), or the addresses given; a public pool only if asked for
  line=""; for k in $NTP_SERVERS; do
    [ "$k" = gateway ] && k=$(ip -4 route show default 2>/dev/null | awk '{ print $3; exit }')
    [ -n "$k" ] && line+="server $k iburst"$'\n'
  done
  [ -n "$NTP_POOL" ] && line+="pool $NTP_POOL iburst maxsources 3"$'\n'
  s=${s//@NTP_SERVER_LINES@/$line}
  printf '%s\n' "$s" > "$out.new"; mv -f "$out.new" "$out"
}

apply_config() {
  if [ -n "$SERVER" ] && ! [[ $SERVER =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then say "$(msg E_SERVER_IP)" >&2; return 1; fi
  local root=${APPLY_ROOT:-}
  render nftables.conf.in "$root/etc/nftables.conf"
  render chrony.conf.in "$root/etc/chrony/chrony.conf"
  install -d "$root/etc/systemd/system/purser.timer.d"
  printf '[Timer]\nOnCalendar=\nOnCalendar=*-*-* %s:00\n' "$NIGHT_AT" > "$root/etc/systemd/system/purser.timer.d/time.conf"
  install -d "$root/etc/systemd/system/serial-getty@$SERIAL_TTY.service.d"
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -n -l %s/purser-console --keep-baud 115200,57600,38400,9600 %%I $TERM\n' \
    "${CONSOLE_DIR:-/usr/local/sbin}" > "$root/etc/systemd/system/serial-getty@$SERIAL_TTY.service.d/purser.conf"
  [ -n "$root" ] && return 0
  if command -v nft >/dev/null 2>&1; then
    nft -c -f /etc/nftables.conf && nft -f /etc/nftables.conf
    systemctl enable nftables.service >/dev/null 2>&1 || true
    # reloading the rules empties the maintenance chains: while the switch is on, open them again
    [ -e "$RUN_DIR/maint" ] && [ -x /usr/local/sbin/purser-maint ] && /usr/local/sbin/purser-maint reopen || true
  fi
  dns_apply
  # SSH (and the page) run only while the maintenance switch is on; purser-maint starts and stops them.
  systemctl unmask ssh.service >/dev/null 2>&1 || true
  systemctl disable ssh.service ssh.socket >/dev/null 2>&1 || true
  [ -e "$RUN_DIR/maint" ] || systemctl stop ssh.service ssh.socket >/dev/null 2>&1 || true
  systemctl daemon-reload
  systemctl restart chrony 2>/dev/null || true
  systemctl try-restart purser.timer 2>/dev/null || true
}

# DNS from the configured resolvers, never from the local network (the server may be its DNS).
dns_apply() {
  local s c
  if command -v nmcli >/dev/null 2>&1 && systemctl -q is-active NetworkManager 2>/dev/null; then
    for c in $(nmcli -t -f NAME,TYPE con show | awk -F: '$2 ~ /ethernet/ { print $1 }'); do
      nmcli con mod "$c" ipv4.ignore-auto-dns yes ipv4.dns "$DNS_SERVERS" && nmcli con up "$c" >/dev/null || true
    done
  elif systemctl -q is-active systemd-resolved 2>/dev/null; then
    install -d /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=%s\nDomains=~.\nFallbackDNS=\n' "$DNS_SERVERS" > /etc/systemd/resolved.conf.d/purser.conf
    install -d /etc/systemd/network/10-purser.network.d 2>/dev/null || true
    systemctl restart systemd-resolved
  else
    rm -f /etc/resolv.conf
    for s in $DNS_SERVERS; do echo "nameserver $s"; done > /etc/resolv.conf
  fi
}

# --- disk: new (LUKS2 + btrfs) or adopted (key moved from the old card) ---

disk_usb_wait() {   # wait until at least one USB disk shows up
  local i
  for (( i = 0; i < DISK_WAIT; i++ )); do [ -n "$(usb_disks)" ] && return 0; sleep 1; done
  return 1
}

disk_new() {   # interactive; erases the chosen disk
  local disks dev n ok cipher=() rec back
  [ -z "$LUKS_UUID" ] || { say "$(msg E_DISK_CONFIGURED "$LUKS_UUID")" >&2; return 1; }
  disk_usb_wait || { say "$(msg E_NO_USB_DISK)" >&2; return 1; }
  disks=$(usb_disks); n=$(wc -l <<< "$disks")
  say "$disks"
  if [ "$n" -ne 1 ]; then say "$(msg E_ONE_DISK)" >&2; return 1; fi
  dev=$(awk '{ print $1 }' <<< "$disks")
  if cryptsetup isLuks "$dev" 2>/dev/null || [ -n "$(lsblk -nro FSTYPE "$dev" | tr -d '\n')" ]; then say "$(msg W_DISK_HAS_DATA "$dev")"; fi
  printf '%s' "$(msg P_ERASE "$dev")" >&2; read -r ok || ok=""
  [ "$ok" = ERASE ] || { say "$(msg E_ABORTED)" >&2; return 1; }
  if cryptsetup benchmark -c aes-xts-plain64 -s 512 2>/dev/null | awk '/aes-xts/ { exit !($5 + 0 >= 150) }'; then
    cipher=(--cipher aes-xts-plain64 --key-size 512)
  else
    cipher=(--cipher xchacha12,aes-adiantum-plain64 --key-size 256)
  fi
  say "$(msg I_CIPHER "${cipher[1]}")"
  install -d -m 0700 "$SECRETS"
  ( umask 077; head -c 64 /dev/urandom > "$LUKS_KEY" ); chmod 0400 "$LUKS_KEY"
  wipefs -a "$dev" >/dev/null
  cryptsetup luksFormat --type luks2 --batch-mode "${cipher[@]}" --key-file "$LUKS_KEY" "$dev"
  rec=$(head -c 4096 /dev/urandom | tr -dc 'ACDEFHJKLMNPRTUVWXY34679' | cut -c1-32 | sed 's/.\{4\}/&-/g; s/-$//')
  ( umask 077; printf '%s' "$rec" > "$RUN_DIR/recovery" )
  cryptsetup luksAddKey --key-file "$LUKS_KEY" "$dev" "$RUN_DIR/recovery"
  shred -u "$RUN_DIR/recovery" 2>/dev/null || rm -f "$RUN_DIR/recovery"
  say ""; say "$(msg C_RECOVERY)"; say ""; say "      $rec"; say ""
  printf '%s' "$(msg P_RECOVERY_BACK)" >&2; read -r back || back=""
  if [ "$back" != "${rec: -4}" ]; then say "$(msg E_RECOVERY_BACK)" >&2; fi
  unset rec; [ -t 1 ] && clear 2>/dev/null || true
  cryptsetup luksHeaderBackup "$dev" --header-backup-file "$SECRETS/luks-baslik.img"
  chmod 0400 "$SECRETS/luks-baslik.img"
  cryptsetup open --key-file "$LUKS_KEY" "$dev" "$MAP"
  mkfs.btrfs -q -L purser "$MAPPER_DIR/$MAP"
  conf_set LUKS_UUID "$(cryptsetup luksUUID "$dev")"
  install -d -m 0755 "$MNT"; mount -o noatime "$MAPPER_DIR/$MAP" "$MNT"
  install -d -m 0755 "$GEN_DIR" "$AUDIT"
  install -d -m 0700 "$AUDIT/liste" "$AUDIT/meta" "$AUDIT/supheli" "$AUDIT/temiz" "$AUDIT/pin"
  disk_close || true
  setup_mark disk new
  say "$(msg I_DISK_READY "$SECRETS/luks-baslik.img")"
}

disk_adopt() {   # uses the key file moved from the old card
  local d uuid
  [ -r "$LUKS_KEY" ] || { say "$(msg E_NO_KEY "$LUKS_KEY")" >&2; return 1; }
  if [ -z "$LUKS_UUID" ]; then
    disk_usb_wait || { say "$(msg E_NO_USB_DISK)" >&2; return 1; }
    for d in $(usb_disks | awk '{ print $1 }'); do
      cryptsetup isLuks "$d" 2>/dev/null || continue
      if cryptsetup open --test-passphrase --key-file "$LUKS_KEY" "$d" 2>/dev/null; then uuid=$(cryptsetup luksUUID "$d"); break; fi
    done
    [ -n "${uuid:-}" ] || { say "$(msg E_KEY_NO_DISK)" >&2; return 1; }
    conf_set LUKS_UUID "$uuid"
  fi
  disk_open || return 1
  if [ ! -d "$GEN_DIR" ] || [ ! -d "$AUDIT/liste" ]; then disk_close || true; say "$(msg E_NOT_PURSER_DISK)" >&2; return 1; fi
  [ -s "$ST_LAST_PUBLISHED" ] || state_rebuild
  suspect_state_sync
  say "$(msg I_ADOPTED "$(generations 'gen-*' | wc -l)" "$(generations 'uzun-*' | wc -l)" "$(cat "$ST_LAST_PUBLISHED" 2>/dev/null || echo -)")"
  disk_close || true
  setup_mark disk adopted
}

# SD state lost but the disk is fine: rebuild the few pointers from the audit area.
state_rebuild() {
  local last first sound id
  last=$(generations 'gen-*' | sed 's/^gen-//' | while read -r id; do [ -s "$AUDIT/meta/$id" ] && echo "$id"; done | tail -1)
  [ -n "$last" ] || return 0
  echo "$last" > "$ST_LAST_PUBLISHED"
  cp "$AUDIT/liste/$last.list" "$ST_LAST_LIST" 2>/dev/null || true
  first=$(uncleared_suspects | LC_ALL=C sort | head -1)
  if [ -n "$first" ]; then
    echo "$first" > "$ST_SUSPECT_FLAG"
    sound=$(generations 'gen-*' | sed 's/^gen-//' | awk -v f="$first" '$0 < f' | tail -1)
  else sound=$last; fi
  [ -n "$sound" ] && echo "$sound" > "$ST_LAST_SOUND"
  log "state rebuilt from disk: last published $last, last sound ${sound:-none}"
}

# "purser setup" on the user's computer writes a small FAT partition (label PURSERSET) after
# flashing: setup.conf, the one-time secrets (recovery passphrase, operation code) and optional
# maintenance SSH keys. The first boot takes them over and then overwrites the whole partition.
setup_partition() {
  local dev m=$RUN_DIR/setup-part f
  dev=$(blkid -L PURSERSET 2>/dev/null || true)
  [ -n "$dev" ] && [ -b "$dev" ] || return 0
  install -d -m 0700 "$m"
  mount -o ro "$dev" "$m" 2>/dev/null || return 0
  install -d -m 0700 "$SECRETS" /etc/purser
  [ -s "$m/setup.conf" ] && install -m 0600 "$m/setup.conf" "$SETUP_CONF"
  for f in recovery.once code.once; do [ -s "$m/$f" ] && install -m 0400 "$m/$f" "$SECRETS/$f"; done
  if [ -s "$m/ssh-keys" ]; then
    install -d -m 0700 /root/.ssh
    grep -E '^(ssh-ed25519|sk-ssh-ed25519@openssh.com|ecdsa-sha2-nistp256) [A-Za-z0-9+/=]+( [^ ]*)?$' "$m/ssh-keys" > /root/.ssh/authorized_keys || true
    chmod 0600 /root/.ssh/authorized_keys
  fi
  umount "$m"
  # the secrets were on a FAT file system: nothing of it is kept
  f=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
  head -c "$f" /dev/zero > "$dev" 2>/dev/null || true
  sync
  log "first boot: settings taken from the setup partition; the partition was overwritten"
}

# --- first boot (unattended part) ---
cmd_firstboot() {
  [ "$(setup_get state)" = "done" ] && return 0
  setup_partition
  ensure_users; fix_ownership
  apply_setup_conf
  # No card settings is fine: defaults (DHCP, English) and the box waits to be paired.
  [ -r "$CONF" ] || install -m 0644 "$PURSER_LIB/purser.conf.example" "$CONF"
  load_config
  [ -n "$SERVER" ] && apply_config || true
  ensure_ssh_key
  ensure_known_hosts && setup_mark hostkey "done"
  [ -s /etc/purser/id ] || box_id_new
  box_hostname
  code_is_set || code_from_card
  if [ -n "$(setup_get prepare_disk)" ] && [ -z "$LUKS_UUID" ]; then
    light_set checking
    if disk_prepare_unattended; then notify disk_prepared default N_DISK_PREPARED
    else notify disk_prepare_failed urgent N_DISK_PREPARE_FAILED "$(cat "$RUN_DIR/prepare.reason" 2>/dev/null || echo -)"; light_set fault; fi
    load_config
  elif [ -r "$LUKS_KEY" ]; then disk_adopt >/dev/null || true; fi
  local fails=0
  install -d -m 0755 "$RUN_DIR"; cmd_selftest > "$RUN_DIR/selftest.txt" 2>&1 || fails=$?
  log "first boot self-test: $fails failures"
  [ "$fails" -eq 0 ] || notify selftest_failed high N_SELFTEST_FAILED "$fails"
  setup_finish_if_complete
  if [ "$(setup_get state)" = "done" ]; then
    notify box_ready default N_BOX_READY "$PURSER_VERSION" "$(cat "$ST_LAST_PUBLISHED" 2>/dev/null || echo -)"
    code_is_set || { notify code_missing default N_CODE_MISSING; due_once code_missing $(( 7 * 86400 )) || true; }
  else
    notify setup_waiting default N_SETUP_WAITING "$(setup_missing | tr '\n' ' ')"
  fi
  led_update
}

# What the nightly job needs. The operation code is not on this list: it only guards the
# commands at the box, and a card moved from an older release has none yet. Without it the
# nightly job runs and a weekly reminder goes out until "setup-code" is run at the console.
setup_missing() {
  [ -n "$SERVER" ] && [ -s "$SSH_DIR/known_hosts" ] || echo paired
  [ -n "$LUKS_UUID" ] || echo disk
  return 0
}

setup_finish_if_complete() {
  [ -z "$(setup_missing)" ] || return 0
  setup_mark state "done"
  if systemd_up; then
    systemctl enable --now purser-tick.timer >/dev/null 2>&1 || true
    # a new disk gets its first fill first; an adopted disk continues nightly at once
    if [ "$(setup_get disk)" != new ] || [ "$(setup_get first_fill)" = "done" ]; then
      systemctl enable --now purser.timer >/dev/null 2>&1 || true
    fi
  fi
}

box_ip() { hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1; }

# --- the wizard on the serial console ---
ask() {   # ask <prompt key> <default> -> answer
  local a
  printf '%s [%s]: ' "$(msg "$1")" "$2" >&2; read -r a || a=""
  printf '%s' "${a:-$2}"
}
yes_no() { local a; printf '%s (y/n): ' "$(msg "$1")" >&2; read -r a || a=""; [[ $a =~ ^[yYeE] ]]; }

cmd_setup() {
  if [ "$(setup_get state)" = "done" ]; then code_require || return 1; fi
  ensure_users; fix_ownership
  say "$(msg W_TITLE)"
  if [ ! -r "$CONF" ]; then
    install -m 0644 "$PURSER_LIB/purser.conf.example" "$CONF"; load_config
  fi
  conf_set LANG_UI "$(ask W_LANG "$LANG_UI")"; load_messages
  conf_set SERVER "$(ask W_SERVER "${SERVER:-192.0.2.10}")"
  conf_set SERVER_PORT "$(ask W_PORT "$SERVER_PORT")"
  conf_set KINDS "$(ask W_KINDS "${KINDS:-pgbackrest:pgbackrest}")"
  conf_set NIGHT_AT "$(ask W_NIGHT "$NIGHT_AT")"
  conf_set POLL_UNTIL "$(ask W_POLL_UNTIL "$POLL_UNTIL")"
  load_config
  apply_config || true
  ensure_ssh_key
  say "$(msg W_PUBKEY)"; say ""
  say "  purser-admit add $(cat /etc/purser/id 2>/dev/null) $(box_ip) '$(cut -d' ' -f1,2 "$SSH_DIR/id_ed25519.pub")'"
  say ""
  printf '%s' "$(msg P_ENTER)" >&2; read -r _ || true
  local fp t=$SSH_DIR/known_hosts.new
  fp=$(server_fingerprint "$t" || true)
  if [ -z "$fp" ]; then say "$(msg E_GATE_UNREACHABLE "$SERVER" "$SERVER_PORT")"
  else
    say "$(msg W_FINGERPRINT "$fp")"
    if yes_no W_FINGERPRINT_OK; then mv -f "$t" "$SSH_DIR/known_hosts"; chmod 0644 "$SSH_DIR/known_hosts"; setup_mark hostkey "done"
      if remote latest >/dev/null 2>&1; then say "$(msg I_GATE_OK)"; else say "$(msg E_GATE_LATEST)"; fi
    else rm -f "$t"; fi
  fi
  notify test default N_TEST
  if [ -z "$LUKS_UUID" ]; then
    if [ -r "$LUKS_KEY" ]; then disk_adopt || true
    elif yes_no W_DISK_NEW; then disk_new || true; fi
  fi
  code_is_set || code_new_interactive || true
  cmd_selftest || true
  setup_finish_if_complete
  say "$(msg W_DONE "$(setup_missing | tr '\n' ' ')")"
}

# --- commands at the box ---
cmd_clear() {   # clear <id>
  local id=$1 c
  valid_id "$id" || { say "$(msg E_USAGE_ID clear)" >&2; return 2; }
  code_require || return 1
  take_lock; disk_open || return 1
  if [ -r "$AUDIT/supheli/$id" ]; then
    say "$(msg C_SUSPECT_REASONS "$id")"; say "  $(reasons_text "$(cat "$AUDIT/supheli/$id")")"
    printf '%s' "$(msg P_CLEAR_CONFIRM)" >&2; read -r c || c=""
    if [ "$c" = CLEAR ]; then
      : > "$AUDIT/temiz/$id"
      if ! deletion_paused; then
        rm -f "$ST_SUSPECT_FLAG"; kv_set "$ST_MAINT" paused_since ""
        cp "$ST_LAST_PUBLISHED" "$ST_LAST_SOUND" 2>/dev/null || true
      else uncleared_suspects | LC_ALL=C sort | head -1 > "$ST_SUSPECT_FLAG"; fi
      suspect_state_sync
      notify cleared default N_CLEARED "$id"
    else say "$(msg E_ABORTED)"; fi
  else say "$(msg E_NOT_SUSPECT "$id")"; fi
  disk_close || true
  led_update
}

cmd_pin() {   # pin <id>
  local id=$1
  valid_id "$id" || { say "$(msg E_USAGE_ID pin)" >&2; return 2; }
  code_require || return 1
  take_lock; disk_open || return 1
  if [ -d "$GEN_DIR/gen-$id" ] || [ -d "$GEN_DIR/uzun-$id" ]; then : > "$AUDIT/pin/$id"; say "$(msg I_PINNED "$id")"
  else say "$(msg E_NO_GENERATION "$id")"; fi
  disk_close || true
}

cmd_disk_on() {
  code_require || return 1
  take_lock; disk_open || return 1
  if systemd_up; then
    systemd-run --quiet --on-active="${DISK_ON_MIN}min" --unit=purser-disk-off "$PURSER_BIN" disk-off >/dev/null 2>&1 || true
  fi
  say "$(msg I_DISK_ON "$MNT" "$DISK_ON_MIN")"
}
cmd_disk_off() {
  systemd_up && systemctl stop purser-disk-off.timer 2>/dev/null || true
  disk_close
}

cmd_first_fill() {
  code_require || return 1
  if systemd_up && [ -z "${FIRST_FILL_FOREGROUND:-}" ]; then
    systemd-run --unit=purser-first-fill --collect -E FIRST_FILL_FOREGROUND=1 "$PURSER_BIN" run --first-fill
    say "$(msg I_FIRST_FILL_STARTED)"
    return 0
  fi
  night_run first-fill
}

cmd_shell() {
  code_require || return 1
  notify maint_shell high N_MAINT_SHELL
  exec /bin/bash -l
}
