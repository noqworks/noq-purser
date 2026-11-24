# NOQ Purser

[Türkçe](README.tr.md)

A small box on the same network as your server, in another room or building, that takes the backups off it
every night and keeps their history where the server cannot reach it.

**Version 1.1.1 · Verified** (restore drill passed). Download and step-by-step guide:
<https://open.noq.works/projects/purser/>

The box (an Orange Pi Zero 3, a bare USB-SATA bridge, a 2.5" SSD, an LED stick and a maintenance
switch) listens on no port while the switch is off. Every night it connects to the server, pulls
the night's frozen backup generation through a restricted SSH gate, checks every file against a
list, keeps 14 daily, 8 weekly and 12 monthly generations on its encrypted disk and locks the disk
again. Only the box deletes history, on its own schedule; the server can neither reach the box nor
tell it to delete anything.

## Install in four steps

1. **Server** (Debian/Ubuntu with systemd): download `noq-purser-server-1.1.1.tar.gz`, then
   `sudo ./install.sh` and list your backup repositories in
   `/etc/purser/source.conf`.
2. **Computer** (macOS or Linux): run the card tool, in Terminal
   `bash <(curl -fsSL https://open.noq.works/files/purser/purser-setup)`
   or from `noq-purser-setup-1.1.1.tar.gz` (on a Mac, double-click `purser-setup.command`). It
   downloads the box image and checks it, lists the SD cards, asks a few questions, writes the card
   and shows the 12-digit operation code and the disk recovery passphrase **once**: write them on paper.
3. **Box**: card, disk, Ethernet, power. The first boot prepares the disk (cyan); a dot at each end
   of the stick means it waits to be paired.
4. **Pair**: `sudo purser pair` on the server prints a QR code. Switch maintenance on (purple), open
   `https://<id>.local` on your phone, tap Pair, scan the code, switch maintenance off.

Details: [docs/install.md](docs/install.md).

## What it does

- **Server side** (`source/`): `purser-source` waits until the night's backup jobs are done,
  freezes the backup repositories (reflink, hard links or copy), writes a hashed file list, asks
  each source whether it is fresh and runs your verification commands. `purser-gate` is the only
  thing the box can talk to: `latest`, read-only rsync, `ack`, `note`. `purser pair` admits a box
  with a one-time QR code.
- **Box** (`box/`): pulls the newest generation into a btrfs snapshot inside a sandbox, rejects
  anything that does not fit the list, re-reads every changed file, derives warnings and suspicion
  from its own signals (immutable files of pgBackRest / borg / restic, deletions outside the
  prune day, mass changes, silent changes, stale sources), publishes read-only snapshots and
  applies retention.
- **Alarms** go back through the same gate (`note <event>`, a fixed alphabet); the server raises them
  with your own command (`ALERT_CMD`). No third-party service, no internet.
- **At the box**: an 8-LED stick shows the state; a maintenance switch opens, only while it is on, a
  page on `https://<id>.local` (pairing, state, actions behind the operation code) and SSH with
  your key. Off closes everything.
- **Clock**: network time from your router, or an optional DS3231 battery clock (set once from your
  phone while pairing).
- **Image** (`image/`): builds the SD card image from a pinned Armbian release with everything
  preinstalled; the box never fetches code or packages. `image/purser-setup` prepares a card.

Supported sources: pgBackRest, borg, restic, plain directories.

## What it does not protect against

- **The box being compromised.** The box holds the disk key and the disk is attached to it.
  Whoever controls the box can erase the history. There is a single disk.
- **Fire, theft or seizure at the same site.** If the box is in the same building as the server, one event can
  take both. Put it in another room, ideally another building.
- **A patient attacker who produces bad backups for months.** The box keeps them faithfully. The
  answer is long retention and restore drills.
- **Lost disk passphrase or LUKS header**, and data you do not back up.

The full list is in [docs/threat-model.md](docs/threat-model.md).

## Status

1.1.1, verified on our own box. The test suite runs without hardware (`tests/run.sh`): unit,
end-to-end night with a real gate and a real btrfs, attack scenarios, compatibility with disks and
SD cards written by the prototype; image tools (`tests/run.sh --image-tools`).

**Restore drill passed (24 Nov 2026).** A generation taken by the box was opened read-only and
restored in an isolated container with no network: PostgreSQL (pgBackRest) restored, recovered and
opened writable; the last borg archive opened and the extracted files were identical to the live
system. Run your own drill every three months and after every change to your sources: a backup
whose restore has never been tried is not a backup.

## Documents

| | |
| --- | --- |
| [docs/install.md](docs/install.md) | Server, card, first boot, pairing, moving an SD card |
| [docs/hardware.md](docs/hardware.md) | Parts, wiring, lights; what the box does to the disk |
| [docs/design.md](docs/design.md) | How it works: the night, the list, the gate, signals, retention, clock, network, at the box |
| [docs/threat-model.md](docs/threat-model.md) | What it protects against and what not |
| [docs/restore.md](docs/restore.md) | Restoring on a clean machine |
| [CHANGELOG.md](CHANGELOG.md) | Changes |

## Repository

```
source/   server side: purser-source, purser-gate, purser-admit, purser-pair, purser, install.sh
box/      box core (Bash), page (purser-ui, ui/), light, maintenance switch, units, messages (en, tr)
image/    image build, purser-setup (card), flash.sh, card migration, release.sh
tests/    hardware-free test suite (Docker)
docs/     documentation (en, tr)
```

Bash, Python standard library and distribution packages only. License: GPL-3.0-or-later ([LICENSE](LICENSE)).
