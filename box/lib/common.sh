# shellcheck shell=bash
# NOQ Purser box: configuration, frozen on-disk names, logging, small helpers.
#
# Backward compatibility: every name in the "frozen" blocks below is read by boxes that are
# already in service (disk layout, SD state files, users, nftables names). The names predate the
# English code base; they are part of the format and do not change. purser.conf is sourced, so
# keys an older release wrote and this one no longer knows are simply ignored.

CONF=${PURSER_CONF:-/etc/purser/purser.conf}
# shellcheck disable=SC2034
PURSER_VERSION=1.0.0

load_config() {
  if [ -r "$CONF" ]; then
    # shellcheck source=/dev/null
    . "$CONF"
  fi
  # --- keys of the original purser.conf (names and defaults unchanged) ---
  : "${SERVER:=}" "${SERVER_PORT:=22}" "${SERVER_USER:=purser}" "${LUKS_UUID:=}"
  : "${MNT:=/srv/purser}" "${STATE:=/var/lib/purser}"
  : "${SSH_DIR:=/etc/purser/ssh}" "${LUKS_KEY:=/etc/purser/sirlar/luks.key}" "${NOTIFY:=/etc/purser/sirlar/bildirim}"
  : "${POLL_UNTIL:=08:30}" "${POLL_EVERY:=300}" "${MAX_MIN:=80}" "${LONG_DOW:=7}"
  : "${KEEP_DAILY:=14}" "${KEEP_WEEKLY:=8}" "${KEEP_MONTHLY:=12}"
  : "${WARN_FACTOR:=3}" "${STALE_NIGHTS:=2}" "${LATE_H:=30}" "${KINDS:=}"
  # --- keys added in 1.0 ---
  : "${LANG_UI:=en}" "${NOTIFY_KIND:=ntfy}" "${NOTIFY_CA:=}"
  : "${NIGHT_AT:=05:15}" "${PRUNE_DOW:=$LONG_DOW}" "${LABEL_MAX_DAYS:=2}"
  : "${MASS_DELETE_PCT:=50}" "${MASS_CHANGE_PCT:=50}" "${MASS_MIN_FILES:=20}"
  : "${DISK_MIN_FREE_PCT:=10}" "${DISK_WAIT:=60}" "${DISK_ON_MIN:=30}"
  : "${MAX_FILE_SIZE:=256G}" "${LIST_MAX_SIZE:=512M}" "${RSYNC_IO_TIMEOUT:=300}" "${RSYNC_BWLIMIT:=}"
  : "${DNS_SERVERS:=1.1.1.1 9.9.9.9}" "${NTP_SERVERS:=}" "${NTP_POOL:=pool.ntp.org}" "${CLOCK_JUMP_MAX:=600}"
  : "${MAINT_SSH_FROM:=}" "${SERIAL_TTY:=ttyS0}" "${IMAGE_MAX_DAYS:=182}"
  : "${SCRUB_EVERY_DAYS:=30}" "${SMART_EVERY_DAYS:=30}" "${RESERVE_MIN:=10}"
  : "${LONG_MIN_NIGHTS:=4}" "${MONTHLY_MIN_WEEKS:=3}"
  : "${CODE_ATTEMPTS:=3}" "${SANDBOX:=systemd}" "${BOARD_LED:=auto}"
  : "${SYS_DIR:=/sys}" "${DEV_DIR:=/dev}" "${BY_UUID_DIR:=/dev/disk/by-uuid}" "${MAPPER_DIR:=/dev/mapper}" "${RUN_DIR:=/run/purser}"
  : "${LOCK_FILE:=/run/purser.lock}" "${PURSER_BIN:=/usr/local/sbin/purser}" "${CONSOLE_UNIT:=}"
  : "${IMAGE_RELEASE:=$PURSER_LIB/image-release}"
  frozen_names
}

