# Test environment for NOQ Purser. Debian with systemd as PID 1 so the real systemd-run sandbox
# can be exercised. Nothing here runs on the host. BASE=debian:bookworm matches the box image
# (systemd 252); the default debian:trixie is the current release.
ARG BASE=debian:trixie
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -q && apt-get -y -q upgrade && apt-get install -y -q --no-install-recommends \
      systemd systemd-sysv dbus bash coreutils findutils mawk sed grep util-linux util-linux-extra procps \
      rsync openssh-server openssh-client btrfs-progs argon2 shellcheck curl ca-certificates \
      python3 openssl nftables chrony xz-utils e2fsprogs fdisk kmod file git acl sudo ufw dosfstools \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask getty@tty1.service console-getty.service systemd-logind.service ssh.service ssh.socket 2>/dev/null || true
# privileged container, clock not namespaced: chronyd must never run in here (it would set the host clock)
RUN systemctl disable chrony.service 2>/dev/null; install -d /etc/systemd/system/chrony.service.d && printf "[Unit]\nConditionPathExists=/never-in-the-purser-lab\n" > /etc/systemd/system/chrony.service.d/purser-lab.conf
# no host keys baked into the image (every image would share them, and scanners rightly flag private keys):
# each lab container makes its own when it starts (tests/inner.sh)
RUN rm -f /etc/ssh/ssh_host_*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
