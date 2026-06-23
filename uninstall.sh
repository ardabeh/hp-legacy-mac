#!/bin/sh
# hp-legacy-mac uninstaller
set -eu
[ "$(id -u)" = "0" ] || { echo "Please run with sudo: sudo sh $0"; exit 1; }
BASE=/Library/Printers/hp-legacy-mac
FILTER=/usr/libexec/cups/filter/hp-legacy-mac

# Remove queues created by this tool (those with a queues/*.conf)
if [ -d "$BASE/queues" ]; then
    for c in "$BASE"/queues/*.conf; do
        [ -e "$c" ] || continue
        q="$(basename "$c" .conf)"
        echo ">>> Removing queue: $q"
        lpadmin -x "$q" 2>/dev/null || true
    done
fi
rm -f "$FILTER"
rm -rf "$BASE"
launchctl stop org.cups.cupsd 2>/dev/null || true
sleep 1; launchctl start org.cups.cupsd 2>/dev/null || true
echo ">>> hp-legacy-mac removed."
