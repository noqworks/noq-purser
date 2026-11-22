# Minimal systemd host for the server-side install test. Deliberately WITHOUT rsync and
# openssh-server: source/install.sh has to install them itself.
ARG BASE=debian:trixie
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -q && apt-get -y -q upgrade && apt-get install -y -q --no-install-recommends systemd systemd-sysv dbus openssh-client procps \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl mask getty@tty1.service console-getty.service systemd-logind.service 2>/dev/null || true
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
