# NOQ Purser

[English](README.md)

Sunucunun yanında duran küçük bir kutu: yedekleri her gece sunucudan alır ve geçmişlerini
sunucunun ulaşamayacağı yerde saklar.

**Önizleme 1.0.0.** Tezgâhtaki kutuda sınanıyor. İndirme ve adım adım rehber:
<https://open.noq.works/tr/projeler/purser/>

Kutu (Orange Pi Zero 3, çıplak USB-SATA köprüsü, 2,5" SSD, LED çubuğu ve bakım anahtarı) anahtar
kapalıyken hiçbir portu dinlemez. Her gece sunucuya kendisi bağlanır, gecenin dondurulmuş yedek
neslini kısıtlı bir SSH kapısından çeker, her dosyayı listeyle karşılaştırır, şifreli diskinde 14
günlük, 8 haftalık ve 12 aylık nesil tutar ve diski yeniden kilitler. Geçmişi yalnız kutu, kendi
takvimiyle siler; sunucu kutuya ulaşamaz, ona silme diyemez.

## Dört adımda kurulum

1. **Sunucu** (systemd'li Debian/Ubuntu): `noq-purser-server-1.0.0.tar.gz` dosyasını indir,
   `sudo ./install.sh` çalıştır, yedek depolarını
   `/etc/purser/source.conf` dosyasına yaz.
2. **Bilgisayar** (macOS ya da Linux): kart aracını çalıştır; Terminal'de
   `bash <(curl -fsSL https://open.noq.works/files/purser/purser-setup)`
   ya da `noq-purser-setup-1.0.0.tar.gz` içinden (Mac'te `purser-setup.command` dosyasına çift tıkla).
   Araç kutu imajını indirip denetler, SD kartları listeler, birkaç soru sorar, kartı yazar ve 12
   haneli işlem kodunu ve disk kurtarma parolasını **bir kez** gösterir: kâğıda yaz.
3. **Kutu**: kart, disk, Ethernet, güç. İlk açılış diski hazırlar (camgöbeği); çubuğun iki ucunda
   nokta, eşleşmeyi beklediği anlamına gelir.
4. **Eşleşme**: sunucuda `sudo purser pair` bir QR kod basar. Bakım anahtarını aç (mor), telefonda
   `https://<kimlik>.local` adresini aç, Eşleş'e dokun, kodu okut, anahtarı kapat.

Ayrıntı: [docs/install.tr.md](docs/install.tr.md).

## Ne yapar

- **Sunucu tarafı** (`source/`): `purser-source` gecenin yedek işlerinin bitmesini bekler, yedek
  depolarını dondurur (reflink, sabit bağ ya da kopya), özetli bir dosya listesi yazar, her kaynağa
  taze olup olmadığını sorar ve senin doğrulama komutlarını çalıştırır. Kutunun konuşabildiği tek
  şey `purser-gate`: `latest`, salt okunur rsync, `ack`, `note`. `purser pair` bir kutuyu tek
  kullanımlık QR koduyla kabul eder.
- **Kutu** (`box/`): en yeni nesli bir sanal alan içinde btrfs anlık görüntüsüne çeker, listeye
  uymayanı reddeder, değişen her dosyayı yeniden okur, uyarı ve şüpheyi kendi sinyallerinden
  çıkarır (pgBackRest / borg / restic'in değişmeyen dosyaları, budama günü dışında silme, toplu
  değişiklik, sessiz değişiklik, bayat kaynak), salt okunur anlık görüntüler yayınlar ve saklama
  kuralını uygular.
- **Alarmlar** aynı kapıdan geri gider (`note <olay>`, sabit bir alfabe); sunucu onları senin
  komutunla yükseltir (`ALERT_CMD`). Üçüncü taraf hizmet yok, internet yok.
- **Kutunun başında**: 8 LED'li çubuk durumu gösterir; bakım anahtarı yalnız açıkken
  `https://<kimlik>.local` adresinde bir sayfa (eşleşme, durum, işlem koduyla korunan işlemler) ve
  senin anahtarınla SSH açar. Kapatınca hepsi kapanır.
- **Saat**: modemden ağ saati ya da isteğe bağlı DS3231 pil saati (eşleşirken telefondan bir kez
  ayarlanır).
- **İmaj** (`image/`): SD kart imajını sabitlenmiş bir Armbian sürümünden, her şey kurulu olarak
  derler; kutu kod ya da paket indirmez. `image/purser-setup` kartı hazırlar.

Desteklenen kaynaklar: pgBackRest, borg, restic, düz dizinler.

## Neye karşı korumaz

- **Kutunun ele geçirilmesi.** Disk anahtarı kutuda, disk kutuya bağlı. Kutuyu yöneten geçmişi
  silebilir. Tek disk var.
- **Aynı yerde yangın, hırsızlık ya da el koyma.** Kutu sunucunun yanında durur.
- **Aylarca bozuk yedek üreten sabırlı bir saldırgan.** Kutu onları sadakatle saklar. Yanıtı uzun
  saklama süresi ve geri yükleme tatbikatıdır.
- **Kaybolan disk parolası ya da LUKS başlığı**, ve yedeklemediğin veri.

Tam liste: [docs/threat-model.tr.md](docs/threat-model.tr.md).

## Durum

Önizleme 1.0.0. Test takımı donanımsız çalışır (`tests/run.sh`): birim, gerçek kapı ve gerçek btrfs
ile uçtan uca gece, saldırı senaryoları, ilk örneğin yazdığı disk ve kartlarla uyumluluk; imaj
araçları (`tests/run.sh --image-tools`).

**Bu sürümle henüz geri yükleme tatbikatı yapılmadı.** Yapılana kadar NOQ Purser'ı geri yükleme
açısından sınanmamış say. Geri yüklemesi hiç denenmemiş yedek, yedek değildir.

## Belgeler

| | |
| --- | --- |
| [docs/install.tr.md](docs/install.tr.md) | Sunucu, kart, ilk açılış, eşleşme, SD kart taşıma |
| [docs/hardware.tr.md](docs/hardware.tr.md) | Parçalar, bağlantı, ışıklar; kutu diske ne yapar |
| [docs/design.tr.md](docs/design.tr.md) | Nasıl çalışır: gece, liste, kapı, sinyaller, saklama, saat, ağ, kutunun başında |
| [docs/threat-model.tr.md](docs/threat-model.tr.md) | Neye karşı korur, neye korumaz |
| [docs/restore.tr.md](docs/restore.tr.md) | Temiz bir makinede geri yükleme |
| [CHANGELOG.md](CHANGELOG.md) | Değişiklikler |

## Depo

```
source/   sunucu: purser-source, purser-gate, purser-admit, purser-pair, purser, install.sh
box/      kutu çekirdeği (Bash), sayfa (purser-ui, ui/), ışık, bakım anahtarı, birimler, iletiler (en, tr)
image/    imaj derleme, purser-setup (kart), flash.sh, kart taşıma, release.sh
tests/    donanımsız test takımı (Docker)
docs/     belgeler (en, tr)
```

Yalnız Bash, Python standart kitaplığı ve dağıtım paketleri. Lisans: GPL-3.0-or-later ([LICENSE](LICENSE)).
