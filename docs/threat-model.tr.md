# Tehdit modeli

[English](threat-model.md)

Başlangıç noktası: **korunan sunucu ele geçirilmiştir.** Saldırganın orada root yetkisi var,
sabırlı ve yetkin. Saldırganın dikkatsizliğine dayanan savunmalar (tuzak dosya, entropi, fidye
notu adı) koruma değil, sinyal sayılır.

## Neye karşı korur

| Durum | Sonuç |
| --- | --- |
| Sunucuda root yetkisi alan biri sunucudaki yedekleri siler ya da şifreler | Kutudaki geçmiş kalır |
| Sunucu geçerli özetlerle bozuk içerik ve `clean=yes` yayımlar | Kutu saklar ama hiçbir şey silmez; eski nesiller takvime göre kalır |
| Ele geçirilmiş sunucu kötü niyetli rsync akışı ya da kötü liste verir | rsync kum havuzunda çalışır, yalnız hazırlık alanına yazar; liste ve ağaç kutuda denetlenir; uymayan nesil reddedilir |
| Bir kaynak sessizce yedek üretmeyi bırakır | Sunucu `fresh=no` der (uyarı); kutu 2 gecedir değişmeyen kaynağı ayrıca bildirir |
| Sunucu nesil üretmeyi bırakır | Kutu her gece "nesil gelmedi" der, 30 saatte gecikme alarmı; bunun için sunucuya muhtaç değildir |
| Sunucu geçmişi hızlı yaşlandırmak için nesil tarihlerini uydurur | Saklama yayımlanan geceleri sayar; tarih silmeyi hızlandıramaz |

## Neye karşı KORUMAZ

| Durum | Neden |
| --- | --- |
| **Kutu ele geçirilir** | Disk anahtarı kutudadır ve disk kutuya takılıdır. Kutuyu yöneten diskin şifresini açıp silebilir. Tek disk vardır: geçmiş gider. Sunucuya bakan saldırı yüzeyi kum havuzundaki rsync istemcisidir. |
| **Yerinde yangın, hırsızlık, el koyma** | Kutu ve disk sunucunun yanında durur (aynı bina ya da arazi). İkisini birden yok eden ya da götüren şey geçmişi de götürür. Başka bir yerde kopya bu sürümün parçası değildir. |
| **Aylarca bozuk yedek üreten sabırlı saldırgan** | Kutu bozuk veriyi sadakatle saklar. Tek karşılık uzun saklama (12 ay) ve düzenli geri yükleme tatbikatıdır. Tatbikat yapılmıyorsa NOQ Purser kimseyi kurtarmaz. |
| **Disk parolasının ya da LUKS başlığının kaybı** | Kâğıttaki parola ve başlık yedeği yoksa geri yükleme yoktur. |
| **Yedeklenmeyen veri** | Kaynak listesi kurulumu yapanın sorumluluğudur. |
| **Kutunun başındaki kişi** | İşlem kodu bilinçli bir kilittir, sınır değildir: o kişi kutuyu, SD kartı ya da diski alıp götürebilir. |
| **Yazma boşaltmasını dürüst iletmeyen USB-SATA köprüsü** | Yayımlanmış nesiller salt okunurdur ve yalnız yayım anında yazılan meta veriyle bağlıdır. Köprü yapmadığı yazmayı yapıldı derse elektrik kesintisi tek diski bozabilir. Sınanmış köprü ve disk kullanın. |

## Tehditler ve karşılıkları

