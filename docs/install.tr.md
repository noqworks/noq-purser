# Kurulum

[English](install.md)

Önizleme 1.0.0. İndirmeler: <https://open.noq.works/tr/projeler/purser/#indir> (GitHub sürümünde de
var). Her dosya SHA-256 değeriyle `SHA256SUMS` içinde.

## Özet

1. **Sunucuda: purser install.** Ayrı bir kullanıcı ve yalnız kutunun kullanacağı dar bir kapı kurar. pgBackRest, Borg ve restic ayarlarına bakıp bulduğu depoları önerir. Depo şifresizse açıkça uyarır.
2. **Bilgisayarda: purser-setup.** purser-setup <imaj>.img.xz /dev/diskN. Önce imajın sağlamasını ve kartın çıkarılabilir bir disk olduğunu denetler. Kutunun dilini, saat dilimini, ağını (varsayılan DHCP) ve saat sunucusunu sorar. Diskin silinip silinmeyeceğini sorar; silinecekse yeni kutu kimliğini yazarak onaylarsın. Kartı yazmak için aygıt adını bir kez daha yazarsın.
3. **Kâğıda yaz.** Kart yazılınca iki şey bir kez gösterilir: 12 haneli işlem kodu ve disk silinecekse kurtarma parolası. Kâğıda yazıp "yazdım" diyene kadar kurulum ilerlemez. Bilgisayarda ve sunucuda kopyası kalmaz; fotoğrafını çekme.
4. **Kartı tak, güç ver.** Kart, disk, Ethernet, en son güç. İlk açılış gözetimsizdir: ayarları karttan alır, kurulum bölümünü siler, diski hazırlar (camgöbeği nefes). Bitince ışığın iki ucunda nokta yanar: eşleşmeyi bekliyor.
5. **Sunucuda: purser pair.** Terminalde bir QR kod ve tek satırlık bir belirteç çıkar; on dakika geçerli, tek kullanımlıktır.
6. **Bakım anahtarını aç, QR'ı okut.** Işık mor yanıp söner. Telefonla https://<kimlik>.local adresine gir; kutunun kendi imzalı sertifikası için tarayıcının uyarısını bir kez kabul et. Eşleş'e dokun, QR'ı okut. Saat modülü varsa telefonun saati bu sırada bir kez modüle yazılır.
7. **Anahtarı kapat.** Sayfa, SSH ve kutunun ağdaki görünürlüğü kapanır. Kutu o gece ilk yedeği çeker; sabah ışık yeşilse tamamdır.

## 1. Sunucu

systemd'li Debian 12/13 ya da Ubuntu 24.04+.

```
tar xzf noq-purser-server-1.0.0.tar.gz && cd noq-purser-server-1.0.0
sudo ./install.sh --listen 192.168.1.10        # sunucunun, kutunun ağındaki adresi
sudo nano /etc/purser/source.conf               # SOURCES=("pgbackrest:/var/lib/pgbackrest" "borg:/srv/borg" ...)
sudo purser status
```

`install.sh` kapı kullanıcısını, kapıya ait ayrı bir sshd'yi (tek port, varsayılan 2222, yalnız
kabul edilen kutuların adresleri), gece çalışan `purser-source` işini (`--timer 04:30`) ve alarm
yolunu kurar. Yeniden çalıştırılabilir. Kutudan gelen alarmlar `note <olay>` olarak gelir ve
`source.conf` içindeki `ALERT_CMD` ile yükseltilir (varsayılan: sistem günlüğü). Seçenekler:
`--port`, `--base`, `--user`, `--timer`, `--prefix`; `--uninstall` programları ve birimleri
kaldırır, veriyi bırakır.

## 2. Kart (bilgisayarında)

macOS ya da Linux. Terminal'de:

```
bash <(curl -fsSL https://open.noq.works/files/purser/purser-setup)
```

ya da `noq-purser-setup-1.0.0.tar.gz` dosyasını aç ve `bash purser-setup` çalıştır (Mac'te
`purser-setup.command` dosyasına çift tıklanabilir; ilk kez sağ tık > Aç, imzalı bir uygulama
değil, bir betik).

