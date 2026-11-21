# Installation

[Türkçe](install.tr.md)

Three steps: the server side, the box image, the first boot. Addresses below are examples
(`192.0.2.10` server, `192.0.2.15` box).

## 1. Server side

On the protected server, as root (Debian 12/13, Ubuntu 24.04/26.04; tested on Debian 13,
Ubuntu 24.04 and 26.04):

```sh
git clone <this repository> noq-purser && cd noq-purser
source/install.sh --listen 192.0.2.10 --port 2222 --base /srv/purser --timer 04:30
```

It installs what is missing (`rsync`, `openssh-server`, `python3` for `rrsync`), creates the gate
user (no password, no login shell use), puts `purser-source`, `purser-gate` and `purser-admit`
into `/usr/local/sbin`, writes `/etc/purser/source.conf` (only if there is none), the gate's own
host key, and the units `purser-source.timer` (nightly), `purser-source-watch.timer` (hourly) and
`purser-sshd.service` (a separate sshd for the box only; the main sshd is not touched). It can be
run again at any time; `--uninstall` removes programs and units, keeps the data under `--base`
and moves `/etc/purser` aside.

Then edit `/etc/purser/source.conf`. The examples in `source/examples/` (pgBackRest, borg, restic,
plain directory) show sources, wait units, freshness and verification commands. Check it and
enable the timer:

```sh
purser-source check
systemctl enable --now purser-source.timer
```

Names inside the backups must use `A-Z a-z 0-9 . _ / + -`; anything else belongs inside a borg or
restic repository. Encrypt the sources with their own tools (borg/restic repokey, pgBackRest
`repo-cipher-type`): the box keeps its disk key on the box.

The box is admitted later, when it shows its key (step 3):

```sh
purser-admit 192.0.2.15 'ssh-ed25519 AAAA… purser@noq-purser'
```

This writes the key with `from="192.0.2.15",restrict,command="…/purser-gate"`, renders the gate's
sshd configuration, limits the gate unit to the box address and adds a ufw or firewalld rule (with
plain nftables it prints the rule to add). It prints the gate's host key fingerprint; the box
asks you to compare it. `purser-admit --revoke` closes the gate.

## 2. The box image

On any Linux machine with Docker (nothing is installed on the host; arm64 programs run under
proot + qemu inside the build container, nothing is registered with the host kernel):

```sh
image/build-image.sh --cache ./build-cache --out ./out [--setup-conf my-setup.conf]
```

- The base is a pinned Armbian release for the Orange Pi Zero 3 (Debian 12); its sha256 is in
  the script and is checked before the file is used.
- All packages the box needs are installed into the image at build time. The running box never
  fetches code or packages: its firewall has no rule for it and the apt timers are masked.
- The image comes with: SSH server masked, root password locked (`*`), no login on the serial
  console (the restricted `purser-console` runs there instead), Wi-Fi and Bluetooth off, chrony
  instead of timesyncd, empty machine id, no SSH host keys.
- Result: `out/noq-purser-<version>-orangepizero3-<date>.img.xz` and its `.sha256`.
- The first build takes long (the package stage); later builds reuse it (`--rebuild-base` redoes
  it).

**Optional unattended first boot.** Copy `image/setup.conf.example`, fill it in and pass it with
`--setup-conf`. The box reads it once and shreds it. It can configure the gate (accepting its host
key only when it matches `SERVER_HOSTKEY_FP`), sources, window, notification channel, language,
fixed address (`NET_ADDRESS`, `NET_GATEWAY`; empty = DHCP), DNS, NTP and adopt a moved disk. A
**new** disk is always prepared at the serial console, because its recovery passphrase is shown
exactly once.

**Write the card** (Linux or macOS):

```sh
image/flash.sh out/noq-purser-….img.xz /dev/sdX        # Linux; macOS: /dev/diskN (diskutil list)
```

It checks the image against its `.sha256`, refuses the disk the running system lives on, mounted
system disks, non-removable disks and disks larger than 256 GB (`--force-size`), and asks you to
type the device name back before it writes.

## 3. First boot

Connect the cable and the disk to the board, Ethernet, the USB-serial adapter on the debug UART
(115200 baud), insert the card, power on. The first-boot service creates the users and keys,
applies `setup.conf` if there is one, applies the firewall, chrony and DNS settings, runs the
self-test and, if everything the nightly job needs is there (gate host key, notification channel,
disk), enables the timers. Otherwise it waits for `setup` on the serial console and the LED shows
a heartbeat.

On the serial console (`purser>` prompt), `setup` asks for: language, gate address and port,
sources (`KINDS`), first question time, end of the polling interval. Then:

1. It prints the `purser-admit` line to run on the server, with the box's address and key.
2. It shows the gate's host key fingerprint: compare it with what `purser-admit` printed.
3. Notification channel: an ntfy server (a random topic is generated); subscribe to it in the
   ntfy app; a test message is sent.
4. Disk: with no disk configured it offers to prepare a **new** disk: exactly one USB disk must be
   attached; type `ERASE`. It creates LUKS2 (AES-XTS or Adiantum after a benchmark) with a random
   key file and a **recovery passphrase that is shown once** (write it on paper, type its last
   four characters back), takes a LUKS header backup (`/etc/purser/sirlar/luks-baslik.img`; copy
   it to a USB stick for the paper pack), creates btrfs and the layout.
5. Operation code: shown once, write it on paper (not on the box), type it back.
6. Self-test.

A new disk then needs its first fill, without the window ceiling: `first-fill` (asks for the
code; runs in the background; follow it with `status`). After the first fill the nightly timer
is enabled. Check with `status` and `selftest`, and send a test with `notify-test`.

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
