#!/bin/bash
# NOQ Purser, server side, straight from open.noq.works (no download step by hand):
#   curl -fsSL https://open.noq.works/files/purser/install | sudo bash -s -- --listen <LAN address>
# It reads the release manifest, fetches the server package, checks its SHA-256 and runs
# install.sh with your options. install.sh keeps its own copy under /usr/local/share/noq-purser.
set -euo pipefail
R=${PURSER_RELEASES:-https://open.noq.works/files/purser}
[ "$(id -u)" = 0 ] || { echo "run it with sudo" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl is needed" >&2; exit 1; }
m=$(curl -fsSL --proto '=https,file' "$R/latest.txt")
V=$(awk '$1 == "version" { print $2; exit }' <<< "$m")
N=$(awk '$1 == "server" { print $2; exit }' <<< "$m")
S=$(awk '$1 == "server" { print $3; exit }' <<< "$m")
[[ $V =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ $N =~ ^noq-purser-server-[0-9.]+\.tar\.gz$ ]] && [[ $S =~ ^[0-9a-f]{64}$ ]] \
  || { echo "bad release manifest at $R/latest.txt" >&2; exit 1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
echo "NOQ Purser $V: fetching $N"
curl -fsSL --proto '=https,file' -o "$t/$N" "$R/$V/$N"
[ "$(sha256sum "$t/$N" | cut -c1-64)" = "$S" ] || { echo "checksum mismatch: not the published package" >&2; exit 1; }
tar -C "$t" -xzf "$t/$N"
PURSER_VERSION=$V bash "$t/noq-purser-server-$V/install.sh" "$@"
echo
echo "next: edit /etc/purser/source.conf (your backup repositories), then: sudo purser pair"
