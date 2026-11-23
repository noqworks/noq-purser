# NOQ Purser case · r1b

[Türkçe](#türkçe)

A screwless white case: the tray and the shell snap together on seven flexing hooks, the boards sit on pins that are
melted down with a soldering iron, the light shines through a top thinned to 0.8 mm, the purser logo is engraved on top.
Outside 175.5 × 68.9 × 27 mm. r1b replaces r1 after r1 was printed and assembled on the bench.

| File | Part | Print |
|---|---|---|
| `stl/purser-kasa-taban.stl` | tray | white PETG, floor down |
| `stl/purser-kasa-kapak.stl` | shell | white PETG, top down (logo and light window first), no supports |
| `stl/purser-anahtar-halkasi.stl` | switch ring | purple PETG, wide end down, 100 % infill, skirt and brim |
| `stl/purser-usb-tapasi.stl` | USB-A dust plug | purple PETG, head down, skirt and brim |

`step/` has the same parts as STEP; `cad/kasa.py` makes all of them (CadQuery 2.x; `python3 kasa.py <out dir>`).

## What changed from r1

- **Closing.** r1's half-round ridges on the tray lip did not hold: the tray and the shell came apart. r1b has seven
  cantilever hooks (1.6 mm thick, 11 mm free, 0.8 mm catch) that rise from the tray floor along the walls and click
  into pockets inside the shell wall. They print upright without supports; a firm pull opens the case. The lip only
  aligns now.
- **Orange Pi position.** The board sat flush against the front wall and the micro HDMI nose pushed on it. It now sits
  1.8 mm back; the micro HDMI clears the wall by about 1 mm.
- **USB-C opening.** A full stadium (rounded top and bottom), 9.4 × 13.4 mm, centred on the connector.
- **USB-A plug.** r1's plug pressed into the case opening and pushed on the socket instead of closing it. r1b's plug is
  independent of the case: a plate goes into the USB-A socket itself (between the socket's tongue and its shell) and the
  socket's springs hold it. If it does not go in, turn it 180°.
- **Switch ring.** No nut underneath; a modelled M6 × 0.75 internal thread runs the full 6 mm (minor Ø 5.35, major
  Ø 6.30 for print clearance, 0.6 mm lead-in chamfer). Print it solid: 100 % infill, 4 walls. Made by `cad/halka.py`
  (CadQuery body + manifold3d thread); `step/purser-anahtar-halkasi.step` is the thread-less body.
- **Clock module.** The single far mounting pin moved to the other long edge, where the module's hole is.

## Light stick: stable colours

On the bench the stick sometimes showed random colours on random LEDs, more while the disk was busy. The stick runs on
5 V and reads its data line against 0.7 × 5 V = 3.5 V; the Orange Pi drives that line at 3.3 V, so every update is on the
edge. Fix it entirely at the stick; nothing changes on the Orange Pi (same header pins, same wires):

- a **1N4007 diode in series in the stick's 5 V lead** (anode to the supply, banded end to the stick): the stick runs at
  about 4.3 V and reads 3.3 V data reliably (LEDs a little dimmer);
- a **470–1000 µF electrolytic capacitor** (10 V or more) across the stick's 5 V and GND, after the diode, close to the
  stick (long leg to 5 V);
- a **330 Ω resistor in series in the data line, at the stick's DIN pad**;
- GND stays common with the Orange Pi; nothing goes in the GND line.

Until the stick has these parts the light
software draws steady states (no continuous breathing), because every update is a chance for a garbled frame.

## Assembly

Seat the Orange Pi on four pins and the clock module on three, press each 2.5 mm pin tip down with the iron; the light
stick goes on the two pins inside the shell, LEDs up (its holes are in the 4 mm band on the DIN side, 25 mm apart). Pass
the switch through the left wall and screw the ring straight onto its bushing. Place the SSD and bridge between the
corner guides, push the dust plug into the USB-A socket (USB-C is the power input and stays open), press the shell onto
the tray until all hooks click.

## Türkçe

Vidasız beyaz kasa: taban ve kapak yedi esnek tırnakla birbirine oturur, kartlar pimlere takılır ve pim uçları havyayla
eritilir, ışık 0,8 mm'ye inceltilmiş üst yüzden süzülür, üstte purser logosu kazılı. Dış ölçü 175,5 × 68,9 × 27 mm.
r1b, r1 tezgâhta basılıp kurulduktan sonra onun yerine geldi.

| Dosya | Parça | Baskı |
|---|---|---|
| `stl/purser-kasa-taban.stl` | taban | beyaz PETG, tabanı tablada |
| `stl/purser-kasa-kapak.stl` | kapak | beyaz PETG, üst yüzü tablada (logo ve ışık penceresi ilk katmanlar), destek yok |
| `stl/purser-anahtar-halkasi.stl` | anahtar halkası | mor PETG, geniş ucu tablada, %100 doluluk, skirt ve brim |
| `stl/purser-usb-tapasi.stl` | USB-A toz tapası | mor PETG, başı tablada, skirt ve brim |

`step/` aynı parçaların STEP hâli; `cad/kasa.py` hepsini üretir (CadQuery 2.x; `python3 kasa.py <çıktı klasörü>`).

### r1'den bu yana değişenler

- **Kapanma.** r1'deki taban kenarındaki yarım yuvarlak sırtlar tutmadı; taban ile kapak birbirinden ayrılıyordu. r1b'de
  tabandan duvar boyunca yükselen yedi esnek tırnak var (1,6 mm kalın, 11 mm serbest boy, 0,8 mm kanca); kapak duvarının
  içindeki yuvalara tık diye oturur. Destek olmadan dik basılır; güçlü bir çekişle açılır. Taban kenarı artık yalnız
  hizalar.
- **Orange Pi'nin yeri.** Kart ön duvara sıfırdı, micro HDMI ucu duvara bastırıyordu. Şimdi 1,8 mm geride; micro HDMI
  duvardan yaklaşık 1 mm uzakta.
- **USB-C açıklığı.** Altı da üstü de yuvarlak tam oval, 9,4 × 13,4 mm, konnektöre ortalı.
- **USB-A tapası.** r1'deki tapa kasanın açıklığına bastırıyor, soketi kapatmak yerine ona baskı yapıyordu. r1b'deki tapa
  kasadan bağımsız: bir plaka doğrudan USB-A soketinin içine (soketin dili ile gövdesi arasına) girer, soketin yayları
  tutar. Girmezse 180° çevir.
- **Anahtar halkası.** Altta somun yok; 6 mm boyunca modelli M6 × 0,75 iç diş (baskı payıyla diş dibi Ø 5,35, diş
  üstü Ø 6,30, altta 0,6 mm giriş pahı). Tam dolu basılır: %100 doluluk, 4 duvar. `cad/halka.py` üretir (CadQuery gövde +
  manifold3d diş); `step/purser-anahtar-halkasi.step` dişsiz gövdedir.
- **Saat modülü.** Tek kalan uzak pim, modülün deliğinin olduğu öbür uzun kenara alındı.

### Işık çubuğu: kararlı renkler

Tezgâhta çubuk bazen rastgele LED'lerde rastgele renkler gösterdi, disk çalışırken daha sık. Çubuk 5 V'la çalışır ve veri
hattını 0,7 × 5 V = 3,5 V eşiğiyle okur; Orange Pi bu hattı 3,3 V ile sürer, yani her güncelleme sınırda. Çözümün tamamı çubukta; Orange Pi'de hiçbir şey değişmez (aynı header pinleri, aynı kablolar):

- **çubuğun 5 V ucuna seri 1N4007 diyot** (anot besleme tarafına, şeritli uç çubuğa): çubuk yaklaşık 4,3 V ile çalışır ve
  3,3 V veriyi güvenle okur (LED'ler biraz sönükleşir);
- **470–1000 µF elektrolitik kondansatör** (10 V ya da üstü), çubuğun 5 V ile GND'si arasına, diyottan sonra, çubuğa yakın
  (uzun bacak 5 V'a);
- **veri hattına seri 330 Ω direnç**, çubuğun DIN girişinde;
- GND Orange Pi ile ortak kalır; GND hattına bir şey konmaz.

Çubuğa bu parçalar eklenene kadar ışık yazılımı durumları
sabit çizer (sürekli nefes alma yok), çünkü her güncelleme bozuk bir kare için bir fırsattır.

### Montaj

Orange Pi'yi dört, saat modülünü üç pime oturt, her pimin 2,5 mm'lik ucunu havyayla bastırarak erit; ışık çubuğu
kapağın içindeki iki pime LED'ler yukarı bakacak şekilde takılır (delikleri DIN tarafındaki 4 mm şeritte, 25 mm arayla).
Anahtarı sol duvardan geçir, halkayı doğrudan boğazına vidala. SSD ile köprüyü köşe kılavuzlarının arasına koy, toz
tapasını USB-A soketine tak (USB-C güç girişidir, açık kalır), kapağı bütün tırnaklar tık diye oturana kadar tabana bastır.
