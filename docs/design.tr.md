# NOQ Purser nasıl çalışır

[English](design.md)

Bu belge 1.0 sürümünü uygulandığı haliyle anlatır. Örneklerdeki adlar, sayılar ve tarihler
uydurmadır.

## Üç iddia

Sunucunuzun ele geçirildiğini varsayın. NOQ Purser saldırganın dikkatsizliğine değil, üç şeye
dayanır:

1. **Dinleyen portu olmayan kutu.** Bağlantıyı her zaman kutu başlatır; sunucu kutuya ulaşamaz.
2. **Sunucunun elinde olmayan silme yetkisi.** Geçmişi yalnız kutu, kendi takvimiyle siler.
   Sunucunun hiçbir sözü silme yetkisi vermez.
3. **Sunucuya güvenmeyen kutu.** Sunucudan gelen her şeyi (liste, dosya adı, dosya türü, içerik)
   kendisi denetler; uyarıyı ve şüpheyi kendi sinyallerinden çıkarır. Sunucunun "temiz" demesi
   kutuyu yalnız daha temkinli yapabilir.

## Kim ne yapar

| Taraf | Yapar | Yapamaz |
| --- | --- | --- |
| Sunucu (`purser-source`) | Gecenin yedek işleri bitince nesli dondurur, her kaynağa tazeliğini sorar, dosya listesini yazar, nesli kutu onaylayana kadar tutar | Kutuya bağlanmak; kutudaki herhangi bir şeyi silmek |
| Kapı (`purser-gate`) | Kutu anahtarının SSH zorunlu komutu: `latest`, salt okunur `rsync`, `ack <kimlik> [hüküm]` | Başka her şey (reddedilir, günlüğe düşer) |
| Kutu (`purser`) | Çeker, denetler, doğrular, yayımlar, saklama takvimini uygular, diski yeniden kilitler, onay yazar, alarm gönderir | Sunucuda onay dışında bir şey yazmak |
| Seri konsol (`purser-console`) | Sabit komutları çekirdeğe iletir | Karar vermek, yetki vermek, sunucudan gelen metni göstermek |
| İnsan | Geri yükleme tatbikatı, geri yüklenen nesli sabitleme, şüpheyi kutunun başında kaldırma, kâğıt paketi saklama | — |

## Gece, sunucu tarafı (`purser-source`)

1. **Bekleme.** Zamanlayıcıyla başlar (varsayılan 04:30), sonra saate değil bağımlılığa bakar:
   `WAIT_UNITS` içindeki, zamanlayıcısı açık her birim bu gece çalışmış ve bitmiş olmalı; araç
   kilitleri (pgBackRest backup/expire, borg `lock.*`, restic `locks/`) düşmüş olmalı.
   `WAIT_MAX_MIN` (240) içinde olmazsa o gece nesil üretilmez; kutu "nesil gelmedi" der.
2. **Dondurma öncesi komutlar** (`PRE_FREEZE_CMDS`, isteğe bağlı), ör. WAL değiştirmek için
   `pgbackrest check`.
3. **Dondurma**: her kaynak `generation/.build-<kimlik>/<ad>/` altına. `FREEZE=auto` önce reflink
   kopyayı dener (XFS, btrfs: bir saniye, ek yer tutmaz), sonra sabit bağı (aynı dosya sistemi;
   dosyayı yerinde yeniden yazmayan depolar için uygun), sonra tam kopyayı. Araçların geçici ve
   kilit dosyaları dondurulmuş kopyadan silinir. `A-Z a-z 0-9 . _ / + -` dışında ad ya da dosya
   veya dizin olmayan bir şey çalışmayı durdurur.
4. **Liste**: yalnız yeni ya da boyutu veya zamanı değişen dosyaların özeti yeniden hesaplanır,
   kalanı önceki çalışmanın önbelleğinden gelir.
5. **Tazelik**, kaynak başına: pgBackRest en yeni yedek etiketi, borg en yeni segment, restic en
   yeni anlık görüntü, düz dizin en yeni dosya (ya da `FRESH_CMDS`). `FRESH_MAX_H`'den (26 sa)
   eskiyse `fresh=no` ve not. Bayatlık uyarıdır, şüphe değil.
