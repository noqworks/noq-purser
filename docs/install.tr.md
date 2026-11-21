# Kurulum

[English](install.md)

Üç adım: sunucu tarafı, kutu imajı, ilk açılış. Aşağıdaki adresler örnektir (`192.0.2.10` sunucu,
`192.0.2.15` kutu).

## 1. Sunucu tarafı

Korunan sunucuda, root olarak (Debian 12/13, Ubuntu 24.04/26.04; Debian 13, Ubuntu 24.04 ve 26.04
üzerinde sınandı):

```sh
git clone <bu depo> noq-purser && cd noq-purser
source/install.sh --listen 192.0.2.10 --port 2222 --base /srv/purser --timer 04:30
```

Eksik olanı kurar (`rsync`, `openssh-server`, `rrsync` için `python3`), kapı kullanıcısını açar
(parolasız), `purser-source`, `purser-gate` ve `purser-admit`'i `/usr/local/sbin` altına koyar,
`/etc/purser/source.conf`'u (yalnız yoksa), kapının kendi ana bilgisayar anahtarını ve
`purser-source.timer` (gecelik), `purser-source-watch.timer` (saatlik) ve `purser-sshd.service`
(yalnız kutu için ayrı bir sshd; ana sshd'ye dokunulmaz) birimlerini yazar. İstenildiği zaman
yeniden çalıştırılabilir; `--uninstall` programları ve birimleri kaldırır, `--base` altındaki
veriyi bırakır, `/etc/purser`'ı kenara taşır.

Sonra `/etc/purser/source.conf`'u düzenleyin. `source/examples/` altındaki örnekler (pgBackRest,
borg, restic, düz dizin) kaynakları, beklenen birimleri, tazelik ve doğrulama komutlarını
gösterir. Denetleyip zamanlayıcıyı açın:

```sh
purser-source check
systemctl enable --now purser-source.timer
```

Yedeklerin içindeki adlar `A-Z a-z 0-9 . _ / + -` kullanmalı; başka karakterli adlar bir borg ya
da restic deposunun içine girer. Kaynakları kendi araçlarıyla şifreleyin (borg/restic repokey,
pgBackRest `repo-cipher-type`): kutu disk anahtarını kendi üzerinde tutar.

Kutu sonra, anahtarını gösterdiğinde kabul edilir (3. adım):

```sh
purser-admit 192.0.2.15 'ssh-ed25519 AAAA… purser@noq-purser'
```

Anahtarı `from="192.0.2.15",restrict,command="…/purser-gate"` ile yazar, kapının sshd
yapılandırmasını üretir, kapı birimini kutunun adresiyle sınırlar ve ufw ya da firewalld kuralı
ekler (yalnız nftables varsa eklenecek kuralı yazar). Kapının ana bilgisayar anahtarının parmak
izini yazar; kutu bunu karşılaştırmanızı ister. `purser-admit --revoke` kapıyı kapatır.

## 2. Kutu imajı

Docker'lı herhangi bir Linux makinede (ana sisteme hiçbir şey kurulmaz; arm64 programları üretim
kapsayıcısında proot + qemu ile çalışır, ana sistemin çekirdeğine hiçbir şey kaydedilmez):

```sh
image/build-image.sh --cache ./build-cache --out ./out [--setup-conf benim-setup.conf]
```

- Taban, Orange Pi Zero 3 için sabitlenmiş bir Armbian sürümüdür (Debian 12); sha256'sı betikte
  yazılıdır ve dosya kullanılmadan önce denetlenir.
- Kutunun gereksindiği bütün paketler imaja üretim sırasında kurulur. Çalışan kutu hiçbir zaman
  kod ya da paket çekmez: güvenlik duvarında buna kural yoktur, apt zamanlayıcıları maskelidir.
- İmajda: SSH sunucusu maskeli, root parolası kilitli (`*`), seri konsolda oturum açma yok (yerine kısıtlı
  `purser-console` çalışır), Wi-Fi ve Bluetooth kapalı, timesyncd yerine chrony, boş makine
  kimliği, SSH ana bilgisayar anahtarı yok.
