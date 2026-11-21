# Changelog / Değişiklikler

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
