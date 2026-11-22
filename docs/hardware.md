# Hardware

[Türkçe](hardware.tr.md)

## Parts

| Part | Qty | Note |
| --- | --- | --- |
| Orange Pi Zero 3 | 1 | 1 GB of memory is enough. Wi-Fi is not used. |
| 2.5" SATA SSD | 1 | At least twice the total size of your backups. We used 4 TB and took the board out of its case to save space. |
| USB-SATA bridge board | 1 | The board inside an ordinary USB-SATA cable. The cable is cut and the wires are soldered straight to the board. |
| microSD card | 1 | 8 GB or larger. |
| 5 V 3 A USB-C power adapter | 1 | A computer's USB port is not enough; the disk draws a high current when it first starts. |
| Ethernet cable | 1 |  |
| 8-LED addressable stick | 1 | WS2812 or SK6812. The four-colour (RGBW) kind works too; you choose it during setup. |
| Toggle switch (SPST) | 1 | Two wires, 6 mm neck. The maintenance switch. |
| DS3231 clock module (optional) | 1 | Fit it when your router has no time server. On the ZS-042 board remove R4 (201), which charges the cell; a CR2032 must not be charged. |

No relay, safety key or button; we tried them and took them out. Time comes one of two ways: your router's time server (NTP) or a battery clock module. If you cannot set up the router, fit the module.

## Wiring

Pin numbers come from the official Orange Pi Zero 3 v1.2 pinout. The disk wires are verified on the bench; the light and switch tests are next. Pin 1 is the square solder pad on both headers.

| Wire | Goes to | Note |
| --- | --- | --- |
| Disk · red 1 | 13-pin header, pin 1 (5 V) | Power for the bridge board |
| Disk · black 1 | 13-pin header, pin 2 (GND) |  |
| Disk · white (D−) | 13-pin header, pin 3 (USB2 D−) | Keep the data wires short and close together |
| Disk · green (D+) | 13-pin header, pin 4 (USB2 D+) |  |
| Disk · red 2 | 26-pin header, pin 4 (5 V) | Extra supply, so the disk current is not carried by a single pin |
| Disk · black 2 | 26-pin header, pin 9 (GND) |  |
| LED · 5 V | 26-pin header, pin 2 (5 V) |  |
| LED · GND | 26-pin header, pin 6 (GND) |  |
| LED · DIN | 26-pin header, pin 19 (MOSI) | The stick's input end; DOUT stays free |
| Switch · lead 1 | 26-pin header, pin 12 (PC11) |  |
| Switch · lead 2 | 26-pin header, pin 14 (GND) | Contact closed means maintenance on |
| Clock · VCC | 26-pin header, pin 1 (3.3 V) | Not 5 V; the module pulls I²C up to this voltage |
| Clock · SDA | 26-pin header, pin 3 (I²C3 SDA, PH5) |  |
| Clock · SCL | 26-pin header, pin 5 (I²C3 SCL, PH4) |  |
| Clock · GND | 26-pin header, pin 25 (GND) | Pin 9 carries the disk's extra ground; 20 works too |

1. **Take out the bridge board.** Open the housing of the USB-SATA cable, take out the board and desolder the USB cable. Four solder pads for USB remain on the board.
2. **Wire the disk.** Solder the four wires to the first four pins of the 13-pin header and the extra supply pair to the 26-pin header. The disk runs at USB 2.0 speed; enough for a nightly backup.
3. **Wire the light.** Solder the stick's 5 V, GND and DIN. Data travels on one wire. Whether a level shifter is needed will show in the light test; we will write the result here.
4. **Wire the switch.** Solder the two leads of the switch to pin 12 and pin 14. No external resistor is planned; the board's internal pull-up will be used.
5. **Wire the clock module (optional).** VCC to pin 1, SDA to pin 3, SCL to pin 5, GND to pin 25. 32K and SQW stay free. The box finds the module at address 0x68 itself; it takes its first time from the phone while pairing and keeps it without a network afterwards (about a minute of drift a year).
6. **Measure before powering.** Check with a multimeter that there is no short between 5 V and GND. The undersides of the bare boards and the soldered ends must not touch each other.
7. **Power from the adapter.** Plug the board into a 5 V 3 A adapter, not into a computer.

An interactive 3D pinout of the board: <https://open.noq.works/projects/purser/>.

## Lights

| Colour | Meaning |
| --- | --- |
| White | Ready, disk closed |
| White, a dot at each end | Not paired, or disk not prepared |
| Blue, filling bar | Pulling the backup |
| Cyan | Checking what was pulled |
| Green | Tonight is done |
| Yellow | Warning: the backup was taken but needs a look |
| Orange | Fault: the backup could not be taken |
| Red | Suspicion. Red never lights for anything else |
| Purple, alternating | Maintenance access is on |
| Red and white alternating | Operation code locked |
| Dark | No power |

The page on `https://<id>.local` (maintenance switch on) shows the same state in words.

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