- Sonuç: `out/noq-purser-<sürüm>-orangepizero3-<tarih>.img.xz` ve `.sha256` dosyası.
- İlk üretim uzun sürer (paket aşaması); sonrakiler onu yeniden kullanır (`--rebuild-base` baştan
  yapar).

**İsteğe bağlı gözetimsiz ilk açılış.** `image/setup.conf.example`'ı kopyalayıp doldurun ve
`--setup-conf` ile verin. Kutu onu bir kez okur ve siler. Kapıyı (ana bilgisayar anahtarını yalnız
`SERVER_HOSTKEY_FP` ile eşleşirse kabul ederek), kaynakları, pencereyi, bildirim kanalını, dili,
sabit adresi (`NET_ADDRESS`, `NET_GATEWAY`; boşsa DHCP), DNS'i, NTP'yi ayarlayabilir ve taşınmış
bir diski sahiplenebilir. **Yeni** disk her zaman seri konsolda hazırlanır, çünkü kurtarma
parolası tam bir kez gösterilir.

**Kartı yazın** (Linux ya da macOS):

```sh
image/flash.sh out/noq-purser-….img.xz /dev/sdX        # Linux; macOS: /dev/diskN (diskutil list)
```

İmajı `.sha256` dosyasıyla karşılaştırır; çalışan sistemin durduğu diski, bağlı sistem
disklerini, çıkarılamaz diskleri ve 256 GB'tan büyük diskleri reddeder (`--force-size`); yazmadan
önce aygıt adını geri yazmanızı ister.

## 3. İlk açılış

Kabloyu ve diski karta, Ethernet'i, hata ayıklama UART'ına USB-seri dönüştürücüyü (115200 baud)
bağlayın, kartı takın, gücü verin. İlk açılış servisi kullanıcıları ve anahtarları üretir, varsa
`setup.conf`'u uygular, güvenlik duvarını, chrony ve DNS ayarlarını uygular, öz sınamayı çalıştırır
ve gece işinin gerektirdiği her şey varsa (kapının ana bilgisayar anahtarı, bildirim kanalı, disk)
zamanlayıcıları açar. Yoksa seri konsolda `setup`'ı bekler; LED kalp atışı gösterir.

Seri konsolda (`purser>` istemi) `setup` sorar: dil, kapı adresi ve portu, kaynaklar (`KINDS`),
ilk soru saati, sorma aralığının sonu. Sonra:

1. Sunucuda çalıştırılacak `purser-admit` satırını kutunun adresi ve anahtarıyla yazar.
2. Kapının ana bilgisayar anahtarının parmak izini gösterir: `purser-admit`'in yazdığıyla
   karşılaştırın.
3. Bildirim kanalı: bir ntfy sunucusu (rastgele bir konu üretilir); ntfy uygulamasında abone
   olun; deneme iletisi gider.
4. Disk: yapılandırılmış disk yoksa **yeni** disk hazırlamayı önerir: tam bir USB disk takılı
   olmalı; `ERASE` yazın. LUKS2 kurar (ölçüme göre AES-XTS ya da Adiantum), rastgele anahtar
   dosyası ve **bir kez gösterilen kurtarma parolası** ile (kâğıda yazın, son dört karakterini geri
   yazın); LUKS başlık yedeğini alır (`/etc/purser/sirlar/luks-baslik.img`; kâğıt paket için USB
   belleğe kopyalayın); btrfs'i ve düzeni kurar.
5. İşlem kodu: bir kez gösterilir; kâğıda yazın (kutunun üstüne değil), geri yazın.
6. Öz sınama.

Yeni disk sonra pencere tavanı olmadan ilk dolumu ister: `first-fill` (kod sorar; arka planda
çalışır; `status` ile izleyin). İlk dolumdan sonra gece zamanlayıcısı açılır. `status` ve
`selftest` ile denetleyin, `notify-test` ile deneme gönderin.

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