6. **Doğrulama**, dondurulmuş kopyada (`VERIFY_CMDS`, isteğe bağlı; ör. `pgbackrest verify`,
   `restic check`). Herhangi biri başarısızsa `clean=no`.
7. **Yayımlama**: `generation/<kimlik>/`, `generation/<kimlik>.list`, `generation/LATEST`.
8. **Tavan**: son onaylı nesil ve en yeni `KEEP_UNACKED` (3) nesil tutulur, kalanı silinir. Kutu
   uzun süre gelmese de sunucu şişmez.

`purser-source watch` (saatlik; uyarılar isteğe bağlı `ALERT_CMD` ile): `ACK_ALERT_H` (30) saattir
onay yok; kutu `BOX_WINDOW_START`–`BOX_WINDOW_END` dışında bağlandı. Bu uyarılar kolaylıktır,
güvence değildir: ele geçirilmiş sunucu onları susturabilir. Kutunun kendi kanalı sunucudan
geçmez.

## Liste

```
# purser-list 1
# generation=2026-01-14T03-10Z
# created=2026-01-14T03:11:52Z
# clean=yes
# fresh=yes
# note=pgbackrest verify ok
3f2a…e91c  pgbackrest/backup/demo/20260111-021500F/backup.manifest
…
```

- `#` başlık satırlarının altında `sha256sum` biçimi. Kutuda JSON ayrıştırıcı yok.
- İlk satır tam olarak `# purser-list 1`. `generation`, `clean` (`yes|no|unknown`) ve `fresh`
  (`yes|no`) zorunlu. Liste neslin tam ağacıdır; silinenler böylece görünür.
- Kutunun denetimi (`purser-verify list`): başlık `^# [a-z_]+=[A-Za-z0-9:._;, -]{0,200}$`; dosya
  satırı `^[0-9a-f]{64}  [A-Za-z0-9._/+-]+$`, yol en çok 1024 karakter; `/` ile başlayan yol,
  `.` ya da `..` bileşeni, boş bileşen, `/` ile biten yol, yinelenen yol ve başka bir yolun dizini
  olan yol yasak. Tek bir kötü satır nesli reddettirir.
- `note=` hiçbir bildirimde gösterilmez; yalnız günlüğe yazılır.

## Kapı

Kutunun sunucuda tek bir anahtarı var; ayrı bir sshd'de (`purser-sshd`: kendi portu, adresi ve
ana bilgisayar anahtarı; ana sshd'ye dokunulmaz):

```
from="192.0.2.20",restrict,command="/usr/local/sbin/purser-gate" ssh-ed25519 AAAA… purser
```

| İstek | Etkisi |
| --- | --- |
| `latest` | en yeni yayımlanmış nesil kimliğini yazar |
| `rsync --server --sender …` | `rrsync -ro generation/` |
| `ack <kimlik> [tamam\|uyari\|supheli]` | `ack/<kimlik>` dosyasına hükmü ve zamanı yazar; kimlik biçimi ve neslin varlığı denetlenir |

Başka her istek reddedilir ve günlüğe düşer. Hüküm sözcükleri protokolün parçasıdır, değişmez.

## Gece, kutu tarafı (`purser run`)

Disk hep takılıdır ve pencere dışında **kilitli** durur (LUKS kapalı, bağlı değil).

1. **Saat kapısı.** Saate güvenilemiyorsa (bkz. "Saat") o gece nesil alınmaz, sunucuya
   sorulmaz bile, bildirim gider.
2. **Bekleyen onay** önceki pencereden kaldıysa önce o gönderilir. Bu başarı sayılmaz.
3. **Yeni nesil, disk kilitliyken.** `POLL_UNTIL`'e (08:30) kadar `POLL_EVERY`'de (5 dk) bir
   `latest` sorulur. Kimlik son yayımlanandan yeni ve en çok bir saat ileride olmalı. Gelmezse
   "sunucu bu gece nesil üretmedi"; diskin şifresi hiç açılmaz.
4. **Liste denetimi, disk kilitliyken.** Liste SD kartın geçici alanına indirilir ve denetlenir
   (yukarıda). Reddedilen nesil diski hiç açtırmaz.
