# Restore

[Türkçe](restore.tr.md)

A backup whose restore has never been tried is not a backup. Do a drill every three months, and
after every change to the sources.

**Status of this release:** the restore steps below follow from the on-disk format and the tools'
own documentation and were drilled on our own box on 24 Nov 2026: PostgreSQL (pgBackRest) and borg opened.

You need: the disk, a clean Linux machine that has no access to the protected server (a laptop or
a VM with the network off), the paper pack (disk recovery passphrase, the tools' passphrases and
keys) and, if the LUKS header is damaged, the header backup (`luks-baslik.img`). The box itself is
not needed.

## 1. Open the disk read-only

```sh
lsblk -o NAME,SIZE,MODEL,TRAN                     # find the USB disk, e.g. /dev/sdX
# only if the LUKS header is damaged:
cryptsetup luksHeaderRestore /dev/sdX --header-backup-file luks-baslik.img
cryptsetup open --readonly /dev/sdX purser-restore   # asks for the recovery passphrase
mkdir -p /mnt/purser && mount -o ro /dev/mapper/purser-restore /mnt/purser
```

## 2. Choose a generation

```sh
ls /mnt/purser/nesil/            # gen-<id>: daily, uzun-<id>: weekly/monthly (pruned)
ls /mnt/purser/denetim/supheli/  # suspect generations ...
ls /mnt/purser/denetim/temiz/    # ... and the ones cleared at the box
cat /mnt/purser/denetim/meta/<id>          # bytes, files, seconds, warnings, suspicion
```

Prefer the newest generation that is not suspect, or older than the first uncleared suspect.
Check it against its list before you use it:

```sh
cd /mnt/purser/nesil/gen-<id>
grep -v '^#' /mnt/purser/denetim/liste/<id>.list | sha256sum --quiet -c
# a pruned long-retention copy holds a subset of the list:
cd /mnt/purser/nesil/uzun-<id>
grep -v '^#' /mnt/purser/denetim/liste/<id>.list | sha256sum --quiet -c --ignore-missing
```

## 3. Restore with the tool

Copy the repository you need to writable scratch space first (the disk stays read-only):

```sh
cp -a /mnt/purser/nesil/gen-<id>/<source> /restore/repo
```

- **pgBackRest**: point a pgBackRest configuration at the copy (`repo1-path=/restore/repo`, the
  stanza name and `repo1-cipher-pass` from the paper pack), then
  `pgbackrest --stanza=<stanza> restore`. A weekly/monthly copy (`uzun-<id>`) has no WAL archive:
  restore it with `--type=none` (it needs `archive-copy=y`, which carries the WAL of the full
  backup inside it). pgBackRest warns that the timeline does not advance; for a drill that is
  expected. `--type=immediate` is another option to try.
- **borg**: `borg list /restore/repo`, then `borg extract /restore/repo::<archive>` (passphrase
  or key export from the paper pack).
- **restic**: `restic -r /restore/repo snapshots`, then
  `restic -r /restore/repo restore <snapshot> --target /restore/out`.
- **dir**: the files are plain copies.

Then check something you know: the content of a file, the result of a query.

## 4. Pin what worked

A generation whose restore worked should never be deleted automatically:

- at the box: `pin <id>` on the serial console (asks for the operation code), or
- on the restore machine, with the disk mounted read-write: `touch /mnt/purser/denetim/pin/<id>`.
  The box reads it in its next window.

## 5. Close

```sh
umount /mnt/purser && cryptsetup close purser-restore
```

Put the disk back on the box. The box finds it by its LUKS UUID; nothing else to do.

## Layout of the disk

```
nesil/gen-<id>           read-only btrfs snapshot, one per night
nesil/uzun-<id>          read-only weekly/monthly copy (pgBackRest pruned to the newest full)
denetim/liste/<id>.list  the list of the generation as verified by the box (real hashes)
denetim/meta/<id>        bayt= dosya= sure= uyari= suphe=
denetim/supheli/<id>     reason codes of a suspect generation
denetim/temiz/<id>       the suspect was cleared at the box
denetim/pin/<id>         pinned
hazirlik                 staging (may be half-filled; never restore from it)
```
