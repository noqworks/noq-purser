# How NOQ Purser works

[Türkçe](design.tr.md)

This document describes release 1.0 as it is implemented. Names, numbers and dates in the
examples are made up.

## Three claims

Assume your server has been taken over. NOQ Purser rests on three things, not on the attacker
being careless:

1. **The box has no listening port.** The box always opens the connection; the server cannot
   reach the box.
2. **The server cannot delete history.** Only the box deletes, on its own schedule. Nothing the
   server says grants deletion.
3. **The box does not trust the server.** It checks everything the server sends (list, file
   names, file types, content) and draws warnings and suspicion from its own signals. A "clean"
   verdict from the server can only make the box more careful.

## Who does what

| Part | Does | Cannot |
| --- | --- | --- |
| Server (`purser-source`) | When the night's backup jobs are done: freezes a generation, asks each source whether it is fresh, writes the file list, keeps the generation until the box acknowledges it | Connect to the box; delete anything on the box |
| Gate (`purser-gate`) | SSH forced command for the box key: `latest`, read-only `rsync`, `ack <id> [verdict]` | Anything else (refused and logged) |
| Box (`purser`) | Fetches, checks, verifies, publishes, applies retention, locks the disk again, acknowledges, sends alarms | Write on the server, except its acknowledgement |
| Serial console (`purser-console`) | Passes fixed commands to the core | Decide anything, grant anything, show server text |
| Person | Restore drills, pins a restored generation, clears a suspect at the box, keeps the paper pack | — |

## The night, server side (`purser-source`)

1. **Wait.** It starts from a timer (default 04:30) and then waits for dependencies, not the
   clock: every unit in `WAIT_UNITS` whose timer is enabled must have run tonight and finished,
   and the tools' locks (pgBackRest backup/expire, borg `lock.*`, restic `locks/`) must be gone.
   If that takes longer than `WAIT_MAX_MIN` (240), no generation is produced tonight; the box
   reports "no generation".
2. **Pre-freeze commands** (`PRE_FREEZE_CMDS`, optional), e.g. `pgbackrest check` to switch WAL.
3. **Freeze** each source into `generation/.build-<id>/<name>/`. `FREEZE=auto` tries a reflink
   copy (XFS, btrfs: one second, no extra space), then hard links (same file system; fine for
   repositories that never rewrite a file in place), then a full copy. Temporary and lock files of
   the tools are removed from the frozen copy. Names outside `A-Z a-z 0-9 . _ / + -` and anything
   that is not a file or directory stop the run.
4. **List**: only new or changed (size or mtime) files are hashed again, the rest is taken from
   the previous run's cache.
5. **Freshness** per source: pgBackRest newest backup label, borg newest segment, restic newest
   snapshot, plain directory newest file (or `FRESH_CMDS`). Older than `FRESH_MAX_H` (26 h) →
   `fresh=no` with a note. Staleness is a warning, not suspicion.
6. **Verification** on the frozen copy (`VERIFY_CMDS`, optional, e.g. `pgbackrest verify`,
   `restic check`). Any failure → `clean=no`.
7. **Publish**: `generation/<id>/`, `generation/<id>.list`, `generation/LATEST`.
8. **Ceiling**: the last acknowledged generation and the newest `KEEP_UNACKED` (3) others are
   kept, the rest removed. The server does not grow while the box is away.

`purser-source watch` (hourly, optional alerts through `ALERT_CMD`): no acknowledgement for
`ACK_ALERT_H` (30) hours, and a box connection outside `BOX_WINDOW_START`–`BOX_WINDOW_END`.
These alerts are a convenience: a compromised server can silence them. The box's own channel
does not pass through the server.

## The list

```
# purser-list 1
# generation=2026-01-14T03-10Z
# created=2026-01-14T03:11:52Z
# clean=yes
# fresh=yes
# note=pgbackrest verify ok
3f2a…e91c  pgbackrest/backup/demo/20260111-021500F/backup.manifest
…
```

- `sha256sum` format below `#` header lines. No JSON parser on the box.
- The first line is exactly `# purser-list 1`. `generation`, `clean` (`yes|no|unknown`) and
  `fresh` (`yes|no`) are required. The list is the complete tree, so deletions are visible.
