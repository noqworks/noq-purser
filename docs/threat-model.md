# Threat model

[Türkçe](threat-model.tr.md)

Starting point: **the protected server is compromised.** An attacker has root on it, is patient
and competent. Defences that rely on the attacker being careless (decoy files, entropy, ransom
note names) are treated as signals, not as protection.

## What it protects against

| Situation | Result |
| --- | --- |
| Someone with root on the server deletes or encrypts the backups on the server | The history on the box stays |
| The server publishes broken content with valid hashes and `clean=yes` | The box keeps it but deletes nothing; old generations stay on schedule |
| The compromised server serves a malicious rsync stream or a malicious list | rsync runs in a sandbox and writes only into staging; list and tree are checked on the box; a generation that does not fit is rejected |
| A source silently stops producing backups | The server says `fresh=no` (warning); the box separately reports a source that has not changed for 2 nights |
| The server stops producing generations | The box reports "no generation" each night and the delay alarm after 30 hours; it does not depend on the server for that |
| The server forges generation dates to age history faster | Retention counts published nights; dates cannot accelerate deletion |

## What it does NOT protect against

| Situation | Why |
| --- | --- |
| **The box is compromised** | The box holds the disk key and the disk is attached to it. Whoever controls the box can unlock and erase the disk. There is one disk: the history is gone. The attack surface toward the server is the sandboxed rsync client. |
| **Fire, theft, seizure at the site** | Box and disk stand next to the server (same building or same site). Whatever destroys or removes both takes the history with it. A copy at another place is not part of this release. |
| **A patient attacker who produces bad backups for months** | The box keeps bad data faithfully. The only answer is long retention (12 months) and regular restore drills. Without drills NOQ Purser saves nobody. |
| **Lost disk passphrase or LUKS header** | Without the paper passphrase and the header backup there is no restore. |
| **Data that is not backed up** | The list of sources is the operator's responsibility. |
| **A person at the box** | The operation code is a deliberate lock, not a boundary: that person can take the box, the SD card or the disk. |
| **A USB-SATA bridge that lies about flushes** | Published generations are read-only and only metadata written at publish time ties them. If the bridge acknowledges writes it has not made, a power cut can damage the single disk. Use a bridge and disk you have tested. |

## Threats and answers

| Threat | Answer |
| --- | --- |
| Root on the server deletes the server's backups | The server has no delete right on the box; the box keeps the history |
| Fake "clean" verdict with broken data | A verdict grants nothing; long retention and pinned generations remain |
| Content changed with size, time and list hash kept | ctime difference after the sync plus re-read of every touched file: suspect |
| Mass deletion or mass encryption | Immutable files of the tool changed or deleted: suspect; large changes: suspect or warning |
| Malicious list line: path traversal, control character, duplicate path | Strict patterns on the box; generation rejected before the disk is unlocked |
| Malicious rsync: symlink, device, endless stream, huge file | `--no-links --no-specials --no-devices`, type scan, sandbox (unprivileged user, read-only system, no secrets, one writable path), per-file size ceiling, I/O timeout, runtime ceiling |
| Source stops silently | Freshness query on the server; 2 unchanged nights on the box |
| Repository changes during the pull | The generation is frozen on the server; otherwise the list does not match and the night does not count |
| Server tampers with acknowledgement files | Acknowledgements only steer the server's own clean-up; nothing on the box depends on them |
| Server stops producing generations | Box waits in its window, then notifies; delay alarm after 30 h |
| Server silences alarms | The box's notifications do not pass through the server |
| Server forges generation dates | Retention counts nights; ids more than an hour in the future are not taken |
| Local NTP is taken over to shift the clock | chrony refuses changes over 10 minutes after its first updates; a jump against the monotonic clock, disagreement with network time or a clock earlier than the image date stops the night and is notified; retention does not depend on the clock |
| Notification address changes | Resolved again before every send; only that address is allowed out on 443 |
| Server tries to inject text into a notification | Notifications contain only core-generated state; `note=` and file names are never shown |
| The box is stolen | Disk encrypted, but the key is in the box: protection is the sources' own encryption (borg/restic repokey, pgBackRest `repo-cipher-type`). Revoke the box key on the server (`purser-admit --revoke`) and the notification topic |
| Power cut while writing | Published generations are read-only; staging is rebuilt next night; see the bridge row above |
| LUKS header damaged | Header backup taken at setup (keep it off the box, next to the paper pack) |
| Hung USB-SATA bridge | One software reset of the USB device (authorized 0/1, else unbind/bind); still missing → urgent notification. There is no power switch; a person has to re-plug the cable |
| Repository or release compromised | The box never fetches code; it is updated only by replacing the SD card with a scripted image whose sha256 you can check. Release signing is not part of this release |

## Clock without a battery

The board has no battery-backed clock. At boot the clock is taken from the network once (chrony's
first updates). A local attacker who controls NTP at exactly that moment can start the box with a
wrong clock. The consequences are bounded: retention does not use the clock; generation ids more
than an hour ahead of the box clock are refused; the code lock wait and the delay alarm may be
off. A clock earlier than the image build date is detected.

## Always-attached disk

The disk is never switched off; outside the window it is locked (LUKS closed) and not mounted.
A separate power switch would not add protection, because the box would drive it. The disk is
powered around the clock: an SSD is the recommended disk.

## Why the box is small

The core is a few thousand lines of Bash that can be read in a sitting. "Readable" is one claim;
"defended against hostile input" is another and rests on the strict list patterns, the sandbox
and the separation of privileges, not on the size of the code.

| Step | Runs as | Can write | Can read |
| --- | --- | --- | --- |
| List fetch, sync | `purser-rsync`, systemd sandbox, network | only the scratch area / staging | staging and its SSH key |
| List check, tree check, hashing | `purser-dogrula`, sandbox, no network | nothing | staging, lists |
| Pruning long copies | `purser-rsync`, sandbox, no network | only the copy being pruned | that copy |
| Publish, retention, lock, ack | root | snapshot properties and the state area | everything; it does not walk the trees |

The secrets (`/etc/purser/sirlar`) and the state area are inaccessible inside every sandbox.
