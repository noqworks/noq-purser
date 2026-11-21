# shellcheck shell=bash
# Alarm channel. It never passes through the protected server. A message contains only state the
# core produced itself: catalog text plus numbers, generation ids and reason codes. Nothing the
# server wrote (note=, file names) is ever placed in a message.

# notify <event> <priority: default|high|urgent> <message key> [args...]
notify() {
  local event=$1 prio=$2 key=$3 a text
  shift 3
  local args=()
  # arguments are core-generated (ids, numbers, catalog text); control characters are dropped anyway
  for a in "$@"; do args+=("$(printf '%s' "$a" | tr -d '\000-\037\177|' | cut -c1-400)"); done
  text=$(msg "$key" "${args[@]}")
  text=$(printf '%s' "$text" | tr -d '\r\n|')
  log "notify $event: $text"
  notify_send "$event" "$prio" "$text" && return 0
  notify_queue "$event" "$prio" "$text"
}

notify_queue() {
  [ -d "$STATE" ] || return 0
  printf '%s|%s|%s|%s\n' "$(now)" "$1" "$2" "$3" >> "$ST_NOTIFY_QUEUE"
  # keep the newest 50
  tail -50 "$ST_NOTIFY_QUEUE" > "$ST_NOTIFY_QUEUE.t" && mv -f "$ST_NOTIFY_QUEUE.t" "$ST_NOTIFY_QUEUE"
  log "notification queued ($1)"
  return 0
}

# Retry queued notifications in order; stop at the first failure.
notify_flush() {
  [ -s "$ST_NOTIFY_QUEUE" ] || return 0
  local at ev pr tx rest=() sending=1
  while IFS='|' read -r at ev pr tx; do
    if [ $sending = 1 ] && notify_send "$ev" "$pr" "$tx ($(date -u -d "@$at" +%Y-%m-%dT%H:%MZ))"; then continue; fi
    sending=0; rest+=("$at|$ev|$pr|$tx")
  done < "$ST_NOTIFY_QUEUE"
  if [ ${#rest[@]} -eq 0 ]; then rm -f "$ST_NOTIFY_QUEUE"; else printf '%s\n' "${rest[@]}" > "$ST_NOTIFY_QUEUE"; fi
}

# The secrets file holds NTFY_URL / NTFY_TOKEN or WEBHOOK_URL / WEBHOOK_TOKEN. It is parsed, not sourced.
secret_get() { [ -r "$NOTIFY" ] || return 0; sed -n "s/^$1=//p" "$NOTIFY" | tail -1 | sed "s/^['\"]//; s/['\"]$//"; }

notify_send() {   # notify_send <event> <priority> <text>; 0 = delivered
  local event=$1 prio=$2 text=$3 url token host re code
  [ -r "$NOTIFY" ] || { log "no notification channel configured"; return 1; }
  case $prio in default|high|urgent) ;; *) prio=default ;; esac
  case $NOTIFY_KIND in
    webhook) url=$(secret_get WEBHOOK_URL); token=$(secret_get WEBHOOK_TOKEN)
             re='^https://([a-z0-9.-]+)(/[A-Za-z0-9._~%/-]*)?$' ;;
    *)       url=$(secret_get NTFY_URL); token=$(secret_get NTFY_TOKEN)
             re='^https://([a-z0-9.-]+)/[A-Za-z0-9_-]{1,64}$' ;;
  esac
  [[ $url =~ $re ]] || { log "notification address is not valid"; return 1; }
  host=${BASH_REMATCH[1]}
  [[ $token =~ ^[A-Za-z0-9._~+/=-]*$ ]] || { log "notification token has invalid characters"; return 1; }
  notify_allow_host "$host"
  local h=()
  [ -n "$NOTIFY_CA" ] && h+=(--cacert "$NOTIFY_CA")
  [ -n "$token" ] && h+=(-H "Authorization: Bearer $token")
  if [ "$NOTIFY_KIND" = webhook ]; then
    h+=(-H "Content-Type: text/plain; charset=utf-8" -H "X-Purser-Event: $event" -H "X-Purser-Priority: $prio")
  else
    h+=(-H "Title: NOQ Purser" -H "Priority: $prio" -H "Tags: floppy_disk")
  fi
  # A 2xx answer means delivered, even if the connection then ends untidily (curl exit != 0):
  # queueing it as well would send the alarm twice.
  code=$(curl -sS --proto =https --max-time 20 -o /dev/null -w '%{http_code}' "${h[@]}" --data-binary "$text" "$url" 2>/dev/null || true)
  [[ $code =~ ^2[0-9][0-9]$ ]] && return 0
  log "notification not delivered (http $code)"
  return 1
}

# The box runs for months; the address is resolved again before every send and the nftables
# set is refreshed, so a changed address is followed and nothing else is allowed out on 443.
notify_allow_host() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list set inet "$NFT_TABLE" "$NFT_NOTIFY_SET" >/dev/null 2>&1 || return 0
  local ip
  nft flush set inet "$NFT_TABLE" "$NFT_NOTIFY_SET" 2>/dev/null || true
  for ip in $(getent ahostsv4 "$1" | awk '{ print $1 }' | sort -u); do
    [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || continue
    nft add element inet "$NFT_TABLE" "$NFT_NOTIFY_SET" "{ $ip }" 2>/dev/null || true
  done
}