- The box enforces (`purser-verify list`): header lines `^# [a-z_]+=[A-Za-z0-9:._;, -]{0,200}$`;
  file lines `^[0-9a-f]{64}  [A-Za-z0-9._/+-]+$`, at most 1024 characters of path; no leading
  `/`, no `.` or `..` component, no empty component, no trailing `/`, no duplicate path, no path
  that is also a directory of another path. One bad line rejects the generation.
- `note=` is never shown in a notification; it goes to the log only.

## The gate

The box has one key on the server, in a separate sshd (`purser-sshd`, its own port, address and
host key; the main sshd is not touched):

```
from="192.0.2.20",restrict,command="/usr/local/sbin/purser-gate" ssh-ed25519 AAAA… purser
```

| Request | Effect |
| --- | --- |
| `latest` | prints the newest published generation id |
| `rsync --server --sender …` | `rrsync -ro generation/` |
| `ack <id> [tamam\|uyari\|supheli]` | writes `ack/<id>` with the verdict and time; the id format and existence are checked |

Everything else is refused and logged. The verdict words are part of the protocol and stay as
they are (`tamam` = ok, `uyari` = warning, `supheli` = suspect).

## The night, box side (`purser run`)

The disk is attached all the time and stays **locked** (LUKS closed, not mounted) outside the
window.

1. **Clock gate.** If the clock cannot be trusted (see "Clock"), nothing is taken tonight, the
   server is not even asked, a notification goes out.
2. **Pending acknowledgement** from an earlier window is sent first. That is not success.
3. **New generation, disk locked.** `latest` is asked every `POLL_EVERY` (5 min) until
   `POLL_UNTIL` (08:30). The id must be newer than the last published one and not more than an
   hour in the future. Nothing arrives → "the server produced no generation tonight"; the disk is
   never unlocked.
4. **List check, disk locked.** The list is fetched into the SD card's scratch area and checked
   (above). A rejected generation never unlocks the disk.
5. **Disk.** Find the USB device by its LUKS UUID; if it is missing or does not answer a small
   read, reset the USB bridge in software once (de-authorize/re-authorize, else unbind/bind) and
   wait again; still nothing → urgent notification. Then LUKS open, mount.
6. **Staging**: a writable btrfs snapshot of the last published generation. A half-filled
   staging area from an earlier night is kept and completed. The box always goes to the newest
   generation.
7. **Sync**: rsync in the sandbox writes only into staging, `--delete --no-links --no-specials
   --no-devices`, per-file size ceiling, I/O timeout, window ceiling. Its output is not parsed.
   Then anything in staging that is not a plain file or directory rejects the generation, and the
   tree must hold exactly the listed files.
8. **What changed**, from two sources: the list difference (new or other hash), and every file
   whose ctime is newer than a mark set before the sync (`find -cnewer`). rsync cannot keep a
   ctime, so a server that keeps size, mtime and the old hash while changing content is caught.
9. **Verification**: every changed file is read back from disk and hashed. A file whose list hash
   is unchanged but whose content changed → `list_hash_lie` (suspect; the stored list records
   the real hash). A list hash that changed while nothing was transferred is pulled again with
   `--checksum`; if the content then differs, it was a silent change (suspect). Other mismatches
   fail the night.
10. **Signals** (below).
11. **Publish**: audit files are written as `.pending`, then the read-only snapshot
    `nesil/gen-<id>`, then the audit files are renamed. A power cut in between is finished or
    rolled back on the next run.
12. **Long retention**: on the long-retention day (see "Retention") a writable copy is pruned in
    the sandbox and made read-only as `nesil/uzun-<id>`.
13. **Retention, maintenance**, then **lock the disk**: sync, unmount, LUKS close; the box checks
    that no mapper device and no mount remain, otherwise urgent notification.
14. **Acknowledge** `ack <id> <verdict>`. If that fails it is kept as pending.
15. **Alarm** if needed. A quiet night is a good night.

Success means: a new generation was checked, verified, published and the disk was locked again.
A re-run, a pending acknowledgement or a partial transfer is not success.

The window ceiling is `MAX_MIN` (80 minutes): no new work after it, a half-filled staging area
waits for the next night. `first-fill` (at the console) has no ceiling.

## Signals

