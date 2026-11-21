# shellcheck shell=bash
# Everything that touches data the server controls runs here: an unprivileged user in a
# transient systemd unit with a read-only system, one writable path at most, no secrets,
# no device nodes, a runtime ceiling and a per-file size ceiling.
#
# SANDBOX=setpriv is a weaker fallback used by the test suite where no systemd is PID 1:
# same user and time ceiling, but no namespace restrictions.

VERIFY_BIN=${VERIFY_BIN:-/usr/local/lib/purser/purser-verify}

sandbox() {   # sandbox <user> <writable path|-> <seconds> <net|nonet> -- command...
  local user=$1 rw=$2 t=$3 net=$4
  shift 5
  if [ "$SANDBOX" = setpriv ]; then
    timeout --kill-after=10 "$t" setpriv --reuid="$user" --regid="$user" --init-groups --no-new-privs -- "$@"
    return
  fi
  local p=(-p User="$user" -p Group="$user" -p ProtectSystem=strict -p ProtectHome=yes -p PrivateTmp=yes
           -p PrivateDevices=yes -p NoNewPrivileges=yes -p CapabilityBoundingSet= -p RestrictSUIDSGID=yes
           -p ProtectKernelTunables=yes -p ProtectKernelModules=yes -p ProtectControlGroups=yes -p LockPersonality=yes
           -p SystemCallFilter=@system-service -p SystemCallErrorNumber=EPERM -p RuntimeMaxSec="$t"
           -p LimitFSIZE="$MAX_FILE_SIZE" -p InaccessiblePaths="-$SECRETS -$STATE")
  [ "$rw" != - ] && p+=(-p ReadWritePaths="$rw")
  if [ "$net" = net ]; then
    p+=(-p RestrictAddressFamilies="AF_INET AF_INET6 AF_UNIX")
  else
    p+=(-p PrivateNetwork=yes -p RestrictAddressFamilies=AF_UNIX -p InaccessiblePaths="-$SSH_DIR")
  fi
  if sandbox_expands_env; then
    # systemd < 254 (Debian 12) has no --expand-environment=no and expands $NAME in the command
    # line of the unit; "$$" is its escape for a literal "$".
    local a esc=()
    for a in "$@"; do esc+=("${a//\$/\$\$}"); done
    systemd-run --wait --pipe --quiet --collect "${p[@]}" -- "${esc[@]}"
  else
    systemd-run --wait --pipe --quiet --collect --expand-environment=no "${p[@]}" -- "$@"
  fi
}

# 0 when this systemd-run would expand variables in the command (no --expand-environment option).
sandbox_expands_env() {
  if [ -z "${SANDBOX_EXPANDS:-}" ]; then
    if systemd-run --help 2>/dev/null | grep -q -- '--expand-environment'; then SANDBOX_EXPANDS=no; else SANDBOX_EXPANDS=yes; fi
  fi
  [ "$SANDBOX_EXPANDS" = yes ]
}

ssh_opts() {
  SSH_OPTS=(-i "$SSH_DIR/id_ed25519" -o Port="$SERVER_PORT" -o UserKnownHostsFile="$SSH_DIR/known_hosts"
            -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30
            -o IdentitiesOnly=yes -o ClearAllForwardings=yes -o RequestTTY=no)
}
ssh_e() { ssh_opts; printf 'ssh %s' "$(printf '%q ' "${SSH_OPTS[@]}")"; }

# Gate requests (latest, ack) run as the rsync user too: root never talks to the server.
remote() {   # remote <request...>
  ssh_opts
  sandbox "$RSYNC_USER" - 60 net -- ssh "${SSH_OPTS[@]}" "$SERVER_USER@$SERVER" "$@"
}

# shellcheck disable=SC2034  # used by the caller
rsync_opts() {
  RSYNC_OPTS=(rsync -rt --perms --chmod=D0755,F0644 --delete --no-links --no-specials --no-devices
              --timeout="$RSYNC_IO_TIMEOUT" --partial-dir=.purser-partial --max-size="$MAX_FILE_SIZE")
  [ -n "${RSYNC_BWLIMIT:-}" ] && RSYNC_OPTS+=(--bwlimit="$RSYNC_BWLIMIT")
  return 0
}

verify() {   # verify <subcommand> args...  (no network, writes nowhere)
  sandbox "$VERIFY_USER" - "${VERIFY_TIMEOUT:-3600}" nonet -- "$VERIFY_BIN" "$@"
}
