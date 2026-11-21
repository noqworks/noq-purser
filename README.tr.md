# NOQ Purser

[English](README.md)

Sunucunuzun yanında duran, her gece yedekleri sunucudan alıp geçmişini sunucunun ulaşamayacağı
yerde tutan küçük bir kutu.

Kutunun (Orange Pi Zero 3, USB-SATA kablo, disk) dinleyen portu yoktur. Her gece sunucuya kendisi
bağlanır, gecenin dondurulmuş yedek neslini kısıtlı bir SSH kapısından çeker, her dosyayı listeyle
karşılaştırır, şifreli diskinde 14 günlük, 8 haftalık ve 12 aylık nesil tutar ve diski yeniden
kilitler. Geçmişi yalnız kutu, kendi takvimiyle siler; sunucu kutuya ulaşamaz, ona silme de
yaptıramaz.

## Ne yapar

- **Sunucu tarafı** (`source/`): `purser-source` gecenin yedek işleri bitene kadar bekler, yedek
  depolarını dondurur (reflink, sabit bağ ya da kopya), özetli dosya listesini yazar, her kaynağa
  tazeliğini sorar, sizin doğrulama komutlarınızı çalıştırır. `purser-gate` kutunun konuşabildiği
  tek şeydir: `latest`, salt okunur rsync, `ack`.
- **Kutu** (`box/`): en yeni nesli kum havuzunda bir btrfs görüntüsüne çeker, listeye uymayan her
  şeyi reddeder, değişen her dosyayı yeniden okur, uyarıyı ve şüpheyi kendi sinyallerinden çıkarır
  (pgBackRest / borg / restic'in değişmez dosyaları, budama günü dışında silme, toplu değişiklik,
  sessiz değişiklik, bayat kaynak), salt okunur görüntüler yayımlar, saklama takvimini uygular ve
  sunucudan geçmeyen alarmlar gönderir (ntfy ya da webhook).
- **Kutunun başında**: sabit komutlu kısıtlı seri konsol; bir şey değiştiren komutlar 12 rakamlı
  işlem kodu ister.
- **İmaj** (`image/`): kutunun SD kart imajını sabitlenmiş bir Armbian sürümünden, her şey önceden
  kurulu olarak üreten betik; kutu hiçbir zaman kod ya da paket çekmez.

Desteklenen kaynaklar: pgBackRest, borg, restic, düz dizin.

## Neye karşı korumaz

- **Kutunun ele geçirilmesi.** Disk anahtarı kutudadır ve disk kutuya takılıdır. Kutuyu yöneten
  geçmişi silebilir. Tek disk vardır.
- **Aynı yerde yangın, hırsızlık ya da el koyma.** Kutu sunucunun yanında durur.
- **Aylarca bozuk yedek üreten sabırlı saldırgan.** Kutu onları sadakatle saklar. Karşılığı uzun
  saklama ve geri yükleme tatbikatıdır.
- **Disk parolasının ya da LUKS başlığının kaybı** ve yedeklemediğiniz veri.

Tam liste: [docs/threat-model.tr.md](docs/threat-model.tr.md).

## Durum

Sürüm 1.0. Test takımı donanımsız çalışır (`tests/run.sh`): birim, gerçek kapı ve gerçek btrfs ile
uçtan uca gece, saldırı senaryoları, prototipin yazdığı disk ve SD kartlarla uyum, Debian 13,
Ubuntu 24.04 ve Ubuntu 26.04 üzerinde sunucu kurulumu.

**Bu sürümle geri yükleme tatbikatı henüz yapılmadı.** Yapılana kadar NOQ Purser'ı geri yükleme
açısından sınanmamış sayın. Geri yüklemesi hiç denenmemiş yedek, yedek değildir.

## Belgeler

| | |
| --- | --- |
| [docs/install.tr.md](docs/install.tr.md) | Sunucu tarafı, kutu imajı, ilk açılış, SD kart taşıma |
| [docs/hardware.tr.md](docs/hardware.tr.md) | Kart, kablo, disk; LED; kutunun diske yaptıkları |
| [docs/design.tr.md](docs/design.tr.md) | Nasıl çalışır: gece, liste, kapı, sinyaller, saklama, saat, ağ, konsol |
| [docs/threat-model.tr.md](docs/threat-model.tr.md) | Neye karşı korur, neye karşı korumaz |
| [docs/restore.tr.md](docs/restore.tr.md) | Temiz bir makinede geri yükleme |
| [CHANGELOG.md](CHANGELOG.md) | Değişiklikler |

## Depo

```
source/   sunucu tarafı: purser-source, purser-gate, purser-admit, install.sh, örnekler
box/      kutu çekirdeği (Bash), kısıtlı konsol, doğrulayıcı, systemd birimleri, şablonlar, iletiler (en, tr)
image/    imaj üretimi, SD karta yazma, kart taşıma
tests/    donanımsız test takımı (Docker)
docs/     belgeler (en, tr)
```

Yalnız Bash ve dağıtım paketleri. Lisans: GPL-3.0-or-later ([LICENSE](LICENSE)).
