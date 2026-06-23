#!/bin/sh
# hp-legacy-mac — HP legacy (host-based) yazıcıları modern macOS'ta çalıştırır.
#
# Kullanım (önerilen):
#   curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/install.sh -o /tmp/hp-legacy-mac.sh
#   sudo sh /tmp/hp-legacy-mac.sh
#
# Ne yapar: kendi kendine yeten foo2zjs + ghostscript paketini /Library/Printers/hp-legacy-mac
# altına kurar, bağlı USB yazıcının modelini algılar, uygun PPD'yi seçer, macOS CUPS
# sandbox'ıyla uyumlu bir filtre kurar ve yazdırma kuyruğunu yapılandırır.
#
# Lisans: GPLv2 (foo2zjs türevi). Bkz. LICENSE.
set -eu

# --- Yapılandırma (yayınlarken doldurulur) ---
REPO_SLUG="${HP_LEGACY_REPO:-ardabeh/hp-legacy-mac}"
VERSION="${HP_LEGACY_VERSION:-v1.0.0}"
BASE=/Library/Printers/hp-legacy-mac
FILTER=/usr/libexec/cups/filter/hp-legacy-mac
# Yerel geliştirme: bu betiğin yanında dist/bundle varsa indirme yapma
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"
LOCAL_BUNDLE="$SCRIPT_DIR/dist/bundle"

msg()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mHATA:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Önkoşullar ---
[ "$(id -u)" = "0" ] || die "Lütfen sudo ile çalıştırın:  sudo sh $0"
[ "$(uname -s)" = "Darwin" ] || die "Bu araç yalnızca macOS içindir."
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || die "Bu sürüm Apple Silicon (arm64) içindir. Intel desteği yakında. (uname -m = $ARCH)"

# --- 1) Paketi yerleştir ---
install_bundle() {
    rm -rf "$BASE"
    mkdir -p "$BASE"
    if [ -d "$LOCAL_BUNDLE" ]; then
        msg "Yerel paket kullanılıyor: $LOCAL_BUNDLE"
        cp -R "$LOCAL_BUNDLE"/* "$BASE/"
    else
        URL="https://github.com/$REPO_SLUG/releases/download/$VERSION/hp-legacy-mac-bundle-$ARCH.tar.gz"
        msg "Paket indiriliyor: $URL"
        TMP="$(mktemp -d)"
        curl -fsSL "$URL" -o "$TMP/bundle.tar.gz" || die "Paket indirilemedi: $URL"
        tar -xzf "$TMP/bundle.tar.gz" -C "$TMP"
        cp -R "$TMP/bundle/"* "$BASE/" 2>/dev/null || cp -R "$TMP/"*/* "$BASE/"
        rm -rf "$TMP"
    fi
    chown -R root:wheel "$BASE"
    chmod -R 755 "$BASE/bin"
    [ -x "$BASE/bin/gs" ] || die "Paket bozuk: $BASE/bin/gs bulunamadı."
    msg "Paket kuruldu: $BASE"
}

# --- 2) Filtreyi kur ---
install_filter() {
    if [ -f "$LOCAL_BUNDLE/../../src/cups-filter" ]; then
        install -o root -g wheel -m 755 "$LOCAL_BUNDLE/../../src/cups-filter" "$FILTER"
    elif [ -f "$BASE/cups-filter" ]; then
        install -o root -g wheel -m 755 "$BASE/cups-filter" "$FILTER"
    else
        die "CUPS filtresi bulunamadı."
    fi
    msg "CUPS filtresi kuruldu: $FILTER"
}

