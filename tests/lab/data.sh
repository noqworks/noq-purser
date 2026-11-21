# shellcheck shell=bash
# Synthetic backup repositories that behave like the real tools at file level.
# Names, sizes and dates are made up.
S=/srv/src

rnd() { head -c "${2:-4096}" /dev/urandom > "$1"; }
sha() { sha256sum "$1" | cut -c1-64; }
seg_name() { printf '%024X' "$1"; }   # WAL segment name: timeline 1, increasing number

src_init() {
  rm -rf "${S:?}"/*; install -d "$S"
  # pgBackRest-like repository, stanza "demo"
  local p=$S/pgdemo
  install -d "$p/backup/demo" "$p/archive/demo/16-1/0000000100000000"
  echo info > "$p/backup/demo/backup.info"; cp "$p/backup/demo/backup.info" "$p/backup/demo/backup.info.copy"
  echo info > "$p/archive/demo/archive.info"; cp "$p/archive/demo/archive.info" "$p/archive/demo/archive.info.copy"
  pg_full 20260101-021500F
  echo 1 > "$S/.wal"; pg_wal 3
  # borg-like repository
  local b=$S/borgdemo
  install -d "$b/data/0"
  echo "borg repo" > "$b/README"; echo "[repository]" > "$b/config"
  for i in 1 2 3; do rnd "$b/data/0/$i" 8192; done
  echo 3 > "$S/.borg"; borg_meta 3
  # restic-like repository: every object is named after the sha256 of its content
  local r=$S/resticdemo
  install -d "$r/data" "$r/index" "$r/snapshots" "$r/keys" "$r/locks"
  echo "restic config" > "$r/config"
  restic_obj keys 256; restic_obj data 8192; restic_obj index 512; restic_obj snapshots 256
  # plain directory of dumps
  install -d "$S/dumps"; rnd "$S/dumps/dump-0.sql.gz" 4096
}

pg_full() {   # pg_full <label>
  local d=$S/pgdemo/backup/demo/$1
  install -d "$d/pg_data/base/1"
  rnd "$d/pg_data/base/1/1259.zst" 6000; rnd "$d/pg_data/base/1/2608.zst" 3000
  echo "manifest $1" > "$d/backup.manifest"; cp "$d/backup.manifest" "$d/backup.manifest.copy"
}
pg_diff() {   # pg_diff <full label> <diff stamp>
  local d=$S/pgdemo/backup/demo/${1}_${2}D
  install -d "$d/pg_data/base/1"
  rnd "$d/pg_data/base/1/1259.zst" 2000
  echo "manifest $1 $2" > "$d/backup.manifest"; cp "$d/backup.manifest" "$d/backup.manifest.copy"
}
pg_wal() {   # pg_wal <count>: append WAL segments (name-<sha1>.zst, like pgBackRest)
  local n i f h
  n=$(cat "$S/.wal")
  for (( i = 0; i < $1; i++ )); do
    f=$S/pgdemo/archive/demo/16-1/0000000100000000/$(seg_name "$n")
    rnd "$f.tmp" 3000; h=$(sha1sum "$f.tmp" | cut -c1-40); mv "$f.tmp" "$f-$h.zst"
    n=$(( n + 1 ))
  done
  echo "$n" > "$S/.wal"
  echo "info $(date +%s%N)" > "$S/pgdemo/archive/demo/archive.info"
}
borg_meta() {   # borg_meta <n>: rewrite index/hints/integrity for transaction n
  local b=$S/borgdemo
  rm -f "$b"/index.* "$b"/hints.* "$b"/integrity.*
  rnd "$b/index.$1" 512; rnd "$b/hints.$1" 128; rnd "$b/integrity.$1" 64
}
restic_obj() {   # restic_obj <dir> <size>
  local r=$S/resticdemo t h
  t=$(mktemp); rnd "$t" "$2"; h=$(sha "$t")
  if [ "$1" = data ]; then install -d "$r/data/${h:0:2}"; mv "$t" "$r/data/${h:0:2}/$h"; else mv "$t" "$r/$1/$h"; fi
  chmod 0644 "$r/$1"/* 2>/dev/null || true
}

# One night of ordinary activity. On Sunday (dow 7): new full, expire, compact, prune.
night_activity() {   # night_activity <YYYYMMDD> <dow>
  local day=$1 dow=$2 n
  local full; full=$(find "$S/pgdemo/backup/demo" -mindepth 1 -maxdepth 1 -type d -name '*F' -printf '%f\n' | sort | tail -1)
  if [ "$dow" = 7 ]; then
    pg_full "${day}-020500F"
    # expire: the old full with its diffs, and the WAL before the new full
    find "$S/pgdemo/backup/demo" -mindepth 1 -maxdepth 1 -type d -name "${full}*" -exec rm -rf {} +
    ls "$S/pgdemo/archive/demo/16-1/0000000100000000/" | sort | head -2 | while read -r f; do rm -f "$S/pgdemo/archive/demo/16-1/0000000100000000/$f"; done
    rm -f "$S/borgdemo/data/0/$(find "$S/borgdemo/data/0" -type f -printf "%f\n" | sort -n | head -1)"
    rm -f "$(find "$S/resticdemo/data" -type f | sort | head -1)"
  else
    pg_diff "$full" "${day}-023800"
  fi
  echo "info $day" > "$S/pgdemo/backup/demo/backup.info"; cp "$S/pgdemo/backup/demo/backup.info" "$S/pgdemo/backup/demo/backup.info.copy"
  pg_wal 2
  n=$(( $(cat "$S/.borg") + 1 )); rnd "$S/borgdemo/data/0/$n" 4096; echo "$n" > "$S/.borg"; borg_meta "$n"
  restic_obj data 4096; restic_obj index 256; restic_obj snapshots 128
  rnd "$S/dumps/dump-$day.sql.gz" 2048
  find "$S/dumps" -type f | sort | head -n -3 | xargs -r rm -f
}

# Server publishes generation <id> (test hook PURSER_SOURCE_ID).
publish_generation() { PURSER_SOURCE_ID=$1 /usr/local/sbin/purser-source run >/dev/null; }
