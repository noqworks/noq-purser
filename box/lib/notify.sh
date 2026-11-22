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
  log "notify $event ($prio): $text"
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

# The alarm goes to the server, over the same gate the box uses every night: "note <event>".
# The server raises it with its own ALERT_CMD. No third-party service, no internet: the box can
# only reach the gate. Only the event name travels (a fixed alphabet); the text stays in the box
# log and on the page. Until the box is paired there is nowhere to send to: the note is queued.
notify_send() {   # notify_send <event> <priority> <text>; 0 = delivered
  local event=$1
  [ -n "$SERVER" ] && [ -s "$SSH_DIR/known_hosts" ] || return 1
  [[ $event =~ ^[a-z_]{1,32}$ ]] || event=other
  remote note "$event" < /dev/null > /dev/null 2>&1
}
