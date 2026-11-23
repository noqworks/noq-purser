# Changelog / Değişiklikler

## 1.1.0 — 2026-11-23

### English

- **Server side survives a reboot and pgBackRest's `latest` link.** The nightly freeze removes pgBackRest's
  `latest` symlink from the frozen copy (restore reads `backup.info`); before, a repository with the link failed the
  night with "entries that are neither file nor directory". After a server reboot the wait step reads the journal to see
  that tonight's backup jobs finished, instead of waiting out its four hours.
- **Read-back now reads the disk, and damaged copies heal.** A restore drill on the bench box (23 Nov, isolated container,
  generation mounted read-only) restored the database cleanly but found 7 borg segment files in the first generation with
  holes: size and mtime right, parts of them never on the disk. The per-file check had hashed the page cache rsync had just
  filled. Now: caches are dropped before the read-back so it reads the disk; every night files with holes are removed from
  staging so they are pulled again and read back (size and mtime alone made rsync skip them); a file with holes after the
  transfer fails the night.
- **First fill reads the disk once.** The first generation is checked file by file against the list
  while it is written; the whole-disk scrub and the full hash scan that used to follow it are
  skipped, and the monthly scrub cycle starts from that night. On the bench box this would have
  saved hours over USB 2.
- **The page lists published generations.** The core writes a `nesiller` state file
  (`<id> <gunluk|uzun> <bytes>`) after publish and retention, while the disk is open; the page reads
  it. Before, the list came from the transfer history, which skips the first generation and keeps
  ids that retention removed, so a box with a good first backup showed "no generation yet".
- **"Open the disk (30 min)" on the page.** With the maintenance switch on, the page can unlock the disk for
  inspection or a restore drill after the operation code, like every action; it locks itself again after 30 minutes.
- **Light animations are on by default** (`LIGHT_ANIM=1`): with the stick fix in place (diode, capacitor, DIN resistor)
  the stick shows no random colours (verified on the bench box, 23 Nov), so maintenance breathes purple again instead
  of a fixed tint that was hard to tell from the state. Sticks without the fix: set `LIGHT_ANIM=0`.
- **Live transfer card and live disk usage** on the page (rate, received, phase).
- **Light.** Softer light with the cause on two LEDs; a disk that is missing or not answering is
  shown at once (udev) on the light and the page; neither the hourly tick nor anything else outside
  a running job draws over its light; steady states on the light stick; warm white on RGBW sticks.
- **Why a transfer stopped** is said: disk dropped off USB, unfinished first fill, or time out.
- **"Check the disk" card** on the page (slow USB link, drops, missing) with the disk pins drawn.
- **Case r1b** (STL, STEP, CadQuery source, print and assembly notes) replaces r1: upright USB-C /
  USB-A openings measured from a CAD model of the board, relief for the micro-HDMI nose, the tray
  lip no longer prints in mid-air, the switch ring is solid with a modelled M6 × 0.75 thread.
- **Tests and image** always build on a freshly pulled, patched base and leave nothing behind.
- **Docs:** the box sits on the same network as the server, in another room or building, not next
  to it.

### Türkçe

