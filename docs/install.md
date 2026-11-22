# Installation

[Türkçe](install.tr.md)

Preview 1.0.0. Downloads: <https://open.noq.works/projects/purser/#download> (also on the GitHub
release). Every file is listed with its SHA-256 in `SHA256SUMS`.

## Overview

1. **On the server: purser install.** Creates a separate user and a narrow gate only the box uses. Looks at pgBackRest, Borg and restic settings and suggests the repositories it finds. Warns plainly about an unencrypted repository.
2. **On your computer: purser-setup.** purser-setup <image>.img.xz /dev/diskN. It checks the image's checksum and that the card is a removable disk, then asks for the box language, time zone, network (DHCP by default) and time server. It asks whether the disk is to be erased; if so you confirm by typing the new box id. You type the device name once more before the card is written.
3. **Write it on paper.** Once the card is written two things are shown once: the 12-digit operation code and, if the disk is erased, the recovery passphrase. Setup does not go on until you have written them down and typed "written". No copy stays on the computer or the server; do not photograph them.
4. **Insert the card, power on.** Card, disk, Ethernet, power last. The first boot is unattended: it takes the settings from the card, erases the setup partition and prepares the disk (cyan breathing). When it is done a dot lights at each end of the stick: waiting to be paired.
5. **On the server: purser pair.** The terminal shows a QR code and a one-line token, valid for ten minutes and once.
6. **Switch maintenance on, scan the QR code.** The light blinks purple. Open https://<id>.local on your phone and accept the browser's warning for the box's self-signed certificate once. Tap Pair and scan the code. With a clock module the phone's time is written to it once at this point.
7. **Switch it off.** The page, SSH and the box's presence on the network close. The box pulls its first backup that night; a green light in the morning means it worked.

## 1. Server

Debian 12/13 or Ubuntu 24.04+ with systemd.

```
tar xzf noq-purser-server-1.0.0.tar.gz && cd noq-purser-server-1.0.0
sudo ./install.sh                              # finds its LAN address; --listen <ip> to choose
sudo nano /etc/purser/source.conf               # SOURCES=("pgbackrest:/var/lib/pgbackrest" "borg:/srv/borg" ...)
sudo purser status
```

`install.sh` creates the gate user, a separate sshd for the gate (one port, default 2222, only
the admitted boxes' addresses), the nightly `purser-source` job (`--timer 04:30`) and the alarm
path. It is re-runnable. Alarms from the box arrive as `note <event>` and are raised with
`ALERT_CMD` in `source.conf` (default: the system log). Options: `--port`, `--base`, `--user`,
`--timer`, `--prefix`; `--uninstall` removes programs and units and keeps the data.

## 2. The card (on your computer)

macOS or Linux. In Terminal:

```
bash <(curl -fsSL https://open.noq.works/files/purser/purser-setup)
```

or unpack `noq-purser-setup-1.0.0.tar.gz` and run `bash purser-setup` (on a Mac you can double-click
`purser-setup.command`; the first time right-click > Open, it is a script, not a signed app).

The tool downloads the image from open.noq.works into your cache and checks its SHA-256, lists the
removable disks (the card) and asks: language, time zone, network (DHCP, or an address), time
server (`gateway` = the router), and whether the USB disk is to be erased and prepared (you type
the new box id to confirm). `flash.sh` then refuses anything that is not a whole removable disk of
at most 256 GB, and you type the device name once more. After writing it shows the operation code
and, when the disk is prepared, the recovery passphrase, once; write them on paper and type the
confirmation word. The settings and these one-time secrets go to the card's small setup partition
(`PURSERSET`); the first boot takes them over and overwrites the partition. Nothing is kept on the
computer. If `~/.ssh/id_ed25519.pub` exists it is put on the card for maintenance SSH
(`--no-ssh-key` to skip). With an image you already have: `purser-setup <image.img.xz> <device>`.

## 3. First boot

Card, USB disk, Ethernet, then power. The first boot is unattended: settings from the card, the
disk erased and prepared as LUKS2 + btrfs only with the marker you confirmed, a self-test. The
stick breathes cyan while the disk is prepared; a white stick with a dot at each end means it waits
to be paired. Without a time source (router NTP or the battery clock) the box takes no backup;
see [hardware.md](hardware.md) for the clock module.

## 4. Pairing

```
sudo purser pair                 # QR code and a one-line token, valid 10 minutes, once
```

Switch maintenance on (the stick alternates purple). On your phone open `https://<id>.local`
(the id is on the card label, e.g. `k7rt.local`), accept the warning for the box's self-signed
certificate once, tap Pair and scan the code (or paste the line). The box checks the server's
host key, the server admits the box's key for its address only, and with a battery clock the
phone's time is written to it. Switch maintenance off: the page, SSH and mDNS close. The box pulls
its first generation that night.

## Moving to a new SD card (update)

The box never updates itself. To update, build a new image and move the state over: the disk key,
the LUKS header backup, the notification address, the box's SSH key, the gate's host key,
`purser.conf` and `/var/lib/purser`. On a Linux machine (not on the protected server: the disk key
should never touch it):

```sh
# one card reader is enough: move the state into the image, then flash it
xz -dk out/noq-purser-….img.xz                                       # gives the .img
image/purser-card-migrate --from /dev/sdX --to out/noq-purser-….img   # old card in the reader
image/flash.sh out/noq-purser-….img /dev/sdX                           # new card in the reader
# or, with two readers: flash first, then migrate card to card
image/purser-card-migrate --from /dev/sdX --to /dev/sdY
```

`purser-card-migrate` writes a new `.img.sha256` after changing the image, so `flash.sh` checks
the file it writes. An embedded `setup.conf` in the new image is kept: its keys (e.g. a fixed
address) override the moved `purser.conf` at first boot; the old card's own network settings live
in its operating system and are not moved.

The old card is mounted read-only and stays unchanged. On first boot the box finds the moved
configuration and the disk by its LUKS UUID, adopts it and continues with the nightly job. A card
from the prototype has no operation code: the nightly job runs anyway, and a weekly reminder asks
for `setup-code` at the console. Keys the prototype wrote for hardware this release no longer
uses are ignored.

After the move, the image file (if you migrated into it) contains the disk key: delete it.

## Tests

```sh
tests/run.sh                    # all hardware-free suites in a disposable container
tests/run.sh --server-install   # server installation on Debian 13, Ubuntu 24.04, Ubuntu 26.04
tests/run.sh --image-tools      # flash.sh and purser-card-migrate
```

They need Docker and run privileged containers with loop devices; run them on a test machine.