5. **Disk.** USB aygıtı LUKS UUID'siyle bulunur; yoksa ya da küçük bir okumaya yanıt vermiyorsa
   köprü bir kez yazılımla yeniden başlatılır (yetki kaldır/ver, olmazsa unbind/bind) ve yeniden
   beklenir; yine yoksa acil bildirim. Sonra LUKS açılır, bağlanır.
6. **Hazırlık alanı**: son yayımlanan neslin yazılabilir btrfs görüntüsü. Önceki geceden kalan
   yarım hazırlık alanı korunur ve tamamlanır. Kutu her zaman en yeni nesle gider.
7. **Eşitleme**: rsync kum havuzunda, yalnız hazırlık alanına yazar; `--delete --no-links
   --no-specials --no-devices`, dosya başına boyut tavanı, G/Ç zaman aşımı, pencere tavanı.
   Dökümü ayrıştırılmaz. Ardından hazırlık alanında düz dosya ya da dizin olmayan bir şey nesli
   reddettirir; ağaç tam olarak listedeki dosyaları içermelidir.
8. **Değişenler**, iki kaynaktan: liste farkı (yeni ya da başka özet) ve eşitlemeden önce bırakılan
   işaretten yeni ctime'lı her dosya (`find -cnewer`). rsync ctime'ı koruyamaz; boyutu, zamanı ve
   eski özeti tutup içeriği değiştiren sunucu böyle yakalanır.
9. **Doğrulama**: değişen her dosya diskten geri okunup özetlenir. Liste özeti değişmediği halde
   içeriği değişen dosya → `list_hash_lie` (şüphe; saklanan liste gerçek özeti yazar). Hiçbir şey
   aktarılmadığı halde liste özeti değişen dosya `--checksum` ile yeniden çekilir; içerik o zaman
   farklıysa sessiz değişikliktir (şüphe). Diğer uyuşmazlıklar geceyi başarısız kılar.
10. **Sinyaller** (aşağıda).
11. **Yayımlama**: denetim dosyaları önce `.pending` olarak yazılır, sonra salt okunur
    `nesil/gen-<kimlik>` görüntüsü alınır, sonra denetim dosyaları yeniden adlandırılır. Arada
    elektrik kesilirse bir sonraki çalışma tamamlar ya da geri alır.
12. **Uzun saklama**: uzun saklama gününde (bkz. "Saklama") yazılabilir bir kopya kum havuzunda
    budanır ve `nesil/uzun-<kimlik>` olarak salt okunur yapılır.
13. **Saklama, bakım**, ardından **disk kilitlenir**: sync, bağlantı kesme, LUKS kapatma; kutu
    eşleyici aygıt ve bağlama kalmadığını denetler, kaldıysa acil bildirim.
14. **Onay** `ack <kimlik> <hüküm>`. Gidemezse bekleyen onay olarak saklanır.
15. **Alarm**, gerekirse. Sessiz gece iyi gecedir.

Başarı: yeni bir nesil denetlendi, doğrulandı, yayımlandı ve disk yeniden kilitlendi. Yeniden
işleme, bekleyen onay ya da yarım aktarım başarı değildir.

Pencere tavanı `MAX_MIN` (80 dakika): sonrasında yeni iş başlamaz, yarım hazırlık alanı sonraki
geceye kalır. `first-fill` (konsolda) tavansızdır.

## Sinyaller

| Seviye | Ne zaman | Sonuç |
| --- | --- | --- |
| **Uyarı** | sunucu `fresh=no` dedi; aktarım, aynı haftanın günü için son 4 haftanın ortancasının `WARN_FACTOR` (3) katını aştı; bir kaynak `STALE_NIGHTS` (2) gecedir hiç değişmedi; en yeni pgBackRest etiketi `LABEL_MAX_DAYS` (2) günden eski | bildirim, LED "tamam"dan çıkar, silme sürer |
| **Şüpheli** | sunucu `clean=no` dedi; değişmemesi gereken dosya değişti; olağan temizlik dışında silme; yalan söyleyen liste özeti; sessiz değişiklik; toplu silme ya da toplu değişiklik (≥ %50 ve ≥ 20 dosya) | nesil saklanır ve işaretlenir, otomatik silme durur |

