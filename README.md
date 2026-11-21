# NOQ Purser

[Türkçe](README.tr.md)

A small box next to your server that takes the backups off it every night and keeps their
history where the server cannot reach it.

The box (an Orange Pi Zero 3, a USB-SATA cable, a disk) has no listening port. Every night it
connects to the server, pulls the night's frozen backup generation through a restricted SSH gate,
checks every file against a list, keeps 14 daily, 8 weekly and 12 monthly generations on its
encrypted disk, and locks the disk again. Only the box deletes history, on its own schedule; the
server can neither reach the box nor tell it to delete anything.

## What it does

- **Server side** (`source/`): `purser-source` waits until the night's backup jobs are done,
  freezes the backup repositories (reflink, hard links or copy), writes a hashed file list, asks
  each source whether it is fresh and runs your verification commands. `purser-gate` is the only
  thing the box can talk to: `latest`, read-only rsync, `ack`.
- **Box** (`box/`): pulls the newest generation into a btrfs snapshot inside a sandbox, rejects
  anything that does not fit the list, re-reads every changed file, derives warnings and suspicion
  from its own signals (immutable files of pgBackRest / borg / restic, deletions outside the
  prune day, mass changes, silent changes, stale sources), publishes read-only snapshots, applies
  retention and sends alarms (ntfy or webhook) that never pass through the server.
- **At the box**: a restricted serial console with fixed commands; the ones that change something
  ask for a 12-digit operation code.
- **Image** (`image/`): a script that builds the box's SD card image from a pinned Armbian release
  with everything preinstalled; the box never fetches code or packages.

Supported sources: pgBackRest, borg, restic, plain directories.

## What it does not protect against

- **The box being compromised.** The box holds the disk key and the disk is attached to it.
  Whoever controls the box can erase the history. There is a single disk.
- **Fire, theft or seizure at the same site.** The box stands next to the server.
- **A patient attacker who produces bad backups for months.** The box keeps them faithfully. The
  answer is long retention and restore drills.
- **Lost disk passphrase or LUKS header**, and data you do not back up.

The full list is in [docs/threat-model.md](docs/threat-model.md).

## Status

Release 1.0. The test suite runs without hardware (`tests/run.sh`): unit, end-to-end night with a
real gate and a real btrfs, attack scenarios, compatibility with disks and SD cards written by
the prototype, server installation on Debian 13, Ubuntu 24.04 and Ubuntu 26.04.

**A restore drill with this release has not been done yet.** Until it has, treat NOQ Purser as
untested for restores. A backup whose restore has never been tried is not a backup.

## Documents

| | |
| --- | --- |
| [docs/install.md](docs/install.md) | Server side, box image, first boot, moving an SD card |
| [docs/hardware.md](docs/hardware.md) | Board, cable, disk; LED; what the box does to the disk |
| [docs/design.md](docs/design.md) | How it works: the night, the list, the gate, signals, retention, clock, network, the console |
| [docs/threat-model.md](docs/threat-model.md) | What it protects against and what not |
| [docs/restore.md](docs/restore.md) | Restoring on a clean machine |
| [CHANGELOG.md](CHANGELOG.md) | Changes |

## Repository

```
source/   server side: purser-source, purser-gate, purser-admit, install.sh, examples
box/      box core (Bash), restricted console, verifier, systemd units, templates, messages (en, tr)
image/    image build, SD card flashing, card migration
tests/    hardware-free test suite (Docker)
docs/     documentation (en, tr)
```

Bash and distribution packages only. License: GPL-3.0-or-later ([LICENSE](LICENSE)).
