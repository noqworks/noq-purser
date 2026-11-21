# Geri yükleme

[English](restore.md)

Geri yüklemesi hiç denenmemiş yedek, yedek değildir. Üç ayda bir ve kaynaklarda her değişiklikten
sonra tatbikat yapın.

**Bu sürümün durumu:** aşağıdaki adımlar diskteki biçimden ve araçların kendi belgelerinden
çıkar. Bu sürümle tam bir geri yükleme tatbikatı **henüz yapılmadı**.

Gerekenler: disk, korunan sunucuya erişimi olmayan temiz bir Linux makine (ağı kapalı bir
dizüstü ya da sanal makine), kâğıt paket (disk kurtarma parolası, araçların parolaları ve
anahtarları) ve LUKS başlığı bozuksa başlık yedeği (`luks-baslik.img`). Kutunun kendisi gerekmez.

## 1. Diski salt okunur aç

```sh
lsblk -o NAME,SIZE,MODEL,TRAN                     # USB diski bul, ör. /dev/sdX
# yalnız LUKS başlığı bozuksa:
cryptsetup luksHeaderRestore /dev/sdX --header-backup-file luks-baslik.img
cryptsetup open --readonly /dev/sdX purser-restore   # kurtarma parolasını sorar
mkdir -p /mnt/purser && mount -o ro /dev/mapper/purser-restore /mnt/purser
```

## 2. Nesli seç

```sh
ls /mnt/purser/nesil/            # gen-<kimlik>: günlük, uzun-<kimlik>: haftalık/aylık (budanmış)
ls /mnt/purser/denetim/supheli/  # şüpheli nesiller ...
ls /mnt/purser/denetim/temiz/    # ... ve kutunun başında şüphesi kaldırılanlar
cat /mnt/purser/denetim/meta/<kimlik>      # bayt, dosya, süre, uyarılar, şüphe
```

Şüpheli olmayan en yeni nesli ya da kaldırılmamış ilk şüpheliden eskisini seçin. Kullanmadan önce
listesiyle karşılaştırın:

```sh
cd /mnt/purser/nesil/gen-<kimlik>
grep -v '^#' /mnt/purser/denetim/liste/<kimlik>.list | sha256sum --quiet -c
# budanmış uzun saklama kopyası listenin bir kısmını taşır:
cd /mnt/purser/nesil/uzun-<kimlik>
grep -v '^#' /mnt/purser/denetim/liste/<kimlik>.list | sha256sum --quiet -c --ignore-missing
```

## 3. Araçla geri yükle

Önce gereken depoyu yazılabilir bir çalışma alanına kopyalayın (disk salt okunur kalır):

```sh
cp -a /mnt/purser/nesil/gen-<kimlik>/<kaynak> /restore/repo
```

- **pgBackRest**: bir pgBackRest yapılandırmasını kopyaya yöneltin (`repo1-path=/restore/repo`,
  kâğıt paketten stanza adı ve `repo1-cipher-pass`), sonra `pgbackrest --stanza=<stanza> restore`.
  Haftalık/aylık kopyada (`uzun-<kimlik>`) WAL arşivi yoktur: `--type=none` ile geri yükleyin
  (`archive-copy=y` gerekir; tam yedeğin WAL'ını kendi içinde taşır). pgBackRest zaman çizelgesi
  ilerlemediği için uyarır; tatbikatta beklenen budur. `--type=immediate` da denenebilir.
- **borg**: `borg list /restore/repo`, sonra `borg extract /restore/repo::<arşiv>` (kâğıt paketten
  parola ya da anahtar dökümü).
- **restic**: `restic -r /restore/repo snapshots`, sonra
  `restic -r /restore/repo restore <görüntü> --target /restore/out`.
- **dir**: dosyalar düz kopyadır.

Sonra bildiğiniz bir şeyi denetleyin: bir dosyanın içeriği, bir sorgunun sonucu.

## 4. Çalışanı sabitle

Geri yüklemesi çalışan nesil hiçbir zaman otomatik silinmemeli:

- kutunun başında: seri konsolda `pin <kimlik>` (işlem kodunu sorar), ya da
- geri yükleme makinesinde, disk okuma-yazma bağlıyken: `touch /mnt/purser/denetim/pin/<kimlik>`.
  Kutu bir sonraki penceresinde okur.

## 5. Kapat

```sh
umount /mnt/purser && cryptsetup close purser-restore
```

Diski kutuya geri takın. Kutu onu LUKS UUID'siyle bulur; başka bir şey gerekmez.

## Diskin düzeni

```
nesil/gen-<kimlik>           salt okunur btrfs görüntüsü, gecede bir
nesil/uzun-<kimlik>          salt okunur haftalık/aylık kopya (pgBackRest en yeni tam yedeğe budanmış)
denetim/liste/<kimlik>.list  neslin kutunun doğruladığı listesi (gerçek özetler)
denetim/meta/<kimlik>        bayt= dosya= sure= uyari= suphe=
denetim/supheli/<kimlik>     şüpheli neslin neden kodları
denetim/temiz/<kimlik>       şüphe kutunun başında kaldırıldı
denetim/pin/<kimlik>         sabitlenmiş
hazirlik                     hazırlık alanı (yarım olabilir; asla buradan geri yükleme yapmayın)
```
