# Test environment for NOQ Purser. Debian 13 with systemd as PID 1 so the
# real systemd-run sandbox can be exercised. Nothing here runs on the host.
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      systemd systemd-sysv dbus bash coreutils findutils mawk sed grep util-linux util-linux-extra procps \
      rsync openssh-server openssh-client btrfs-progs argon2 shellcheck curl ca-certificates \
      python3 nftables chrony xz-utils e2fsprogs fdisk kmod file git acl sudo \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask getty@tty1.service console-getty.service systemd-logind.service ssh.service ssh.socket 2>/dev/null || true
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