Kaynak türü kuralları (`purser.conf` içinde `KINDS="tür:dizin[:budama günleri]"`):

- **pgBackRest**: yedek etiketi dizinindeki dosyalar ve WAL segmentleri değişmez. Olağan temizlik
  bütün bir etiket dizinini ya da arşivin en eski segmentlerini siler, yalnız budama gününde.
  Etiket içinden tek tek dosya silmek, arşivin ortasından silmek ya da başka günde silmek
  şüphelidir. Bilgi dosyaları şifreli olduğundan kurallar yalnız dosya adlarına bakar.
- **borg**: `data/` altındaki segmentler değişmez (compact yenisini yazıp eskisini siler); segment
  silmeye yalnız budama gününde izin var.
- **restic**: `data/ index/ snapshots/ keys/` altındaki nesneler değişmez ve içeriklerinin
  SHA-256'sıyla adlandırılır (denetlenir); silme yalnız budama gününde.
- **dir**: değişmez kalıp yok; toplu kurallar ve bayat kaynak kuralı geçerli.

Bu sinyaller dikkatsiz saldırganı yakalar; güvenlik iddiası değildir. Yetkin saldırgan hepsinden
kaçabilir. Onun karşılığı saklama takvimi ve geri yükleme tatbikatıdır.

### Şüpheli nesil

- **Son sağlam nesil**, kaldırılmamış ilk şüpheliden önceki nesildir. Sonrakiler de sağlam
  sayılmaz: bozuk veri sonraki nesillere taşınmış olabilir. Gecikme alarmı ve LED son sağlam nesle
  göre çalışır.
- **Otomatik silme durur**; biri kutunun başında şüpheyi kaldırana kadar (`clear <kimlik>`, işlem
  koduyla; önce neden gösterilir). Kutu her gece silmenin kaç gündür durduğunu bildirir.
- **Silme dururken disk dolarsa**: hiçbir eski nesil silinmez, yeni nesil alınmaz, her gece
  bildirim gider. Korunması gereken eski geçmiştir.

## Saklama

- 14 günlük, 8 haftalık, 12 aylık nesil (`KEEP_DAILY`, `KEEP_WEEKLY`, `KEEP_MONTHLY`).
- Haftalık kopya her haftanın `LONG_DOW` (7 = pazar) günündeki ya da ondan sonraki ilk nesilden
  kesilir; haftalık tam yedeğin günü. Aylık kopya, bir ayın ilk haftalık kopyasıdır.
- **Saklama geceleri sayar, tarihe güvenmez.** Nesil kimliğini sunucu verir, kutunun saati ağdan
  gelir; ikisi de yalan söyleyebilir. Haftalık kesim için önceki kesimden bu yana `LONG_MIN_NIGHTS`
  (4) yayımlanmış nesil, aylık seçim için önceki seçimden bu yana `MONTHLY_MIN_WEEKS` (3) haftalık
  kesim gerekir; kutu gecede en çok bir nesil yayımlar. Sahte tarihler kutuya geçmişi daha uzun
  tutturabilir, hiçbir zaman daha hızlı sildiremez.
- **Uzun kopyaların budanması**: haftalık ve aylık pgBackRest kopyasında yalnız en yeni tam yedek
  ve bilgi dosyaları kalır; WAL ve fark yedekleri atılır (kum havuzunda, ayrı bir yazılabilir
  görüntüde). `archive-copy=y` ile tam yedek gereken WAL'ı kendi içinde taşır; geri yüklemesi
  `--type=none` ile. borg, restic ve düz dizin olduğu gibi kalır.
- Sabitlenmiş nesil (`pin <kimlik>`) otomatik silinmez. En yeni günlük nesil silinmez.
- **Disk dolarsa**: şüpheli yoksa yalnız en eski günlük nesiller, `DISK_MIN_FREE_PCT` (%10) boş
  kalana kadar silinir; haftalık, aylık, sabitlenmiş ve en yeni günlük böyle silinmez. Şüpheli
  varsa: hiçbir şey silinmez, yeni nesil alınmaz.

Kaba disk boyutu:

```
tam yedek × (haftalık + aylık kopya sayısı)
+ bir haftalık değişim × 3
+ borg/restic depoları × 1,5
```