| Level | When | Effect |
| --- | --- | --- |
| **Warning** | server says `fresh=no`; the transfer is above `WARN_FACTOR` (3) × the median of the same weekday over the last 4 weeks; a source has not changed for `STALE_NIGHTS` (2) nights; the newest pgBackRest label is older than `LABEL_MAX_DAYS` (2) days | notification, LED leaves "ok", deletion continues |
| **Suspect** | server says `clean=no`; a file that never changes did change; a deletion outside the normal cleanup; a list hash that lies; a silent change; mass deletion or mass change (≥ 50 % and ≥ 20 files) | generation kept and flagged, automatic deletion stops |

Rules per source type (`KINDS="type:dir[:prune days]"` in `purser.conf`):

- **pgBackRest**: files under a backup label directory and WAL segments never change. Normal
  cleanup removes a whole label directory or the oldest segments, and only on a prune day.
  Deleting single files inside a label, deleting from the middle of the archive, or deleting on
  another day is suspect. The info files are encrypted; the rules use file names only.
- **borg**: segments under `data/` never change (compact writes new ones and deletes old ones);
  deleting segments is allowed only on a prune day.
- **restic**: objects in `data/ index/ snapshots/ keys/` never change and are named after the
  SHA-256 of their content (checked); deletion only on a prune day.
- **dir**: no immutable pattern; mass rules and stale-source rule apply.

These signals catch a careless attacker. They are not the security claim: a capable attacker can
avoid all of them. The answer to that is retention and restore drills.

### Suspect generation

- The **last sound generation** is the one before the first suspect that has not been cleared.
  Later ones are not sound either: bad data may have travelled on. The delay alarm and the LED
  work from the last sound generation.
- **Automatic deletion stops** until a person clears the suspect at the box (`clear <id>`, with
  the operation code; the reason is shown first). Every night the box reports how many days
  deletion has been paused.
- **Disk full while paused**: nothing old is deleted, no new generation is taken, a notification
  goes out every night. Old history is what must be kept.

## Retention

- 14 daily, 8 weekly, 12 monthly generations (`KEEP_DAILY`, `KEEP_WEEKLY`, `KEEP_MONTHLY`).
- Weekly copies are cut from the first generation on or after `LONG_DOW` (7 = Sunday) of each
  week, the day of the weekly full backup. Monthly copies are the first weekly copy of a month.
- **Retention counts nights, never trusts a date.** Generation ids come from the server and the
  box clock from the network; both could lie. A weekly cut also needs `LONG_MIN_NIGHTS` (4)
  published generations since the previous cut, a monthly pick `MONTHLY_MIN_WEEKS` (3) weekly
  cuts since the previous pick, and the box publishes at most one generation per night. Forged
  dates can make the box keep history longer, never delete it faster.
- **Pruning of long copies**: weekly and monthly pgBackRest copies keep only the newest full
  backup and the info files; WAL and differential backups are removed (in the sandbox, in a
  separate writable snapshot). With `archive-copy=y` the full backup carries the WAL it needs;
  restore it with `--type=none`. borg, restic and plain directories are kept as they are.
- Pinned generations (`pin <id>`) are never deleted automatically. The newest daily generation is
  never deleted.
- **Disk full**: with no suspect, only the oldest daily generations are deleted until
  `DISK_MIN_FREE_PCT` (10 %) is free; weekly, monthly, pinned and the newest daily are never
  deleted this way. With a suspect: nothing is deleted, no new generation.

Rough disk size:

```
full backup × (weekly + monthly copies)
+ one week of changes × 3
+ borg/restic repositories × 1.5
```

## Clock

The board has no battery-backed clock. Time comes from the network (chrony; `NTP_SERVERS`,
e.g. the router, and `NTP_POOL`), never from the protected server.

- At boot chrony may step the clock during its first updates; after that it refuses any change
  larger than `CLOCK_JUMP_MAX` (600 s).
- The clock is **trusted** only when chrony is synchronised, network time agrees with the box
  clock, the clock has not jumped against the monotonic clock within the last hour, and it is
  not earlier than the image build date.
- Untrusted clock → no generation tonight, the server is not asked, the disk stays locked, a
  notification (at most once a day per kind). The delay alarm is not sent on an untrusted clock.

## Network

