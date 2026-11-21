#!/bin/bash
# shellcheck disable=SC2034,SC2317  # variables are read by the sourced core; stubs are called indirectly
# purser-verify list: the list format the box accepts, and every way it rejects one.
. /src/tests/lib/assert.sh
V=/usr/local/lib/purser/purser-verify
ID=2026-03-01T03-10Z
H=$(printf 'a%.0s' $(seq 1 64))
W=$(mktemp -d)
hdr() {
  printf '# purser-list 1\n# generation=%s\n# created=2026-03-01T03:11:52Z\n# clean=yes\n# fresh=yes\n# note=pgbackrest verify ok; borg 02:48\n' "$ID"
}
check() {   # check <description> <expected reason|OK> ; list on stdin
  local f=$W/l out rc
  cat > "$f"
  out=$($V list "$f" "$ID" 2>&1); rc=$?
  if [ "$2" = OK ]; then eq "$1" "0 " "$rc $out"; else eq "$1" "1 $2" "$rc $out"; fi
}

check "good list accepted" OK < <({ hdr; echo "$H  pgdemo/backup/demo/backup.info"; echo "$H  dumps/dump-1.sql.gz"; })
check "header-only list (empty generation) accepted" OK < <(hdr)
check "full path alphabet accepted" OK < <({ hdr; echo "$H  a+b/c-d_e.f"; })

check "version 2 rejected" LIST_VERSION < <({ echo "# purser-list 2"; hdr | tail -n +2; })
check "leading space before the version line rejected" LIST_VERSION < <({ printf ' '; hdr; })
check "byte order mark rejected" LIST_VERSION < <({ printf '\xef\xbb\xbf'; hdr; })
check "missing version line rejected" LIST_VERSION < <({ hdr | tail -n +2; })

check "upper-case header key rejected" LIST_HEADER < <({ hdr; echo "# Note=x"; })
check "non-ASCII header value rejected" LIST_HEADER < <({ hdr | sed 's/^# note=.*/# note=caf\xc3\xa9/'; })
check "slash in a header rejected" LIST_HEADER < <({ hdr | sed 's|^# note=.*|# note=see https://example.org|'; })
check "control character in a header rejected" LIST_HEADER < <({ hdr | sed "s/^# note=.*/# note=x$(printf '\001')y/"; })
check "duplicate header rejected" LIST_DUP_HEADER < <({ hdr; echo "# clean=no"; })
check "other generation id rejected" LIST_GENERATION < <({ hdr | sed "s/^# generation=.*/# generation=2026-03-02T03-10Z/"; })
check "missing generation header rejected" LIST_GENERATION < <({ hdr | sed '/^# generation=/d'; })
check "clean=maybe rejected" LIST_CLEAN < <({ hdr | sed 's/^# clean=yes/# clean=maybe/'; })
check "missing clean header rejected" LIST_CLEAN < <({ hdr | sed '/^# clean=/d'; })
check "fresh=unknown rejected" LIST_FRESH < <({ hdr | sed 's/^# fresh=yes/# fresh=unknown/'; })

check "upper-case hash rejected" LIST_LINE < <({ hdr; echo "${H^^}  dumps/x"; })
check "single space rejected" LIST_LINE < <({ hdr; echo "$H dumps/x"; })
check "space in a path rejected" LIST_LINE < <({ hdr; echo "$H  dumps/a b"; })
check "control character in a path rejected" LIST_LINE < <({ hdr; printf '%s  dumps/a\001b\n' "$H"; })
check "tab in a path rejected" LIST_LINE < <({ hdr; printf '%s  dumps/a\tb\n' "$H"; })
check "non-ASCII path rejected" LIST_LINE < <({ hdr; echo "$H  dumps/çay"; })
check "header line after the data rejected" LIST_LINE < <({ hdr; echo "$H  dumps/x"; echo "# clean=yes"; })
check "shell metacharacter in a path rejected" LIST_LINE < <({ hdr; echo "$H  dumps/x;rm"; })
check "path over 1024 characters rejected" LIST_LONG < <({ hdr; echo "$H  $(printf 'p%.0s' $(seq 1 1100))"; })

for p in /etc/passwd ../x dumps/../../etc dumps/.. . ./x dumps/./x dumps//x dumps/ dumps/.purser-partial/x; do
  check "path '$p' rejected" LIST_PATH < <({ hdr; echo "$H  $p"; })
done
check "duplicate path rejected" LIST_DUP < <({ hdr; echo "$H  dumps/x"; echo "$H  dumps/y"; echo "$H  dumps/x"; })
check "path that is also a directory rejected" LIST_PREFIX < <({ hdr; echo "$H  dumps"; echo "$H  dumps/x"; })
rm -rf "$W"
done_testing