Araç imajı open.noq.works'ten önbelleğe indirir ve SHA-256 değerini denetler, çıkarılabilir
diskleri (kartı) listeler ve sorar: dil, saat dilimi, ağ (DHCP ya da adres), saat sunucusu
(`gateway` = modem) ve USB diskin silinip hazırlanıp hazırlanmayacağı (onay için yeni kutu
kimliğini yazarsın). `flash.sh` ardından bütün, çıkarılabilir ve en çok 256 GB olmayan diski
reddeder; aygıt adını bir kez daha yazarsın. Yazdıktan sonra işlem kodunu ve disk hazırlanacaksa
kurtarma parolasını bir kez gösterir; kâğıda yaz ve onay sözcüğünü yaz. Ayarlar ve bu tek
kullanımlık sırlar kartın küçük kurulum bölümüne (`PURSERSET`) gider; ilk açılış onları alır ve
bölümü siler. Bilgisayarda hiçbir şey kalmaz. `~/.ssh/id_ed25519.pub` varsa bakım SSH'si için karta
konur (`--no-ssh-key` ile konmaz). Elindeki bir imajla: `purser-setup <imaj.img.xz> <aygıt>`.

## 3. İlk açılış

Kart, USB disk, Ethernet, en son güç. İlk açılış gözetimsizdir: ayarlar karttan alınır, disk
yalnız onayladığın işaretle silinip LUKS2 + btrfs olarak hazırlanır, öz sınama çalışır. Disk
hazırlanırken çubuk camgöbeği nefes alır; iki ucunda nokta olan beyaz çubuk eşleşmeyi beklediğini
gösterir. Saat kaynağı yoksa (modem NTP'si ya da pil saati) kutu yedek almaz; saat modülü için
[hardware.tr.md](hardware.tr.md).

## 4. Eşleşme

```
sudo purser pair                 # QR kod ve tek satır belirteç; 10 dakika, tek kullanımlık
```

Bakım anahtarını aç (çubuk mor yanıp söner). Telefonda `https://<kimlik>.local` adresini aç
(kimlik kart etiketinde, örn. `k7rt.local`), kutunun kendi imzalı sertifikası için uyarıyı bir kez
geç, Eşleş'e dokun ve kodu okut (ya da satırı yapıştır). Kutu sunucunun anahtar parmak izini
denetler, sunucu kutunun anahtarını yalnız onun adresinden kabul eder; pil saati varsa telefonun
saati ona yazılır. Anahtarı kapat: sayfa, SSH ve mDNS kapanır. Kutu ilk neslini o gece çeker.

## Yeni SD karta taşıma (güncelleme)

Kutu kendini hiç güncellemez. Güncellemek için yeni imaj üretip durumu taşıyın: disk anahtarı,
LUKS başlık yedeği, bildirim adresi, kutunun SSH anahtarı, kapının ana bilgisayar anahtarı,
`purser.conf` ve `/var/lib/purser`. Bir Linux makinede (korunan sunucuda değil: disk anahtarı ona
hiç değmemeli):

```sh
# tek kart okuyucu yeter: durumu imaja taşı, sonra yaz
xz -dk out/noq-purser-….img.xz                                       # .img'yi verir
image/purser-card-migrate --from /dev/sdX --to out/noq-purser-….img   # okuyucuda eski kart
image/flash.sh out/noq-purser-….img /dev/sdX                           # okuyucuda yeni kart
# ya da iki okuyucuyla: önce yaz, sonra karttan karta taşı
image/purser-card-migrate --from /dev/sdX --to /dev/sdY
```

`purser-card-migrate` imajı değiştirdikten sonra yeni bir `.img.sha256` yazar; `flash.sh` yazdığı
dosyayı denetler. Yeni imaja gömülü `setup.conf` korunur: anahtarları (ör. sabit adres) ilk
açılışta taşınan `purser.conf`'un önüne geçer; eski kartın kendi ağ ayarları işletim sistemindedir
ve taşınmaz.

Eski kart salt okunur bağlanır ve değişmeden kalır. İlk açılışta kutu taşınan yapılandırmayı ve
diski LUKS UUID'siyle bulur, sahiplenir ve gece işini sürdürür. Prototipten gelen kartta işlem kodu
yoktur: gece işi yine çalışır, haftalık hatırlatma konsolda `setup-code` ister. Prototipin artık
kullanılmayan donanım için yazdığı anahtarlar yok sayılır.

Taşımadan sonra, imaja taşıdıysanız, imaj dosyası disk anahtarını içerir: silin.

## Testler

```sh
tests/run.sh                    # donanımsız bütün takımlar, atılabilir bir kapsayıcıda
tests/run.sh --server-install   # Debian 13, Ubuntu 24.04, Ubuntu 26.04 üzerinde sunucu kurulumu
tests/run.sh --image-tools      # flash.sh ve purser-card-migrate
```

Docker gerekir; döngü aygıtlı ayrıcalıklı kapsayıcılar çalıştırır; bir test makinesinde çalıştırın.