nftables drops everything incoming (only DHCP replies and replies to the box's own connections).
Out, only: the server gate (one address, one port), the two configured DNS resolvers
(`DNS_SERVERS`; not the local network's resolver, which may be the server), NTP, DHCP, and HTTPS
to the notification host. The notification host is resolved again before every send and the
nftables set refreshed. Maintenance SSH exists only when `MAINT_SSH_FROM` is set (key only, from
that address). There is no rule for package downloads: after installation the box cannot fetch
code or packages. Wi-Fi and Bluetooth modules are blacklisted; wired only.

## Notifications

Only alarms (everything except "done"; "done" goes to the log and to the server as the
acknowledgement). Channel: `curl` to ntfy (default; your own ntfy server or ntfy.sh) or a plain
webhook POST. The address and token live in `/etc/purser/sirlar/bildirim` (root only). Messages
carry only state the core produced (catalog text, numbers, generation ids, reason codes); never a
file name, path, note or content from the server. Undeliverable notifications are queued and
retried hourly (newest 50). Language: `LANG_UI=en|tr`.

## At the box

There is no screen and no button. The state is in `status` (serial console), in notifications
and on the board LED. The serial console runs the restricted `purser-console` instead of a login:

| Command | Code | Does |
| --- | --- | --- |
| `status` | no | last sound generation and its age, last night's result, suspect reason, deletion pause, pending ack, disk usage, SMART summary, last scrub, image age, disk locked/open, clock |
| `clear <id>` | yes | shows why `<id>` is suspect, then clears it (type `CLEAR`) |
| `pin <id>` | yes | pins a generation (e.g. one whose restore was tested) |
| `disk-on` | yes | unlocks and mounts the disk by hand; locks again after `DISK_ON_MIN` (30) minutes |
| `disk-off` | no | locks the disk |
| `first-fill` | yes | first fill without the window ceiling, in the background |
| `selftest` | yes once a code exists | disk on USB, link speed, SMART, network, clock |
| `setup` | yes after setup | setup wizard |
| `setup-code` | no (only if none set) | creates the first operation code |
| `new-code` | yes | new operation code |
| `reset-code` | no | new code without the old one; **always notified** |
| `notify-test` | no | test notification |
| `shell` | yes | maintenance shell; **always notified** |

**Operation code**: 12 digits in three groups (`4821 0937 5562`), the last digit a Damm check
digit (catches every single-digit error and every swap of two adjacent digits; a typo is not
counted as a wrong attempt). The box generates it, shows it once, asks for it back and stores
only an argon2id hash on the SD card. Three wrong entries start a wait that doubles each time,
1 minute up to 24 hours; a reboot does not reset it; the lock is notified. It is a deliberate
lock, not a security boundary: whoever stands at the box can also carry it away. The code never
crosses the network. The console passes the digits to the core and does not store them.

**Two keys on paper, never mixed:**

| | Disk recovery passphrase | Operation code |
| --- | --- | --- |
| Use | opens the disk on another machine | confirms commands at the box |
| Entered | into a computer, at a restore | into the serial console |
| Strength | long; protects a stolen disk | short; a deliberate lock |
| Lost | no restore | make a new one; data unaffected |

The disk passphrase is never entered into the box.

## Maintenance (inside the window, in the time left)

- SMART once a month (`smartctl -d sat` through the bridge).
- btrfs scrub, resumed window by window, one full pass a month.
- A slice of the full hash scan of files that did not change, cursor on the SD card (about one
  round a month, depending on size).

## The SD card

A single root file system (the Armbian image). State and secrets are separate directories:

| Path | Holds |
| --- | --- |
| `/etc/purser/purser.conf` | configuration (no secrets) |
| `/etc/purser/sirlar/` | LUKS key file, LUKS header backup, notification address (root only) |
| `/etc/purser/ssh/` | the box's SSH key (owned by the rsync user) and the gate's host key |
| `/var/lib/purser/` | state: last published / last sound generation, pending ack, last list, signal history, code hash and lock counter, notification queue, maintenance cursors |

On-disk names (`nesil/gen-*`, `nesil/uzun-*`, `denetim/{liste,meta,supheli,temiz,pin}`,
`hazirlik`) and state file names predate the English code base. They are part of the format and
do not change.

**Updating** is replacing the SD card with a newly built image and moving the state over
(`image/purser-card-migrate`); the box never updates itself. After 6 months the box asks for a new
image.

## Not in this release

Read-only root file system and a separate state partition; btrfs quota on staging (the ceilings
are per-file size, I/O timeout and runtime); remote installation over WireGuard; signed releases;
FIDO keys; a printable case. They are not claimed anywhere in this repository.
