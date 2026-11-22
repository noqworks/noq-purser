# Build environment for the NOQ Purser box image. arm64 code runs under proot + qemu user
# emulation; nothing is registered with the host kernel (no binfmt_misc).
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
COPY enosys.py /usr/local/bin/enosys
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      python3 proot qemu-user rsync xz-utils e2fsprogs zerofree util-linux fdisk coreutils ca-certificates curl file dosfstools mtools \
    && rm -rf /var/lib/apt/lists/* && chmod 0755 /usr/local/bin/enosys