## Saat

Kartta pilli saat yok. Saat ağdan gelir (chrony; `NTP_SERVERS`, ör. yönlendirici, ve
`NTP_POOL`), korunan sunucudan asla.

- Açılışta chrony ilk güncellemelerinde saati atlatabilir; sonra `CLOCK_JUMP_MAX`'tan (600 sn)
  büyük her değişikliği reddeder.
- Saate **güvenilir**: chrony eşitlenmişse, ağ saati kutunun saatiyle uyuşuyorsa, saat son bir
  saat içinde tekdüze saate göre sıçramamışsa ve imajın üretim tarihinden önce değilse.
- Güvenilmeyen saat → o gece nesil yok, sunucuya sorulmaz, disk kilitli kalır, bildirim (tür
  başına günde en çok bir kez). Güvenilmeyen saatte gecikme alarmı gönderilmez.

## Ağ

nftables gelen her şeyi düşürür (yalnız DHCP yanıtları ve kutunun kendi bağlantılarının
yanıtları). Giden yalnız: sunucu kapısı (tek adres, tek port), NTP (`NTP_SERVERS`, varsayılan
modem), DHCP ve yapılandırılmışsa DNS (`DNS_SERVERS`, varsayılan boş: kutunun ada ihtiyacı yok).
Paket indirmeye kural yoktur: kurulumdan sonra kutu kod ya da paket çekemez. Wi-Fi ve Bluetooth
modülleri kara listede; yalnız kablolu.

Bakım anahtarı açıkken (`purser-maint`, bir GPIO girişi) iki ek zincir yerel ağa sayfayı (HTTPS
443) ve SSH'yi (22, yalnız anahtarla, yalnız kartla bir anahtar geldiyse) açar, mDNS `<kimlik>.local`
adını duyurur. Kapatmak ya da izleyicinin ölmesi o zincirleri boşaltır ve hizmetleri durdurur.
Açık kaldıkça iki saatte bir hatırlatma gider.

## Bildirim

Yalnız alarm ("tamamlandı" dışındaki her şey; "tamamlandı" günlüğe ve onay olarak sunucuya
gider). Alarm aynı kapıdan geri gider: `note <olay>`, sabit bir alfabe (`[a-z_]`, en çok 32
karakter); sunucu kaydeder ve `ALERT_CMD` ile yükseltir. Metin kutuda kalır (günlük, sayfa):
yalnız çekirdeğin ürettiği durumu taşır (katalog metni, sayılar, nesil kimlikleri, neden kodları);
sunucudan gelen dosya adı, yol, not ya da içerik asla. Kutu eşleşene ya da kapıya ulaşılana kadar
alarmlar kuyrukta bekler ve saatte bir yeniden denenir (en yeni 50). Üçüncü taraf hizmet yok,
internet yok. Dil: `LANG_UI=en|tr`.

## Kutunun başında

Ekran yok. Durum LED çubuğunda (bkz. [hardware.tr.md](hardware.tr.md)), bakım anahtarı açıkken
`https://<kimlik>.local` sayfasında (işlemleri işlem kodu ister) ve `status` komutunda. Seri konsolu
kullananlar için oturum açma yerine kısıtlı `purser-console` çalışır:

| Komut | Kod | Ne yapar |
| --- | --- | --- |
| `status` | hayır | son sağlam nesil ve yaşı, dün gecenin sonucu, şüphe nedeni, silme duraklaması, bekleyen onay, disk doluluğu, SMART özeti, son scrub, imaj yaşı, disk kilitli/açık, saat |
| `clear <kimlik>` | evet | `<kimlik>`in neden şüpheli olduğunu gösterir, sonra kaldırır (`CLEAR` yaz) |
| `pin <kimlik>` | evet | nesli sabitler (ör. geri yüklemesi denenmiş nesil) |
| `disk-on` | evet | diskin şifresini elle açar ve bağlar; `DISK_ON_MIN` (30) dakika sonra yeniden kilitler |
| `disk-off` | hayır | diski kilitler |
| `first-fill` | evet | pencere tavanı olmadan ilk dolum, arka planda |
| `selftest` | kod varsa evet | USB'de disk, bağlantı hızı, SMART, ağ, saat |
| `setup` | kurulumdan sonra evet | kurulum sihirbazı |
| `setup-code` | hayır (yalnız kod yoksa) | ilk işlem kodunu üretir |
| `new-code` | evet | yeni işlem kodu |
| `reset-code` | hayır | eski kod olmadan yeni kod; **her zaman bildirilir** |
| `notify-test` | hayır | deneme bildirimi |
| `shell` | evet | bakım kabuğu; **her zaman bildirilir** |