# shellcheck disable=SC2034  # names are used by the other library files
frozen_names() {
  # --- disk (LUKS mapper, btrfs layout) ---
  MAP=purser
  GEN_DIR=$MNT/nesil                  # published generations: gen-<id> (daily), uzun-<id> (long retention)
  AUDIT=$MNT/denetim                  # audit area: liste/ meta/ supheli/ temiz/ pin/
  STAGING=$MNT/hazirlik               # writable snapshot the sync writes into
  LONG_TMP=$GEN_DIR/.uzun-yapim       # long-retention cut under construction
  META_BYTES=bayt META_FILES=dosya META_SECONDS=sure META_WARN=uyari META_SUSPECT=suphe
  # --- SD card ---
  SECRETS=/etc/purser/sirlar
  INCOMING=/var/lib/purser-gelen
  RSYNC_USER=purser-rsync VERIFY_USER=purser-dogrula
  NFT_TABLE=purser NFT_NOTIFY_SET=bildirim
  ST_LAST_PUBLISHED=$STATE/son-yayin
  ST_LAST_SOUND=$STATE/son-saglam
  ST_PENDING_ACK=$STATE/bekleyen-ack        # "<id> <verdict>"
  ST_SUSPECT_FLAG=$STATE/supheli-var
  ST_LAST_LIST=$STATE/son.list
  ST_TRANSFER_HISTORY=$STATE/aktarim.gecmis # "<id> <weekday> <bytes>"
  ST_STALE_PREFIX=$STATE/bayat-             # bayat-<source dir>: nights without change
  ST_MARK=$STATE/t0
  ST_VERIFY_SET=$STATE/dogrula
  ST_LATE_SENT=$STATE/gecikme-bildirildi
  ST_TIMER_OFF_SENT=$STATE/kapali-bildirildi
  # --- SD card, added in 1.0 ---
  ST_LAST_RUN=$STATE/last-run
  ST_CODE=$STATE/code.hash
  ST_CODE_LOCK=$STATE/code.lock
  ST_NOTIFY_QUEUE=$STATE/notify.queue
  ST_MAINT=$STATE/maint
  ST_DISK_USAGE=$STATE/disk.usage
  ST_SMART=$STATE/smart.summary
  ST_SENT_PREFIX=$STATE/sent.
  ST_SETUP=$STATE/setup
  ST_USB_PORT=$STATE/usb.port
  ST_CLOCK_SENT=$STATE/clock.sent
  ID_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}Z$'
}

log() { printf 'purser: %s\n' "$*" >&2; logger -t purser -- "$*" 2>/dev/null || true; }
say() { printf '%s\n' "$*"; }
fail() { log "$*"; return 1; }

now() { if [ -n "${PURSER_FAKE_NOW:-}" ]; then echo "$PURSER_FAKE_NOW"; else date +%s; fi; }
today() { date -d "@$(now)" +%F; }
id_epoch() { date -u -d "${1:0:10} ${1:11:2}:${1:14:2}" +%s; }
id_dow() { date -u -d "${1:0:10}" +%u; }
valid_id() { [[ ${1:-} =~ $ID_RE ]]; }
human_gb() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1e9 }'; }

# Values that reach a notification or the console are reduced to a safe alphabet.
safe_text() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 .,:_/+-' | cut -c1-120; }

# key=value files (state and maintenance bookkeeping). Values never contain newlines.
kv_get() { [ -r "$1" ] || return 0; sed -n "s/^$2=//p" "$1" | tail -1; }
kv_set() {   # kv_set <file> <key> <value>
  local f=$1 k=$2 v=$3 t
  t=$(mktemp "$f.XXXXXX")
  { [ -r "$f" ] && grep -v "^$k=" "$f" || true; printf '%s=%s\n' "$k" "$v"; } > "$t"
  chmod 0600 "$t"; mv -f "$t" "$f"
}
write_atomic() {   # write_atomic <file> <content>
  local t; t=$(mktemp "$1.XXXXXX"); printf '%s\n' "$2" > "$t"; mv -f "$t" "$1"
}

# Send a given reminder at most once per period (seconds). Returns 0 when it is due.
due_once() {   # due_once <key> <period s>
  local f=$ST_SENT_PREFIX$1 last
  last=$(cat "$f" 2>/dev/null || echo 0)
  [[ $last =~ ^[0-9]+$ ]] || last=0
  [ $(( $(now) - last )) -ge "$2" ] || return 1
  now > "$f"
}

need_config() {
  local k missing=()
  for k in "$@"; do [ -n "${!k:-}" ] || missing+=("$k"); done
  [ ${#missing[@]} -eq 0 ] && return 0
  say "$(msg ERR_CONFIG_MISSING "${missing[*]}")" >&2
  exit 2
}

take_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || { say "$(msg ERR_BUSY)" >&2; exit 1; }
}

# Kinds: "type:dir[:prune days]"; prune days is "any" or a comma list of ISO weekdays (1-7).
kind_type() { printf '%s' "${1%%:*}"; }
kind_dir() { local r=${1#*:}; printf '%s' "${r%%:*}"; }
kind_prune() { local r=${1#*:}; if [ "$r" = "${r#*:}" ]; then printf '%s' "$PRUNE_DOW"; else printf '%s' "${r#*:}"; fi; }
prune_allowed() {   # prune_allowed <days spec> <weekday>
  [ "$1" = any ] && return 0
  [[ ",$1," == *",$2,"* ]]
}
