# Donanım

[English](hardware.md)

## Parçalar

| Parça | Adet | Not |
| --- | --- | --- |
| Orange Pi Zero 3 | 1 | 1 GB bellek yeter. Wi-Fi kullanılmaz. |
| 2,5" SATA SSD | 1 | Yedeklerinin toplamından en az iki kat büyük. Yer kazanmak için kartını kutusundan çıkardık. |
| USB-SATA köprü kartı | 1 | Sıradan bir USB-SATA kablosunun içindeki kart. Kablo kesilir, teller doğrudan karta lehimlenir. |
| microSD kart | 1 | 8 GB ve üstü. |
| 5 V 3 A USB-C adaptör | 1 | Bilgisayarın USB girişi yetmez; disk ilk dönüşte yüksek akım çeker. |
| Ethernet kablosu | 1 |  |
| 8'li adreslenebilir LED çubuğu | 1 | WS2812 ya da SK6812. Dört renkli (RGBW) olanı da çalışır; kurulumda seçilir. |
| Kollu anahtar (SPST) | 1 | İki telli, 6 mm boyunlu. Bakım anahtarı. |
| DS3231 saat modülü (isteğe bağlı) | 1 | Modemin saat sunucusu yoksa takılır. ZS-042 kartında pili şarj eden R4 (201) direnci sökülür; CR2032 şarj edilmez. |

Röle, güvenlik anahtarı ya da düğme yok; denedik, katkıları olmadığı için çıkardık. Saat iki yoldan gelir: modemin saat sunucusu (NTP) ya da pilli saat modülü. Modemi ayarlayamıyorsan modülü tak.

## Bağlantı

Pin numaraları Orange Pi Zero 3 v1.2'nin resmî pin şemasından alındı. Disk telleri tezgâhta doğrulandı; ışık ve anahtar sınaması sırada. Pin 1, her iki başlıkta kare lehim pedidir.

| Tel | Nereye | Not |
| --- | --- | --- |
| Disk · kırmızı 1 | 13 pinli başlık, pin 1 (5 V) | Köprü kartının beslemesi |
| Disk · siyah 1 | 13 pinli başlık, pin 2 (GND) |  |
| Disk · beyaz (D−) | 13 pinli başlık, pin 3 (USB2 D−) | Veri telleri kısa ve birbirine yakın kalsın |
| Disk · yeşil (D+) | 13 pinli başlık, pin 4 (USB2 D+) |  |
| Disk · kırmızı 2 | 26 pinli başlık, pin 4 (5 V) | Ek besleme; disk akımını tek pine bindirmemek için |
| Disk · siyah 2 | 26 pinli başlık, pin 9 (GND) |  |
| LED · 5 V | 26 pinli başlık, pin 2 (5 V) |  |
| LED · GND | 26 pinli başlık, pin 6 (GND) |  |
| LED · DIN | 26 pinli başlık, pin 19 (MOSI) | Çubuğun giriş ucu; DOUT boş kalır |
| Anahtar · uç 1 | 26 pinli başlık, pin 12 (PC11) |  |
| Anahtar · uç 2 | 26 pinli başlık, pin 14 (GND) | Kontak kapalıyken bakım açık |
| Saat · VCC | 26 pinli başlık, pin 1 (3,3 V) | 5 V değil; modülün I²C dirençleri bu gerilime çeker |
| Saat · SDA | 26 pinli başlık, pin 3 (I²C3 SDA, PH5) |  |
| Saat · SCL | 26 pinli başlık, pin 5 (I²C3 SCL, PH4) |  |
| Saat · GND | 26 pinli başlık, pin 25 (GND) | Pin 9 diskin ek toprağında; 20 de olur |

1. **Köprü kartını çıkar.** USB-SATA kablosunun kılıfını aç, kartı çıkar, USB kablosunu karttan sök. Kartta USB için dört lehim pedi kalır.
2. **Diski bağla.** Dört teli 13 pinli başlığın ilk dört pinine, ek besleme çiftini 26 pinli başlığa lehimle. Disk USB 2.0 hızında çalışır; gece yedeği için yeter.
3. **Işığı bağla.** Çubuğun 5 V, GND ve DIN uçlarını lehimle. Veri tek telden gider. Seviye çevirici gerekip gerekmediğini ışık sınamasında göreceğiz; sonucu buraya yazacağız.
4. **Anahtarı bağla.** Anahtarın iki ucunu pin 12 ve pin 14'e lehimle. Dış direnç planlanmadı; kartın dahili yukarı çekmesi kullanılacak.
5. **Saat modülünü bağla (isteğe bağlı).** VCC pin 1, SDA pin 3, SCL pin 5, GND pin 25. 32K ve SQW uçları boş kalır. Kutu modülü 0x68 adresinde kendisi bulur; ilk saatini eşleşirken telefondan alır, sonra ağ olmadan da doğru tutar (yılda yaklaşık bir dakika kayar).
6. **Güç vermeden ölç.** Multimetreyle 5 V ile GND arasında kısa devre olmadığını ölç. Çıplak kartların altı ve lehimli uçlar birbirine değmesin.
7. **Adaptörle aç.** Kartı bilgisayara değil, 5 V 3 A adaptöre tak.

Kartın döndürülebilir 3B pin şeması: <https://open.noq.works/tr/projeler/purser/>.

## Işıklar

| Renk | Anlamı |
| --- | --- |
| Beyaz | Hazır, disk kapalı |
| Beyaz, iki uçta nokta | Eşleşmemiş ya da diski hazırlanmamış |
| Mavi, dolan çubuk | Yedek çekiliyor |
| Camgöbeği | Çekilen yedek denetleniyor |
| Yeşil | Bu gece tamam |
| Sarı | Uyarı: yedek alındı ama bakılmalı |
| Turuncu | Arıza: yedek alınamadı |
| Kırmızı | Şüphe. Başka hiçbir durumda kırmızı yanmaz |
| Mor, dönüşümlü | Bakım erişimi açık |
| Kırmızı-beyaz dönüşümlü | İşlem kodu kilitli |
| Karanlık | Güç yok |

`https://<kimlik>.local` sayfası (bakım anahtarı açıkken) aynı durumu sözle gösterir.

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
