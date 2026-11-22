# NOQ Purser case · r1

[Türkçe](#türkçe)

A screwless white case: the tray and the shell snap together, the boards sit on pins that are melted down with a
soldering iron, the light shines through a top thinned to 0.8 mm, the purser logo is engraved on top.
Outside 175.5 × 68.9 × 27 mm. Drawn, not printed yet.

| File | Part | Print |
|---|---|---|
| `stl/purser-kasa-taban.stl` | tray | white PETG, floor down |
| `stl/purser-kasa-kapak.stl` | shell | white PETG, top down (logo and light window first), no supports |
| `stl/purser-anahtar-halkasi.stl` | switch ring | black PETG, wide end down, skirt and brim |
| `stl/purser-usb-tapasi.stl` | USB-A plug | white PETG, face down, skirt and brim |

`step/` has the same parts as STEP; `cad/kasa.py` makes all of them (CadQuery 2.x; `python3 kasa.py <out dir>`).

Assembly: seat the Orange Pi on four pins and the clock module on three, press each 2.5 mm pin tip down with the iron;
the light stick goes on the two pins inside the shell, LEDs up (its holes are in the 4 mm band on the DIN side, 25 mm
apart). Pass the switch through the left wall, fit the nut, screw the ring on (M6 × 0.75). Place the SSD and bridge
between the corner guides, press the USB-A plug into its socket, press the shell onto the tray until it clicks.

## Türkçe

Vidasız beyaz kasa: taban ve kapak tırnakla birbirine oturur, kartlar pimlere takılır ve pim uçları havyayla eritilir,
ışık 0,8 mm'ye inceltilmiş üst yüzden süzülür, üstte purser logosu kazılı. Dış ölçü 175,5 × 68,9 × 27 mm. Çizildi,
henüz basılmadı.

| Dosya | Parça | Baskı |
|---|---|---|
| `stl/purser-kasa-taban.stl` | taban | beyaz PETG, tabanı tablada |
| `stl/purser-kasa-kapak.stl` | kapak | beyaz PETG, üst yüzü tablada (logo ve ışık penceresi ilk katmanlar), destek yok |
| `stl/purser-anahtar-halkasi.stl` | anahtar halkası | siyah PETG, geniş ucu tablada, skirt ve brim |
| `stl/purser-usb-tapasi.stl` | USB-A tapası | beyaz PETG, ön yüzü tablada, skirt ve brim |

`step/` aynı parçaların STEP hâli; `cad/kasa.py` hepsini üretir (CadQuery 2.x; `python3 kasa.py <çıktı klasörü>`).

Montaj: Orange Pi'yi dört, saat modülünü üç pime oturt, her pimin 2,5 mm'lik ucunu havyayla bastırarak erit; ışık
çubuğu kapağın içindeki iki pime LED'ler yukarı bakacak şekilde takılır (delikleri DIN tarafındaki 4 mm şeritte,
25 mm arayla). Anahtarı sol duvardan geçir, somunu tak, halkayı vidala (M6 × 0,75). SSD ile köprüyü köşe kılavuzlarının
arasına koy, USB-A tapasını sokete bastır, kapağı tık diye oturana kadar tabana bastır.