| Tehdit | Karşılık |
| --- | --- |
| Sunucuda root, sunucudaki yedekleri siler | Sunucunun kutuda silme yetkisi yok; kutu geçmişi tutar |
| Sahte "temiz" hükmüyle bozuk veri | Hüküm hiçbir yetki vermez; uzun saklama ve sabitlenmiş nesiller kalır |
| Boyut, zaman ve liste özeti korunarak içerik değiştirilir | Eşitlemeden sonraki ctime farkı ve dokunulan her dosyanın yeniden okunması: şüpheli |
| Toplu silme ya da toplu şifreleme | Aracın değişmez dosyaları değişti ya da silindi: şüpheli; büyük değişim: şüpheli ya da uyarı |
| Kötü liste satırı: yol aşımı, kontrol karakteri, yinelenen yol | Kutuda katı kalıp; nesil, disk açılmadan reddedilir |
| Kötü rsync: sembolik bağ, aygıt, sonsuz akış, dev dosya | `--no-links --no-specials --no-devices`, tür taraması, kum havuzu (yetkisiz kullanıcı, salt okunur sistem, sır yok, tek yazılabilir yol), dosya başına boyut tavanı, G/Ç zaman aşımı, süre tavanı |
| Kaynak sessizce durur | Sunucuda tazelik sorgusu; kutuda 2 gece değişmeyen kaynak |
| Depo çekme sırasında değişir | Nesil sunucuda dondurulur; yoksa liste tutmaz, gece başarı sayılmaz |
| Sunucu onay dosyalarını tahrif eder | Onay yalnız sunucunun kendi temizliğini yönetir; kutuda hiçbir şey ona bağlı değil |
| Sunucu nesil üretmeyi bırakır | Kutu penceresinde bekler, sonra bildirir; 30 saatte gecikme alarmı |
| Sunucu alarmları susturur | Kutunun bildirimi sunucudan geçmez |
| Sunucu nesil tarihi uydurur | Saklama geceleri sayar; bir saatten fazla ilerideki kimlik alınmaz |
| Saati kaydırmak için yerel NTP ele geçirilir | chrony ilk güncellemelerinden sonra 10 dakikadan büyük değişikliği reddeder; tekdüze saate göre sıçrama, ağ saatiyle uyuşmazlık ya da imaj tarihinden önceki saat o geceyi durdurur ve bildirilir; saklama saate bağlı değil |
| Bildirim adresi değişir | Her gönderimden önce yeniden çözülür; 443'e yalnız o adres izinli |
| Sunucu bildirime metin sokmaya çalışır | Bildirim yalnız çekirdeğin ürettiği durumu içerir; `note=` ve dosya adları asla gösterilmez |
| Kutu çalınır | Disk şifreli ama anahtar kutuda: koruma kaynakların kendi şifrelemesidir (borg/restic repokey, pgBackRest `repo-cipher-type`). Sunucuda kutunun anahtarını iptal edin (`purser-admit --revoke`), bildirim konusunu da |
| Yazma ortasında elektrik kesilir | Yayımlanmış nesiller salt okunur; hazırlık alanı sonraki gece yeniden kurulur; yukarıdaki köprü satırına bakın |
| LUKS başlığı bozulur | Kurulumda başlık yedeği alınır (kutudan uzakta, kâğıt paketin yanında tutun) |
| USB-SATA köprüsü takılır | USB aygıtı bir kez yazılımla yeniden başlatılır (authorized 0/1, olmazsa unbind/bind); yine yoksa acil bildirim. Güç anahtarı yok; kabloyu bir insan çıkarıp takmalı |
| Depo ya da sürüm ele geçirilir | Kutu hiç kod çekmez; yalnız SD kart, sha256'sı denetlenebilen betikle üretilmiş imajla değiştirilerek güncellenir. Sürüm imzası bu sürümde yok |

## Pilsiz saat

Kartta pilli saat yoktur. Açılışta saat bir kez ağdan alınır (chrony'nin ilk güncellemeleri).
Tam o anda NTP'yi yöneten yerel bir saldırgan kutuyu yanlış saatle başlatabilir. Sonuçları
sınırlıdır: saklama saati kullanmaz; kutunun saatinden bir saatten fazla ilerideki nesil
kimlikleri reddedilir; kod kilidi beklemesi ve gecikme alarmı şaşabilir. İmajın üretim
tarihinden önceki saat yakalanır.

## Hep takılı disk

Disk hiç kapatılmaz; pencere dışında kilitlidir (LUKS kapalı) ve bağlı değildir. Ayrı bir güç
anahtarı koruma katmazdı, çünkü onu da kutu sürerdi. Disk gece gündüz enerjilidir: önerilen disk
SSD'dir.

## Kutu neden küçük

Çekirdek, bir oturuşta okunabilecek birkaç bin satır Bash'tir. "Okunabilir" bir iddia,
"düşman girdiye karşı savunulmuş" başka bir iddiadır; ikincisi kodun boyutuna değil, katı liste
kalıplarına, kum havuzuna ve yetki ayrımına dayanır.

| Adım | Kim olarak | Yazabildiği | Okuyabildiği |
| --- | --- | --- | --- |
| Liste indirme, eşitleme | `purser-rsync`, systemd kum havuzu, ağlı | yalnız geçici alan / hazırlık alanı | hazırlık alanı ve SSH anahtarı |
| Liste ve ağaç denetimi, özet | `purser-dogrula`, kum havuzu, ağsız | hiçbir yer | hazırlık alanı, listeler |
| Uzun kopyaların budanması | `purser-rsync`, kum havuzu, ağsız | yalnız budanan kopya | o kopya |
| Yayım, saklama, kilitleme, onay | root | görüntü özellikleri ve durum alanı | hepsi; dosya ağaçlarında gezinmez |

Sırlar (`/etc/purser/sirlar`) ve durum alanı her kum havuzunun içinde erişilemezdir.
