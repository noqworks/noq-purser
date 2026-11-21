# Donanım

[English](hardware.md)

Kutu üç parçadır. Hiçbir şey lehimlenmez, kesilmez, kablolanmaz.

| Parça | Referans | Not |
| --- | --- | --- |
| Kart | Orange Pi Zero 3 (Allwinner H618, en az 1 GB RAM, gigabit Ethernet) | `image/` içindeki imaj bu kart için üretilir. Yazılımın kendisi Debian üzerinde Bash'tir; kendi imajınızla başka kartlarda da çalışır. |
| Kablo | Sıradan, kesilmemiş 2,5" USB-SATA kablo ya da adaptör, kartın USB-A girişinde | Diski USB'den besler. SMART'ı geçirmeli (SAT); öz sınama bunu denetler. |
| Disk | 2,5" SATA SSD | Disk gece gündüz enerjilidir; SSD önerilir. Boyut: [design.tr.md](design.tr.md) içinde "Kaba disk boyutu". |

Gereken ama kutunun parçası olmayanlar:

- microSD kart (16 GB ya da üstü; endüstriyel / yüksek dayanımlı kart iyi olur),
- USB-C güç kaynağı, 5 V / 3 A (kart diski USB-A girişinden besler),
- Ethernet kablosu (kutu yalnız kablolu; Wi-Fi ve Bluetooth kapalı),
- kurulum ve kutunun başındaki komutlar için: kartın hata ayıklama UART'ına (GND, RX, TX;
  115200 baud) 3,3 V USB-seri dönüştürücü. Kartınızda orada pin yoksa lehim yerine klips ya da
  yaylı uçlu prob kullanın. İmaja `setup.conf` gömülüyse konsol yalnız yeni disk (kurtarma
  parolası bir kez gösterilir) ve işlem kodu için gerekir.

```
USB-C 5 V / 3 A ──► Orange Pi Zero 3 ──USB-A──► USB-SATA kablo ──► 2,5" SSD
                        │
                        ├── Ethernet ──► ağınız (kablolu)
                        └── hata ayıklama UART'ı ──► USB-seri dönüştürücü (yalnız kutunun başında çalışırken)
```

## Göstergeler

Ekran ve düğme yok. Kartın kendi LED'i varsa (`/sys/class/leds`, ör. `green:status`) kutu onu
kullanır (`BOARD_LED=auto`; `none` kapatır):

| LED | Anlamı |
| --- | --- |
| sabit yanar | son sağlam nesil 30 saatten yeni, uyarı ve şüphe yok |
| yavaş yanıp söner | uyarı: gecikme, nesil gelmedi, yarım gece, güvenilmeyen saat |
| hızlı yanıp söner | şüpheli nesil, reddedilen nesil, disk ya da doğrulama hatası |
| kalp atışı | henüz kurulmadı ya da henüz sağlam nesil yok |

Asıl durum seri konsoldaki `status` komutunda ve bildirimlerdedir.

## Kutu diske ne yapar

- Disk takılı kalır. Gece penceresi dışında **kilitlidir**: LUKS birimi kapalı, hiçbir şey bağlı
  değil. `status` "Disk şu an: kilitli" der.
- USB-SATA köprüsü takılırsa (disk görünmüyor ya da yanıt vermiyorsa) kutu USB aygıtını bir kez
  yazılımla yeniden başlatır (yetkiyi kaldırıp verir, olmazsa unbind/bind). Disk dönmezse acil
  bildirim gönderir; o zaman birinin kabloyu çıkarıp takması gerekir.
- Öz sınama (`selftest`): disk USB'de görünüyor mu, bağlantı hızı (en az 480 Mbit/s), SMART
  köprüden okunuyor mu, ağ (varsayılan yol, kapının portu yanıt veriyor mu), saat eşit mi.

## Kendi masanızda ölçün

- Bağlantı hızı ve aktarım: USB 2.0 kabaca 35–40 MB/sn verir; birkaç yüz GB'lık ilk dolum saatler
  sürer (`first-fill` kullanın).
- `cryptsetup benchmark`: kurulum yeterince hızlıysa AES-XTS'i, değilse Adiantum'u seçer.
- Yazma ortasında elektrik kesme: bir gece birkaç kez fişi çekin, sonra btrfs'nin bağlandığını ve
  yayımlanmış nesillerin geri okunduğunu denetleyin (`selftest`, geri yükleme tatbikatı). Köprünün
  yazma boşaltmayı dürüst iletip iletmediği burada anlaşılır.
