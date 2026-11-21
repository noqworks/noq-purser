# shellcheck shell=bash
# shellcheck disable=SC2034  # shared names
# The compromised server: root on the lab server edits what the gate serves.
SG=/srv/server/generation
list_of() { echo "$SG/$1.list"; }
# relist <id>: rewrite the list's data lines from the frozen tree as it is now (an attacker
# with root can always produce a list with valid hashes for whatever it serves)
relist() {
  local id=$1 l t
  l=$(list_of "$id"); t=$(mktemp)
  grep '^# ' "$l" > "$t"
  (cd "$SG/$id" && find . -type f -printf '%P\n' | LC_ALL=C sort | while read -r p; do sha256sum -- "$p"; done) >> "$t"
  cat "$t" > "$l"; rm -f "$t"
}
set_header() { sed -i "s|^# $2=.*|# $2=$3|" "$(list_of "$1")"; }
hash_of() { grep -F "  $2" "$(list_of "$1")" | awk -v p="$2" 'substr($0, 67) == p { print substr($0, 1, 64) }'; }
