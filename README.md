# hp-legacy-mac

**Modern macOS'ta (özellikle macOS 26 "Tahoe" / Apple Silicon) çalışmayan eski HP "host-based" yazıcıları yeniden çalıştırır.**

HP'nin bu modeller için sunduğu sürücüler, macOS'tan kaldırılan eski ColorSync (`CM*`) API'lerini kullandığı için macOS 26'da çöker (`MacColorManager` assertion → filter failed). Bu araç, açık kaynak [foo2zjs](https://github.com/OpenPrinting/foo2zjs) sürücüsünü, kendi kendine yeten bir ghostscript paketiyle birlikte, macOS CUPS **sandbox'ıyla uyumlu** biçimde kurar.

```sh
curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/install.sh -o /tmp/hp-legacy-mac.sh
sudo sh /tmp/hp-legacy-mac.sh
```

Yazıcını açıp USB ile bağla, sonra yukarıdaki komutu çalıştır. Araç modeli otomatik algılar, doğru sürücüyü seçer ve yazdırma kuyruğunu kurar.

---

## Neden gerekiyor?

| Katman | Sorun | Çözümümüz |
|---|---|---|
| HP sürücüsü | macOS 26'da `CMGetDefaultProfileBySpace` → abort | foo2zjs sürücüsü |
| ghostscript | macOS'ta yok; Homebrew'unki `/opt/homebrew`'da | gs + 21 dylib `dylibbundler` ile paketlenip taşınır |
| CUPS sandbox | `/usr/local` ve `/opt/homebrew` exec'i yasak; `Sandboxing Off` Apple tarafından yok sayılır | Her şey `/Library/Printers/hp-legacy-mac` altında (sandbox izinli) |
| Renk | gs 10.x PostScript CRD'leri kaldırdı → renkli çöküyor | ICC tabanlı `gs9` renk yolu (`-c -C gs9`) |
| foomatic-rip | macOS'ta yok | Yerine geçen küçük bir CUPS filtresi |

## Desteklenen modeller

> **Durum etiketleri:** ✅ doğrulandı · 🟢 firmware gerektirmez (çalışması beklenir) · 🟡 her açılışta firmware yükleme gerektirir (deneysel, aşağıya bakın)

### Renkli (firmware gerektirmez)
- ✅ **HP LaserJet CP1025 / CP1025nw** — doğrulandı (renkli + mono)
- 🟢 HP Color LaserJet CP1215
- 🟢 HP Color LaserJet 1500 / 1600 / 2600n

### Mono — firmware gerektirir 🟡
LaserJet 1000, 1005, 1018, 1020, P1005, P1006, P1007, P1008, P1505/n,
M1005, M1120, M1319, M12a, M12w, M1132s, M1212nf, P1102/w, P1566, P1606dn

### Mono — standart (firmware gerektirmez) 🟢
LaserJet 1022 / 1022n / 1022nw, P2014 / P2014n, P2035 / P2035n

> 🟡 **Firmware notu:** Bazı mono LaserJet'ler her açılışta HP'ye ait bir firmware bloğunun yüklenmesini ister. Bu sürümde firmware otomatik indirme henüz yoktur (yol haritasında). Bu modeller şimdilik **deneysel**dir.

Tam liste: `ls /Library/Printers/hp-legacy-mac/ppd`

## Kullanım

Kurulumdan sonra herhangi bir uygulamadan **⌘P → kuyruk adı**.

- **Renk:** Renkli modellerde varsayılan renklidir. Mono istersen Yazdır penceresinde **ColorMode → Monochrome** veya sistemin Siyah-Beyaz seçeneğini işaretle.
- **Test:** `echo "test" | lp -d <kuyruk-adı>`
- **Belirli model zorlama:** `sudo HP_LEGACY_MODEL="HP LaserJet CP 1025" sh install.sh`

## Kaldırma

```sh
curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/uninstall.sh -o /tmp/uninstall.sh
sudo sh /tmp/uninstall.sh
```

## Kaynaktan derleme

```sh
brew install ghostscript jbigkit gnu-sed dylibbundler
sh build/build-bundle.sh        # dist/hp-legacy-mac-bundle-arm64.tar.gz üretir
sudo sh install.sh              # yereldeki dist/bundle'ı kullanır
```

## Nasıl çalışır?

1. `install.sh` paketi (foo2zjs sürücüleri + bağımsız ghostscript + PPD'ler) `/Library/Printers/hp-legacy-mac` altına koyar.
2. `ioreg` ile bağlı USB yazıcının modelini algılar, foo2zjs PPD veritabanıyla eşler.
3. PPD'deki `FoomaticRIPCommandLine`'dan sürücü komutunu çıkarır, kuyruk başına `queues/<ad>.conf` yazar.
4. `foomatic-rip` yerine geçen tek bir CUPS filtresi (`/usr/libexec/cups/filter/hp-legacy-mac`) `$PRINTER` env'inden config'i okuyup doğru sürücüyü, renk algısıyla çalıştırır.

## Sınırlamalar / yol haritası

- [ ] Intel (x86_64) paketi
- [ ] Firmware gerektiren modeller için otomatik firmware indirme/yükleme
- [ ] CP1025 dışındaki modellerin saha testi
- [ ] İmzalı/notarized `.pkg` (Developer ID gerektirir)

## Lisans

GPLv2 — foo2zjs türevi. Bkz. [LICENSE](LICENSE).
foo2zjs © Rick Richardson ve katkıda bulunanlar. ghostscript © Artifex.

## Sorumluluk reddi

Bu, HP ile bağlantısı olmayan, topluluk yapımı bir araçtır. "Olduğu gibi" sunulur.