**İşlem kodu**: dörtlü üç grup, 12 rakam (`4821 0937 5562`); son rakam Damm sağlama rakamı (her
tek rakam hatasını ve yan yana iki rakamın her yer değişimini yakalar; yazım hatası yanlış deneme
sayılmaz). Kutu kodu kendisi üretir, bir kez gösterir, geri yazdırır ve SD kartta yalnız argon2id
özetini tutar. Üç yanlıştan sonra her seferinde iki katına çıkan bekleme başlar, 1 dakikadan 24
saate kadar; yeniden başlatma sıfırlamaz; kilitlenme bildirilir. Bilinçli bir işlem kilididir,
güvenlik sınırı değildir: kutunun başındaki kişi kutuyu alıp da götürebilir. Kod ağdan geçmez.
Konsol rakamları çekirdeğe iletir, saklamaz.

**Kâğıtta iki ayrı anahtar, karışmaz:**

| | Disk kurtarma parolası | İşlem kodu |
| --- | --- | --- |
| İşe yarar | diski başka bir makinede açar | kutunun başındaki komutları onaylar |
| Girildiği yer | geri yüklemede bir bilgisayara | seri konsola |
| Gücü | uzun; çalınan diski korur | kısa; bilinçli kilit |
| Kaybolursa | geri yükleme olmaz | yenisi üretilir; veri etkilenmez |

Disk parolası kutuya hiçbir zaman girilmez.

## Bakım (pencerede, kalan sürede)

- Ayda bir SMART (köprü üzerinden `smartctl -d sat`).
- btrfs scrub, pencereden pencereye sürer; ayda bir tam tur.
- Değişmeyen dosyaların tam özet taramasından bir dilim; imleç SD kartta (boyuta göre yaklaşık
  ayda bir tur).

## SD kart

Tek kök dosya sistemi (Armbian imajı). Durum ve sırlar ayrı dizinlerdedir:

| Yol | İçerik |
| --- | --- |
| `/etc/purser/purser.conf` | yapılandırma (sır yok) |
| `/etc/purser/sirlar/` | LUKS anahtar dosyası, LUKS başlık yedeği, bildirim adresi (yalnız root) |
| `/etc/purser/ssh/` | kutunun SSH anahtarı (rsync kullanıcısının) ve kapının ana bilgisayar anahtarı |
| `/var/lib/purser/` | durum: son yayımlanan / son sağlam nesil, bekleyen onay, son liste, sinyal geçmişi, kod özeti ve deneme sayacı, bildirim kuyruğu, bakım imleçleri |

Diskteki adlar (`nesil/gen-*`, `nesil/uzun-*`, `denetim/{liste,meta,supheli,temiz,pin}`,
`hazirlik`) ve durum dosyası adları İngilizce kod tabanından eskidir; biçimin parçasıdır,
değişmez.

**Güncelleme**, yeni üretilmiş imajlı SD kartı takıp durumu taşımaktır
(`image/purser-card-migrate`); kutu kendini hiç güncellemez. 6 ay dolunca kutu yeni imaj ister.

## Deponun kendisi de hedef

Arka kapı yerleştirilmiş bir yedek aracı, hiç yedek aracı olmamasından kötüdür.

- Kutu hiç kod çekmez; güncelleme SD kartı değiştirmektir.
- Yalnız dağıtım paketleri; başka bağımlılık yok.
- İmaj, sabitlenmiş ve özeti denetlenen bir tabandan betikle üretilir; sha256'sını onunla
  yayımlayın. Bit bit yeniden üretilebilirlik hedeftir, iddia değildir.