- **Sunucu tarafı yeniden başlatmaya ve pgBackRest'in `latest` bağlantısına dayanıyor.** Gece dondurmada pgBackRest'in
  `latest` sembolik bağlantısı kopyadan çıkarılıyor (geri yükleme `backup.info`'yu okur); önceden bağlantılı depo geceyi
  "dosya ya da dizin olmayan girdiler" ile düşürüyordu. Sunucu yeniden başladıktan sonra bekleme adımı o gecenin yedek
  işlerinin bittiğini günlükten okuyor, dört saat beklemiyor.
- **Geri okuma artık diskten yapılıyor, bozuk kopyalar kendini onarıyor.** Tezgâhtaki kutuda geri yükleme tatbikatı
  (23 Kas, izole konteyner, nesil salt okuma bağlı) veritabanını sorunsuz geri yükledi ama ilk nesilde 7 borg segment
  dosyasında delik buldu: boyut ve tarih doğru, bir kısmı diske hiç yazılmamış. Dosya dosya denetim, rsync'in az önce
  doldurduğu bellek önbelleğini okumuştu. Şimdi: geri okumadan önce önbellek boşaltılıyor, okuma diskten yapılıyor; her gece
  delikli dosyalar hazırlık alanından silinip yeniden çekiliyor ve geri okunuyor (yalnız boyut ve tarih yüzünden rsync onları
  atlıyordu); aktarımdan sonra delikli dosya kalırsa gece başarısız sayılıyor.
- **İlk dolumda disk bir kez okunur.** İlk nesil yazılırken dosya dosya listeyle denetlenir; ardından
  gelen tam disk taraması (scrub) ve tam özet taraması yapılmaz, aylık tarama sayacı o geceden
  başlar. USB 2 üzerinden bu saatler kazandırır.
- **Sayfa yayımlanmış nesilleri gösterir.** Çekirdek, disk açıkken yayından ve saklama kuralından
  sonra `nesiller` durum dosyasını (`<kimlik> <gunluk|uzun> <bayt>`) yazar; sayfa onu okur. Önceden
  liste aktarım geçmişinden geliyordu; o geçmiş ilk nesli atlıyor, saklama kuralının sildiklerini
  tutuyordu. Bu yüzden ilk yedeği sağlam alınmış kutu "henüz nesil yok" diyordu.
- **Sayfada "Diski aç (30 dk)".** Bakım anahtarı açıkken sayfa, her işlem gibi işlem kodunu alıp diski inceleme ya da geri yükleme tatbikatı için açar;
  30 dakika sonra kendiliğinden kilitlenir.
- **Işık animasyonları varsayılan olarak açık** (`LIGHT_ANIM=1`): çubuk düzeltmesi takılıyken (diyot, kondansatör,
  DIN direnci) rastgele renk görülmedi (tezgâh kutusu, 23 Kas); bakım yeniden mor nefes alıyor, durumdan ayırt
  edilmesi zor sabit bir ton yerine. Düzeltmesiz çubukta `LIGHT_ANIM=0`.
- **Canlı aktarım kartı ve canlı disk doluluğu** (hız, alınan, aşama) sayfada.
- **Işık.** Daha yumuşak ışık, nedeni iki LED'de; yok olan ya da yanıt vermeyen disk hemen (udev) ışıkta
  ve sayfada; saatlik tetik ve çalışan iş dışındaki hiçbir şey onun ışığının üstüne çizmez; ışık
  çubuğunda sabit durumlar; RGBW çubuklarda sıcak beyaz.
- **Aktarımın neden durduğu** söylenir: disk USB'den düştü, ilk dolum bitmedi ya da süre doldu.
- **"Diski denetle" kartı** sayfada (yavaş USB bağlantısı, kopmalar, yokluk), disk pinleri çizimli.
- **Kasa r1b** (STL, STEP, CadQuery kaynağı, baskı ve montaj notları) r1'in yerine: kartın CAD
  modelinden ölçülmüş dik USB-C / USB-A açıklıkları, mikro HDMI çıkıntısı için boşluk, taban dudağı
  artık havada basılmıyor, anahtar halkası tam dolu ve modellenmiş M6 × 0,75 dişli.
- **Testler ve imaj** her zaman yeni çekilmiş, yamalı bir taban üzerinde derlenir ve geride bir şey
  bırakmaz.
- **Belgeler:** kutu sunucunun yanında değil; aynı ağda, başka bir odada ya da binada durur.

## 1.0.0 — 2026-11-21

### English

First release of the rewritten code base (English code, message catalog in English and Turkish).

- **Plain hardware.** The box is a board, an unmodified USB-SATA cable and a disk. The relay,
  the voltage sense, the external LEDs, the battery clock module, the GPIO service and their
  configuration keys are removed. A `purser.conf` written by the prototype still loads: keys it
  no longer knows are ignored.
- **Always-attached disk.** Outside the window the disk is locked (LUKS closed, not mounted);
  "closed" is checked as "no mapper device and no mount" and a failure is notified. A disk that is
  missing or does not answer is recovered with one software reset of its USB device
  (authorized 0/1, else unbind/bind); otherwise an urgent notification.
- **Board LED** under `/sys/class/leds` if the board has one (`BOARD_LED`), silent otherwise.
- **Clock gate.** Time from chrony only. With an unsynchronised clock, a jump against the
  monotonic clock, disagreement with network time or a clock earlier than the image build, no
  generation is taken and a notification goes out.
- **Retention counts nights.** Weekly cuts need `LONG_MIN_NIGHTS` published generations since the
  previous cut, monthly picks `MONTHLY_MIN_WEEKS` weekly cuts; forged dates cannot speed up
  deletion.
- **Self-test** reduced to: disk on USB, link speed, SMART through the bridge, network, clock.
- **Operation code** (12 digits, Damm check digit, argon2id, doubling lock 1 min → 24 h, lock and
  reset notified) for `clear`, `pin`, `first-fill`, `disk-on`, `new-code`, `shell`, `setup`. FIDO
  support is not part of this release. A card moved from the prototype has no code: the nightly job
  runs anyway and a weekly reminder asks for `setup-code`.
- **Server side** rewritten as a site-independent `purser-source` (freeze: reflink → hard links →
  copy; verification and freshness commands from the configuration; optional `ALERT_CMD`; alert
  when no acknowledgement for 30 h, also when the box never acknowledged), `purser-gate` reading
  its base directory from the configuration, `purser-admit`, and a re-runnable `install.sh` with
  `--uninstall`. The installer replaces symlinked programs and units instead of writing through
  them.
- **Image**: `image/build-image.sh` builds the SD card image from a pinned Armbian release with
  all packages preinstalled; `image/flash.sh` (Linux, macOS) and `image/purser-card-migrate`.
- **Unchanged formats**: disk layout (`nesil/gen-*`, `nesil/uzun-*`, `denetim/…`, `hazirlik`), SD
  state files, list format `# purser-list 1`, gate protocol (`latest`, `rsync`, `ack <id>
  tamam|uyari|supheli`).

### Türkçe

Yeniden yazılmış kod tabanının ilk sürümü (kod İngilizce, ileti kataloğu İngilizce ve Türkçe).

- **Sade donanım.** Kutu bir kart, kesilmemiş bir USB-SATA kablo ve bir disktir. Röle, gerilim
  ölçümü, harici LED'ler, pilli saat modülü, GPIO servisi ve yapılandırma anahtarları çıkarıldı.
  Prototipin yazdığı `purser.conf` yüklenmeye devam eder: artık bilinmeyen anahtarlar yok sayılır.
- **Hep takılı disk.** Pencere dışında disk kilitlidir (LUKS kapalı, bağlı değil); "kapalı"
  "eşleyici aygıt yok ve bağlama yok" diye denetlenir, olmazsa bildirilir. Görünmeyen ya da yanıt
  vermeyen disk, USB aygıtının bir kez yazılımla yeniden başlatılmasıyla (authorized 0/1, olmazsa
  unbind/bind) geri getirilir; olmazsa acil bildirim.
- **Kart LED'i**: kartta varsa `/sys/class/leds` altından (`BOARD_LED`), yoksa sessiz.
- **Saat kapısı.** Saat yalnız chrony'den. Eşitlenmemiş saat, tekdüze saate göre sıçrama, ağ
  saatiyle uyuşmazlık ya da imaj tarihinden önceki saatle nesil alınmaz, bildirim gider.
- **Saklama geceleri sayar.** Haftalık kesim için önceki kesimden bu yana `LONG_MIN_NIGHTS`
  yayımlanmış nesil, aylık seçim için `MONTHLY_MIN_WEEKS` haftalık kesim gerekir; sahte tarih
  silmeyi hızlandıramaz.
- **Öz sınama** şunlara indi: USB'de disk, bağlantı hızı, köprüden SMART, ağ, saat.
- **İşlem kodu** (12 rakam, Damm sağlama rakamı, argon2id, 1 dk → 24 sa katlanan kilit, kilit ve
  sıfırlama bildirimli): `clear`, `pin`, `first-fill`, `disk-on`, `new-code`, `shell`, `setup`.
  FIDO bu sürümde yok. Prototipten taşınan kartta kod yoktur: gece işi yine çalışır, haftalık
  hatırlatma `setup-code` ister.
- **Sunucu tarafı** siteden bağımsız yeniden yazıldı: `purser-source` (dondurma: reflink → sabit
  bağ → kopya; doğrulama ve tazelik komutları yapılandırmadan; isteğe bağlı `ALERT_CMD`; 30 saat
  onay yoksa uyarı, kutu hiç onay yazmadıysa da), taban dizini yapılandırmadan okuyan `purser-gate`,
  `purser-admit` ve yeniden çalıştırılabilir, `--uninstall`'lu `install.sh`. Kurulum sembolik bağlı
  programların ve birimlerin içinden yazmaz, onları değiştirir.
- **İmaj**: `image/build-image.sh` SD kart imajını sabitlenmiş Armbian sürümünden, bütün paketler
  önceden kurulu olarak üretir; `image/flash.sh` (Linux, macOS) ve `image/purser-card-migrate`.
- **Değişmeyen biçimler**: disk düzeni (`nesil/gen-*`, `nesil/uzun-*`, `denetim/…`, `hazirlik`),
  SD durum dosyaları, liste biçimi `# purser-list 1`, kapı protokolü (`latest`, `rsync`,
  `ack <kimlik> tamam|uyari|supheli`).
