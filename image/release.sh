#!/bin/bash
# NOQ Purser: assemble a release from the built image and the repository.
#   image/release.sh <built image .img.xz> [--preview]
# Writes /muessese/noqopen/_yayin/purser/<version>/ (the files people download) and
# /muessese/noqopen/purser/{latest.txt,releases.json}; open.noq.works serves them under
# /files/purser/ (scripts/deploy.sh copies them), the GitHub release carries the same files.
set -euo pipefail
export LC_ALL=C
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=${1:?built image .img.xz}; PREVIEW=false; [ "${2:-}" = --preview ] && PREVIEW=true
V=$(cat "$REPO/box/version" 2>/dev/null || sed -n 's/^PURSER_VERSION=//p' "$REPO/box/lib/common.sh" | tr -d '"' | head -1)
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "cannot read the version ($V)" >&2; exit 1; }
OUT=/muessese/noqopen/_yayin/purser/$V
META=/muessese/noqopen/purser
want=$(awk '{ print $1; exit }' "$SRC.sha256"); have=$(sha256sum "$SRC" | cut -c1-64)
[ "$want" = "$have" ] || { echo "image checksum mismatch" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT" "$META"
IMG=noq-purser-$V-orangepizero3.img.xz
cp "$SRC" "$OUT/$IMG"
install -m 0755 "$REPO/image/flash.sh" "$REPO/image/purser-setup" "$OUT/"
printf '#!/bin/bash\n# double-click on a Mac (first time: right-click > Open)\ncd "$(dirname "$0")" && exec bash ./purser-setup\n' > "$OUT/purser-setup.command"
chmod 0755 "$OUT/purser-setup.command"

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# the computer tool
d=$t/noq-purser-setup-$V; mkdir -p "$d"
cp -p "$OUT/purser-setup" "$OUT/purser-setup.command" "$OUT/flash.sh" "$d/"
cp "$REPO/LICENSE" "$d/"
cat > "$d/README.txt" <<EOF
NOQ Purser $V: card setup (macOS and Linux)

macOS: double-click purser-setup.command (the first time: right-click > Open).
Linux / Terminal: bash purser-setup

It downloads the box image from open.noq.works and checks it, lists the SD cards, asks a few
questions, writes the card and shows the operation code (and the disk recovery passphrase) once.
Guide: https://open.noq.works/projects/purser/
EOF
tar -C "$t" --owner=0 --group=0 -czf "$OUT/noq-purser-setup-$V.tar.gz" "noq-purser-setup-$V"
# the server side
s=$t/noq-purser-server-$V; mkdir -p "$s"
cp -rp "$REPO/source/." "$s/"; cp "$REPO/LICENSE" "$s/"
printf '%s\n' "$V" > "$s/version"
cat > "$s/README.txt" <<EOF
NOQ Purser $V: server side (Debian, Ubuntu; systemd)

  sudo ./install.sh --listen <this server's LAN address>
  sudo nano /etc/purser/source.conf      (which backup repositories the box pulls)
  sudo purser pair                       (QR code for the box page)

Guide: https://open.noq.works/projects/purser/
EOF
tar -C "$t" --owner=0 --group=0 -czf "$OUT/noq-purser-server-$V.tar.gz" "noq-purser-server-$V"
(cd "$OUT" && sha256sum "$IMG" flash.sh purser-setup purser-setup.command "noq-purser-setup-$V.tar.gz" "noq-purser-server-$V.tar.gz" > SHA256SUMS)
sum() { awk -v n="$1" '$2 == n { print $1 }' "$OUT/SHA256SUMS"; }
size() { stat -c %s "$OUT/$1"; }
printf '%s  %s\n' "$(sum "$IMG")" "$IMG" > "$OUT/$IMG.sha256"
cat > "$META/latest.txt" <<EOF
version $V
image $IMG $(sum "$IMG")
flash flash.sh $(sum flash.sh)
setup noq-purser-setup-$V.tar.gz $(sum "noq-purser-setup-$V.tar.gz")
server noq-purser-server-$V.tar.gz $(sum "noq-purser-server-$V.tar.gz")
EOF
python3 - "$META/releases.json" "$V" "$PREVIEW" "$OUT" <<'P'
import json, os, sys, datetime
path, v, preview, out = sys.argv[1], sys.argv[2], sys.argv[3] == "true", sys.argv[4]
sums = dict(reversed(l.split()) for l in open(os.path.join(out, "SHA256SUMS")))
names = ["noq-purser-%s-orangepizero3.img.xz" % v, "noq-purser-setup-%s.tar.gz" % v, "noq-purser-server-%s.tar.gz" % v, "purser-setup", "flash.sh"]
files = [{"name": n, "sha256": sums[n], "size": os.path.getsize(os.path.join(out, n))} for n in names]
try:
    d = json.load(open(path))
except (OSError, ValueError):
    d = {}
d.update(product="purser", name="NOQ Purser", repo="https://github.com/noqworks/noq-purser",
         site="https://open.noq.works/projects/purser/", files="https://open.noq.works/files/purser/")
rel = [r for r in d.get("releases", []) if r.get("version") != v]
rel.insert(0, {"version": v, "date": datetime.date.today().isoformat(), "preview": preview, "files": files,
               "summary": {"tr": "İlk önizleme: kart tek komutla hazırlanır, eşleşme QR ile, isteğe bağlı pil saati.",
                           "en": "First preview: the card is prepared with one command, pairing by QR code, optional battery clock."}})
d["releases"] = rel
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2); open(path, "a").write("\n")
P
cp "$META/releases.json" "$OUT/releases.json"
ls -la "$OUT"; cat "$META/latest.txt"
