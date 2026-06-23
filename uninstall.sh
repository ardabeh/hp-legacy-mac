#!/bin/sh
# hp-legacy-mac kaldırıcı
set -eu
[ "$(id -u)" = "0" ] || { echo "Lütfen sudo ile çalıştırın: sudo sh $0"; exit 1; }
BASE=/Library/Printers/hp-legacy-mac
FILTER=/usr/libexec/cups/filter/hp-legacy-mac

# Bu araçla kurulmuş kuyrukları sil (queues/*.conf olanlar)
if [ -d "$BASE/queues" ]; then
    for c in "$BASE"/queues/*.conf; do
        [ -e "$c" ] || continue
        q="$(basename "$c" .conf)"
        echo ">>> Kuyruk siliniyor: $q"
        lpadmin -x "$q" 2>/dev/null || true
    done
fi
rm -f "$FILTER"
rm -rf "$BASE"
launchctl stop org.cups.cupsd 2>/dev/null || true
sleep 1; launchctl start org.cups.cupsd 2>/dev/null || true
echo ">>> hp-legacy-mac kaldırıldı."
