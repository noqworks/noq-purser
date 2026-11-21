# shellcheck shell=bash
# Message catalog. Every text a person reads (console, notification) comes from
# $PURSER_LIB/messages/<lang>. Format: KEY|printf template. English is loaded first, so a key
# missing from another language falls back to English instead of printing the key.

declare -gA MSG=()

load_messages() {
  local lang=${LANG_UI:-en} f k v
  case $lang in en|tr) ;; *) lang=en ;; esac
  for f in "$PURSER_LIB/messages/en" "$PURSER_LIB/messages/$lang"; do
    [ -r "$f" ] || continue
    while IFS='|' read -r k v; do
      case $k in ''|'#'*) continue ;; esac
      MSG[$k]=$v
    done < "$f"
  done
}

# msg KEY [args...]: templates are trusted (catalog), arguments are data.
msg() {
  local k=$1; shift
  local t=${MSG[$k]-$k}
  # shellcheck disable=SC2059
  printf -- "$t" "$@"
}