- Sürümler, hiçbir sunucuda ya da sunucunun sır kasasında değil, donanım anahtarında duran bir
  anahtarla imzalanmalı: "sunucunuzun ele geçirildiğini varsayın" diyen bir proje imza anahtarını
  orada tutamaz. İmza bu sürümde yok.
- Kod bir oturuşta okunacak kadar küçük kalır.

## Elenen seçenekler

| Seçenek | Neden olmaz |
| --- | --- |
| Bulut yedek | Kapsam dışı: NOQ Purser sunucuyla aynı ağdaki fiziksel kopyadır, buluta alternatif değil |
| Hazır NAS | 7/24 ağda; kendisi hedef olur |
| Rastgele pencere saati | Koruma katmaz, yanlış alarm üretir, pencere dışı bağlantı uyarısını anlamsız kılar |
| Yarım kalmış eski nesli tamamlamak | Sunucunun tavanı onu silebilir; kutu her zaman en yeniye gider |
| Disk anahtarını sunucudan almak | Kutuyu sunucuya bağımlı yapar; kaynaklar zaten kendi araçlarıyla şifreli |
| Sunucunun "temiz" hükmüne göre silmek | Ele geçirilmiş sunucu sağlam geçmişi yaşlandırıp sildirebilir |
| Ad denetimini sunucuya bırakmak | Ele geçirilmiş sunucu kuralı çalıştırmaz; denetim kutuda |
| Değişen dosyaları rsync dökümünden çıkarmak | Düşman girdiyi ayrıştırmak demek; yerine liste farkı ve ctime farkı |
| Her gece tam özet taraması | USB 2.0'da pencereye sığmaz; değişenler geri okunur, kalanı dilim dilim |
| Büyük değişimi tek başına şüpheli saymak | Yoğun gün, göç ya da yeni kaynak her hafta yanlış alarm üretir; uyarıdır |
| Şüpheyi yalnız disk sökerek kaldırmak | Her yanlış alarmda çok pahalı; işlem koduyla seri konsol yeter |
| Uzun saklamada WAL taşımak | Farklı haftaların nesilleri blok paylaşmaz; saklama birkaç kat pahalanır |
| Tuzak dosya ve entropiyi güvenlik iddiası yapmak | Yetkin saldırgan atlatır; yalnız dikkatsize karşı sinyal |
| Diskin gücünü kesen röle | Onu kutu sürerdi: kutuyu yöneten röleyi de yönetir. Koruma yok, bir arıza kaynağı daha |
| Pilli saat modülü | Saat ağdan gelir, güvenilmeyen saat geceyi durdurur, saklama geceleri sayar |
| Kutudan bağımsız zaman kilidi | Tek diskte güvenlik katmaz, yalnız arıza kaynağı |
| İkinci (aylık) disk | Bu sürümün kapsamı dışında |
| Kutuyu ağdan güncellemek | İkinci bir güven yolu; rsync açıklarına karşılık kum havuzu ve denetimdir |
| Çok kanallı bildirim kütüphanesi | Dağıtım dışı bağımlılık; `curl` yeter |
| Kutuda ekran ve düğmeler | Fazladan parça ve süreç; durum `status`'ta, bildirimde ve kart LED'inde |
| Kutuda ağdan erişilen arayüz ya da API | Dinleyen servis demek |
| Seri konsolun korumasız kalması | Kodu anlamsız kılar; her yol kodu ister, yalnız kod sıfırlama bildirimli istisnadır |
| Disk parolasını kutuya girmek | Gerekmez; parola yalnız geri yüklemede bir bilgisayara girilir |
| Tek kullanımlık kod listesi | Tek kod, deneme sınırı ve yenileme yeter |
| Sabitlemenin sunucudan gelmesi | Ele geçirilmiş sunucu zehirli nesli sabitler |
| Herkese açık canlı saldırı yarışması | Yabancılara root verilen sunucu saatler içinde kötüye kullanılır |

## Bu sürümde olmayanlar

Salt okunur kök dosya sistemi ve ayrı durum bölümü; hazırlık alanında btrfs kotası (tavanlar
dosya başına boyut, G/Ç zaman aşımı ve süredir); WireGuard üzerinden uzak kurulum; imzalı
sürümler; FIDO anahtarı; basılabilir kutu. Bu depoda hiçbir yerde iddia edilmezler.