# --- 3) Bağlı HP yazıcısını algıla ---
detect_printer() {
    DEV_NAME="${HP_LEGACY_MODEL:-}"
    if [ -z "$DEV_NAME" ]; then
        # Bağlı tüm USB ürün adlarını al, HP/LaserJet olanı seç
        DEV_NAME="$(ioreg -p IOUSB -l -w 0 2>/dev/null \
            | grep '"USB Product Name"' \
            | sed -E 's/.*= "([^"]*)".*/\1/' \
            | grep -iE 'laserjet|deskjet|officejet|hewlett|hp ' | head -1)"
    fi
    [ -n "$DEV_NAME" ] || die "Bağlı HP USB yazıcısı bulunamadı. Yazıcıyı açıp bağlayın veya HP_LEGACY_MODEL ile model adı verin."
    msg "Algılanan yazıcı: $DEV_NAME"
}

# normalize: küçük harf, gürültü kelimelerini ve alfanümerik dışını at.
# NOT: macOS BSD sed \b (kelime sınırı) desteklemez; düz alt-dize temizliği kullanılır.
norm() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -E 's/hewlett[ -]?packard//g; s/professional//g; s/laserjet//g; s/deskjet//g; s/officejet//g; s/colou?r//g; s/series//g; s/mfp//g; s/pro//g; s/hp//g' \
        | tr -cd 'a-z0-9'
}

# --- 4) Modeli PPD'ye eşle ---
match_ppd() {
    DEV_NORM="$(norm "$DEV_NAME")"
    BEST=""; BEST_SCORE=0
    for gz in "$BASE"/ppd/*.ppd.gz; do
        [ -e "$gz" ] || continue
        MODEL="$(gunzip -c "$gz" | sed -nE 's/^\*ModelName:[[:space:]]*"([^"]*)".*/\1/p' | head -1)"
        [ -n "$MODEL" ] || MODEL="$(basename "$gz" .ppd.gz | tr '_-' '  ')"
        MN="$(norm "$MODEL")"
        [ -n "$MN" ] || continue
        # alt-dize eşleşmesi: biri diğerini içeriyorsa, daha uzun ortak ada göre puanla
        SCORE=0
        case "$MN" in *"$DEV_NORM"*) SCORE=${#DEV_NORM};; esac
        case "$DEV_NORM" in *"$MN"*) [ ${#MN} -gt "$SCORE" ] && SCORE=${#MN};; esac
        if [ "$SCORE" -gt "$BEST_SCORE" ]; then BEST_SCORE="$SCORE"; BEST="$gz"; fi
    done
    [ -n "$BEST" ] || die "'$DEV_NAME' için uygun PPD bulunamadı. Desteklenen modeller: ls $BASE/ppd"
    PPD_GZ="$BEST"
    PPD_MODEL="$(gunzip -c "$PPD_GZ" | sed -nE 's/^\*ModelName:[[:space:]]*"([^"]*)".*/\1/p' | head -1)"
    msg "Eşleşen sürücü/PPD: $PPD_MODEL  ($(basename "$PPD_GZ"))"
}

# --- 5) Kuyruğu yapılandır ---
configure_queue() {
    WORK="$(mktemp -d)"
    PPD="$WORK/printer.ppd"
    gunzip -c "$PPD_GZ" > "$PPD"

    # Sürücü komutunu (wrapper + seçenekler) PPD'den çıkar, %X belirteçlerini at
    DRIVER="$(sed -nE 's/^\*FoomaticRIPCommandLine:[[:space:]]*"(.*)".*/\1/p' "$PPD" | head -1 \
        | sed -E 's/%[A-Za-z]//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
    [ -n "$DRIVER" ] || DRIVER="foo2zjs-wrapper"

    # Renk yeteneği
    COLOR_CAPABLE=0
    grep -qiE '^\*ColorDevice:[[:space:]]*True' "$PPD" && COLOR_CAPABLE=1
    case "$DRIVER" in
        foo2zjs-wrapper*)   COLOR_FLAGS="-c -C gs9" ;;
        *)                  COLOR_FLAGS="-c" ;;
    esac

    # PPD'nin cupsFilter satırlarını bizim filtremize çevir
    grep -v '^\*cupsFilter' "$PPD" > "$PPD.tmp" && mv "$PPD.tmp" "$PPD"
    printf '*cupsFilter: "application/vnd.cups-pdf 0 hp-legacy-mac"\n' >> "$PPD"
    # Renkli modelde varsayılanı renkliye al
    if [ "$COLOR_CAPABLE" = "1" ]; then
        sed -i '' 's/^\*DefaultColorMode:.*/*DefaultColorMode: ICM/' "$PPD" 2>/dev/null || true
    fi

    # Kuyruk adı ve aygıt URI'si
    QUEUE="${HP_LEGACY_QUEUE:-}"
    DEVICE_URI="$(lpstat -v 2>/dev/null | sed -nE 's/.*: (usb:.*)/\1/p' | head -1)"
    if [ -z "$QUEUE" ]; then
        # Mevcut bir USB kuyruğu varsa onu kullan, yoksa modelden ad türet
        QUEUE="$(lpstat -v 2>/dev/null | grep -i 'usb:' | sed -nE 's/.* ([^ ]+) için.*/\1/p' | head -1)"
        [ -n "$QUEUE" ] || QUEUE="$(lpstat -v 2>/dev/null | grep -i 'usb:' | awk '{print $3}' | sed 's/:$//' | head -1)"
        [ -n "$QUEUE" ] || QUEUE="$(printf '%s' "$PPD_MODEL" | tr ' /' '__' | tr -cd 'A-Za-z0-9_')"
    fi
    if [ -z "$DEVICE_URI" ]; then
        # CUPS'tan USB aygıtını keşfet
        DEVICE_URI="$(/usr/libexec/cups/backend/usb 2>/dev/null | grep -i 'hewlett\|hp' | sed -nE 's/^direct (usb:[^ ]+).*/\1/p' | head -1)"
    fi
    [ -n "$DEVICE_URI" ] || die "USB aygıt URI'si bulunamadı. Yazıcı bağlı ve açık mı?"

    # Per-queue config
    mkdir -p "$BASE/queues"
    cat > "$BASE/queues/$QUEUE.conf" <<EOF
DRIVER="$DRIVER"
COLOR_CAPABLE=$COLOR_CAPABLE
COLOR_FLAGS="$COLOR_FLAGS"
EOF

    msg "Kuyruk yapılandırılıyor: $QUEUE  ($DEVICE_URI)"
    msg "  Sürücü: $DRIVER  | Renk: $COLOR_CAPABLE"
    lpadmin -p "$QUEUE" -v "$DEVICE_URI" -P "$PPD" -E -o printer-error-policy=retry-job
    cupsenable "$QUEUE" 2>/dev/null || true
    cupsaccept "$QUEUE" 2>/dev/null || true
    rm -rf "$WORK"

    # USB backend'i root olarak çalıştırması için izinleri sıkılaştır (klasik CUPS düzeltmesi)
    chmod 0700 /usr/libexec/cups/backend/usb 2>/dev/null || true

    launchctl stop org.cups.cupsd 2>/dev/null || true
    sleep 1; launchctl start org.cups.cupsd 2>/dev/null || true

    INSTALLED_QUEUE="$QUEUE"
}

# --- Çalıştır ---
msg "hp-legacy-mac $VERSION kuruluyor ($ARCH)"
install_bundle
install_filter
detect_printer
match_ppd
configure_queue

cat <<EOF

\033[1;32m✓ Kurulum tamamlandı!\033[0m

Kuyruk: $INSTALLED_QUEUE
Test:   echo "hp-legacy-mac test" | lp -d "$INSTALLED_QUEUE"
Veya herhangi bir uygulamadan  ⌘P → $INSTALLED_QUEUE

Renkli modellerde varsayılan renklidir; mono için Yazdır penceresinde
"ColorMode → Monochrome" (veya sistemin Siyah-Beyaz seçeneği) işaretleyin.

Kaldırmak için:  sudo sh uninstall.sh
EOF
