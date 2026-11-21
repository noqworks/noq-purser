# Hardware

[Türkçe](hardware.tr.md)

The box is three parts. Nothing is soldered, cut or wired.

| Part | Reference | Notes |
| --- | --- | --- |
| Board | Orange Pi Zero 3 (Allwinner H618, 1 GB RAM or more, gigabit Ethernet) | The image in `image/` is built for this board. The software itself is Bash on Debian and runs on other boards too, with your own image. |
| Cable | An ordinary USB-SATA cable or adapter for 2.5" drives, unmodified, in the board's USB-A port | It powers the drive from USB. It should pass SMART through (SAT); the self-test checks that. |
| Disk | 2.5" SATA SSD | The disk is powered around the clock; an SSD is recommended. Size: see "Rough disk size" in [design.md](design.md). |

What you also need, but is not part of the box:

- a microSD card (16 GB or more; an industrial/high-endurance card is a good idea),
- a USB-C power supply, 5 V / 3 A (the board feeds the drive through its USB-A port),
- an Ethernet cable (the box is wired only; Wi-Fi and Bluetooth are switched off),
- for setup and for the commands at the box: a 3.3 V USB-serial adapter on the board's debug
  UART (GND, RX, TX; 115200 baud). If your board has no pins there, use a clip or spring-contact
  probe instead of soldering. With an embedded `setup.conf` the console is needed only for a new
  disk (its recovery passphrase is shown once) and for the operation code.

```
USB-C 5 V / 3 A ──► Orange Pi Zero 3 ──USB-A──► USB-SATA cable ──► 2.5" SSD
                        │
                        ├── Ethernet ──► your network (wired)
                        └── debug UART ──► USB-serial adapter (only while you work at the box)
```

## Indicators

There is no screen and no button. If the board has its own LED (`/sys/class/leds`, e.g.
`green:status`) the box uses it (`BOARD_LED=auto`; `none` turns it off):

| LED | Meaning |
| --- | --- |
| steady on | last sound generation newer than 30 h, no warning, no suspect |
| slow blink | warning: delay, no generation, partial night, untrusted clock |
| fast blink | suspect generation, rejected generation, disk or verification error |
| heartbeat | not set up yet, or no sound generation yet |

The real state is in `status` on the serial console and in the notifications.

## What the box does to the disk

- The disk stays attached. Outside the nightly window it is **locked**: the LUKS volume is closed
  and nothing is mounted. `status` shows "Disk now: locked".
- If the USB-SATA bridge hangs (the disk is not visible or does not answer), the box resets the
  USB device in software once (de-authorize and re-authorize, otherwise unbind and bind). If that
  does not bring it back, it sends an urgent notification; then someone has to re-plug the cable.
- Self-test (`selftest`): disk visible on USB, link speed (480 Mbit/s or more), SMART readable
  through the bridge, network (default route, the gate's port answers), clock synchronised.

## Measure on your own desk

- Link speed and throughput: USB 2.0 gives roughly 35–40 MB/s; the first fill of a few hundred GB
  takes hours (use `first-fill`).
- `cryptsetup benchmark`: setup picks AES-XTS when it is fast enough, otherwise Adiantum.
- Power cut while writing: pull the plug during a night a few times, then check that btrfs mounts
  and published generations read back (`selftest`, a restore drill). This is where you learn
  whether the bridge reports flushes honestly.
