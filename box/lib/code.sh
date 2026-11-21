# shellcheck shell=bash
# Operation code: a deliberate lock on the commands run at the box, not a security boundary.
# 12 digits in three groups, last digit a Damm check digit. Only an argon2id hash is stored
# (state area). Three wrong entries start a wait that doubles each time, 1 minute up to
# 24 hours; the counter lives on the SD card, a reboot does not reset it.

DAMM=(0317598642 7092154863 4206871359 1750983426 6123045978 3674209581 5869720134 8945362017 9438617205 2581436790)

damm_digit() {   # damm_digit <digits> -> check digit
  local s=$1 i interim=0 row
  for (( i = 0; i < ${#s}; i++ )); do
    row=${DAMM[$interim]}
    interim=${row:${s:$i:1}:1}
  done
  echo "$interim"
}
damm_valid() { [[ $1 =~ ^[0-9]+$ ]] && [ "$(damm_digit "$1")" = 0 ]; }

code_normalize() { printf '%s' "$1" | tr -d ' -'; }
code_format() { printf '%s %s %s' "${1:0:4}" "${1:4:4}" "${1:8:4}"; }

code_generate() {
  local d="" b
  while [ ${#d} -lt 11 ]; do
    for b in $(od -An -tu1 -N32 /dev/urandom); do
      [ "$b" -lt 250 ] && d+=$(( b % 10 ))
      [ ${#d} -ge 11 ] && break
    done
  done
  printf '%s%s' "$d" "$(damm_digit "$d")"
}

code_hash() {   # code_hash <code> <salt hex> -> argon2id encoded hash
  printf '%s' "$1" | argon2 "$2" -id -t 3 -m 16 -p 1 -e
}

code_store() {   # code_store <code>
  local salt
  salt=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
  ( umask 077; printf 'salt=%s\nhash=%s\nset=%s\n' "$salt" "$(code_hash "$1" "$salt")" "$(now)" > "$ST_CODE.new" )
  mv -f "$ST_CODE.new" "$ST_CODE"
  rm -f "$ST_CODE_LOCK"
}

code_is_set() { [ -s "$ST_CODE" ] && [ -n "$(kv_get "$ST_CODE" hash)" ]; }

code_locked_for() {   # seconds left in the current wait (0 = not locked)
  local till; till=$(kv_get "$ST_CODE_LOCK" until)
  [[ $till =~ ^[0-9]+$ ]] || { echo 0; return; }
  local left=$(( till - $(now) ))
  [ "$left" -gt 0 ] && echo "$left" || echo 0
}

# code_check <entered> : 0 ok, 1 wrong (counted), 2 typo (Damm, not counted), 3 locked
code_check() {
  local c fails level wait left
  left=$(code_locked_for)
  [ "$left" -gt 0 ] && return 3
  c=$(code_normalize "$1")
  [[ $c =~ ^[0-9]{12}$ ]] && damm_valid "$c" || return 2
  if [ "$(code_hash "$c" "$(kv_get "$ST_CODE" salt)")" = "$(kv_get "$ST_CODE" hash)" ]; then
    rm -f "$ST_CODE_LOCK"; return 0
  fi
  fails=$(( $(kv_get "$ST_CODE_LOCK" fails || echo 0) + 1 ))
  level=$(kv_get "$ST_CODE_LOCK" level); level=${level:-0}
  kv_set "$ST_CODE_LOCK" fails "$fails"
  if [ $(( fails % CODE_ATTEMPTS )) -eq 0 ]; then
    level=$(( level + 1 ))
    wait=$(( 60 * (1 << (level - 1)) )); [ "$wait" -gt 86400 ] && wait=86400
    kv_set "$ST_CODE_LOCK" level "$level"; kv_set "$ST_CODE_LOCK" until "$(( $(now) + wait ))"
    notify code_locked high N_CODE_LOCKED "$fails" "$(( wait / 60 ))"
  fi
  return 1
}

read_code() {   # prompt on stderr, read one line from stdin (no echo on a terminal)
  local c
  printf '%s' "$(msg P_CODE)" >&2
  if [ -t 0 ]; then read -r -s c || c=""; printf '\n' >&2; else read -r c || c=""; fi
  printf '%s' "$c"
}

# Every command at the box asks for the code. Returns 0 when it was entered correctly.
code_require() {
  local left c rc
  if ! code_is_set; then say "$(msg E_NO_CODE)" >&2; return 1; fi
  left=$(code_locked_for)
  if [ "$left" -gt 0 ]; then say "$(msg E_CODE_LOCKED "$(( (left + 59) / 60 ))")" >&2; return 1; fi
  for _ in 1 2 3; do
    c=$(read_code)
    rc=0; code_check "$c" || rc=$?
    case $rc in
      0) return 0 ;;
      2) say "$(msg E_CODE_TYPO)" >&2 ;;
      3) left=$(code_locked_for); say "$(msg E_CODE_LOCKED "$(( (left + 59) / 60 ))")" >&2; return 1 ;;
      *) say "$(msg E_CODE_WRONG)" >&2
         left=$(code_locked_for)
         if [ "$left" -gt 0 ]; then say "$(msg E_CODE_LOCKED "$(( (left + 59) / 60 ))")" >&2; return 1; fi ;;
    esac
  done
  return 1
}

# Generate, show once, ask for it back. Used by setup-code, new-code and reset-code.
code_new_interactive() {
  local c back
  c=$(code_generate)
  say ""
  say "$(msg C_SHOW)"
  say ""
  say "      $(code_format "$c")"
  say ""
  say "$(msg C_SHOW_HINT)"
  printf '%s' "$(msg P_CODE_BACK)" >&2
  if [ -t 0 ]; then read -r back || back=""; else read -r back || back=""; fi
  if [ "$(code_normalize "$back")" != "$c" ]; then say "$(msg E_CODE_BACK)" >&2; return 1; fi
  code_store "$c"
  [ -t 1 ] && clear 2>/dev/null || true
  say "$(msg C_STORED)"
}

cmd_setup_code() {
  if code_is_set; then say "$(msg E_CODE_EXISTS)" >&2; return 1; fi
  code_new_interactive
}
cmd_new_code() { code_require && code_new_interactive; }
cmd_reset_code() {
  local c
  say "$(msg C_RESET_WARN)"
  printf '%s' "$(msg P_RESET_CONFIRM)" >&2
  read -r c || c=""
  [ "$c" = RESET ] || { say "$(msg E_ABORTED)" >&2; return 1; }
  notify code_reset urgent N_CODE_RESET
  code_new_interactive
}
