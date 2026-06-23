#!/bin/sh
# hp-legacy-mac — revive legacy HP (host-based) printers on modern macOS.
#
# Usage (recommended):
#   curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/install.sh -o /tmp/hp-legacy-mac.sh
#   sudo sh /tmp/hp-legacy-mac.sh
#
# What it does: installs a self-contained foo2zjs + ghostscript bundle under
# /Library/Printers/hp-legacy-mac, detects the connected USB printer model,
# picks the matching PPD, installs a macOS-CUPS-sandbox-compatible filter, and
# configures the print queue.
#
# License: GPLv2 (derived from foo2zjs). See LICENSE.
set -eu

# --- Configuration ---
REPO_SLUG="${HP_LEGACY_REPO:-ardabeh/hp-legacy-mac}"
VERSION="${HP_LEGACY_VERSION:-v1.0.0}"
BASE=/Library/Printers/hp-legacy-mac
FILTER=/usr/libexec/cups/filter/hp-legacy-mac
# Local dev: if a dist/bundle sits next to this script, skip the download
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"
LOCAL_BUNDLE="$SCRIPT_DIR/dist/bundle"

msg()  { printf '\033[1;34m>>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- Prerequisites ---
[ "$(id -u)" = "0" ] || die "Please run with sudo:  sudo sh $0"
[ "$(uname -s)" = "Darwin" ] || die "This tool is for macOS only."
ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || die "This release is for Apple Silicon (arm64). Intel support is coming. (uname -m = $ARCH)"

# --- 1) Place the bundle ---
install_bundle() {
    rm -rf "$BASE"
    mkdir -p "$BASE"
    if [ -d "$LOCAL_BUNDLE" ]; then
        msg "Using local bundle: $LOCAL_BUNDLE"
        cp -R "$LOCAL_BUNDLE"/* "$BASE/"
    else
        URL="https://github.com/$REPO_SLUG/releases/download/$VERSION/hp-legacy-mac-bundle-$ARCH.tar.gz"
        msg "Downloading bundle: $URL"
        TMP="$(mktemp -d)"
        curl -fsSL "$URL" -o "$TMP/bundle.tar.gz" || die "Failed to download bundle: $URL"
        tar -xzf "$TMP/bundle.tar.gz" -C "$TMP"
        cp -R "$TMP/bundle/"* "$BASE/" 2>/dev/null || cp -R "$TMP/"*/* "$BASE/"
        rm -rf "$TMP"
    fi
    chown -R root:wheel "$BASE"
    chmod -R 755 "$BASE/bin"
    [ -x "$BASE/bin/gs" ] || die "Bundle is broken: $BASE/bin/gs not found."
    msg "Bundle installed: $BASE"
}

# --- 2) Install the CUPS filter ---
install_filter() {
    if [ -f "$LOCAL_BUNDLE/../../src/cups-filter" ]; then
        install -o root -g wheel -m 755 "$LOCAL_BUNDLE/../../src/cups-filter" "$FILTER"
    elif [ -f "$BASE/cups-filter" ]; then
        install -o root -g wheel -m 755 "$BASE/cups-filter" "$FILTER"
    else
        die "CUPS filter not found."
    fi
    msg "CUPS filter installed: $FILTER"
}

# --- 3) Detect the connected HP printer ---
detect_printer() {
    DEV_NAME="${HP_LEGACY_MODEL:-}"
    if [ -z "$DEV_NAME" ]; then
        # List all connected USB product names, pick the HP/LaserJet one
        DEV_NAME="$(ioreg -p IOUSB -l -w 0 2>/dev/null \
            | grep '"USB Product Name"' \
            | sed -E 's/.*= "([^"]*)".*/\1/' \
            | grep -iE 'laserjet|deskjet|officejet|hewlett|hp ' | head -1)"
    fi
    [ -n "$DEV_NAME" ] || die "No connected HP USB printer found. Turn it on and connect it, or set HP_LEGACY_MODEL to the model name."
    msg "Detected printer: $DEV_NAME"
}

# normalize: lowercase, strip noise words and non-alphanumerics.
# NOTE: macOS BSD sed has no \b (word boundary); plain substring removal is used.
norm() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' \
        | sed -E 's/hewlett[ -]?packard//g; s/professional//g; s/laserjet//g; s/deskjet//g; s/officejet//g; s/colou?r//g; s/series//g; s/mfp//g; s/pro//g; s/hp//g' \
        | tr -cd 'a-z0-9'
}

# --- 4) Match the model to a PPD ---
match_ppd() {
    DEV_NORM="$(norm "$DEV_NAME")"
    BEST=""; BEST_SCORE=0
    for gz in "$BASE"/ppd/*.ppd.gz; do
        [ -e "$gz" ] || continue
        MODEL="$(gunzip -c "$gz" | sed -nE 's/^\*ModelName:[[:space:]]*"([^"]*)".*/\1/p' | head -1)"
        [ -n "$MODEL" ] || MODEL="$(basename "$gz" .ppd.gz | tr '_-' '  ')"
        MN="$(norm "$MODEL")"
        [ -n "$MN" ] || continue
        # substring match: if one contains the other, score by the longer shared name
        SCORE=0
        case "$MN" in *"$DEV_NORM"*) SCORE=${#DEV_NORM};; esac
        case "$DEV_NORM" in *"$MN"*) [ ${#MN} -gt "$SCORE" ] && SCORE=${#MN};; esac
        if [ "$SCORE" -gt "$BEST_SCORE" ]; then BEST_SCORE="$SCORE"; BEST="$gz"; fi
    done
    [ -n "$BEST" ] || die "No matching PPD for '$DEV_NAME'. Supported models: ls $BASE/ppd"
    PPD_GZ="$BEST"
    PPD_MODEL="$(gunzip -c "$PPD_GZ" | sed -nE 's/^\*ModelName:[[:space:]]*"([^"]*)".*/\1/p' | head -1)"
    msg "Matched driver/PPD: $PPD_MODEL  ($(basename "$PPD_GZ"))"
}

# --- 5) Configure the queue ---
configure_queue() {
    WORK="$(mktemp -d)"
    PPD="$WORK/printer.ppd"
    gunzip -c "$PPD_GZ" > "$PPD"

    # Extract the driver command (wrapper + options) from the PPD; drop %X tokens
    DRIVER="$(sed -nE 's/^\*FoomaticRIPCommandLine:[[:space:]]*"(.*)".*/\1/p' "$PPD" | head -1 \
        | sed -E 's/%[A-Za-z]//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
    [ -n "$DRIVER" ] || DRIVER="foo2zjs-wrapper"

    # Color capability
    COLOR_CAPABLE=0
    grep -qiE '^\*ColorDevice:[[:space:]]*True' "$PPD" && COLOR_CAPABLE=1
    case "$DRIVER" in
        foo2zjs-wrapper*)   COLOR_FLAGS="-c -C gs9" ;;
        *)                  COLOR_FLAGS="-c" ;;
    esac

    # Redirect the PPD's cupsFilter lines to our filter
    grep -v '^\*cupsFilter' "$PPD" > "$PPD.tmp" && mv "$PPD.tmp" "$PPD"
    printf '*cupsFilter: "application/vnd.cups-pdf 0 hp-legacy-mac"\n' >> "$PPD"
    # Default to color on color-capable models
    if [ "$COLOR_CAPABLE" = "1" ]; then
        sed -i '' 's/^\*DefaultColorMode:.*/*DefaultColorMode: ICM/' "$PPD" 2>/dev/null || true
    fi

    # Queue name and device URI
    QUEUE="${HP_LEGACY_QUEUE:-}"
    DEVICE_URI="$(lpstat -v 2>/dev/null | sed -nE 's/.*: (usb:.*)/\1/p' | head -1)"
    if [ -z "$QUEUE" ]; then
        # Reuse an existing USB queue if present, otherwise derive a name from the model
        QUEUE="$(lpstat -v 2>/dev/null | grep -i 'usb:' | awk '{print $3}' | sed 's/:$//' | head -1)"
        [ -n "$QUEUE" ] || QUEUE="$(printf '%s' "$PPD_MODEL" | tr ' /' '__' | tr -cd 'A-Za-z0-9_')"
    fi
    if [ -z "$DEVICE_URI" ]; then
        # Discover the USB device from CUPS
        DEVICE_URI="$(/usr/libexec/cups/backend/usb 2>/dev/null | grep -i 'hewlett\|hp' | sed -nE 's/^direct (usb:[^ ]+).*/\1/p' | head -1)"
    fi
    [ -n "$DEVICE_URI" ] || die "Could not find a USB device URI. Is the printer connected and powered on?"

    # Per-queue config
    mkdir -p "$BASE/queues"
    cat > "$BASE/queues/$QUEUE.conf" <<EOF
DRIVER="$DRIVER"
COLOR_CAPABLE=$COLOR_CAPABLE
COLOR_FLAGS="$COLOR_FLAGS"
EOF

    msg "Configuring queue: $QUEUE  ($DEVICE_URI)"
    msg "  Driver: $DRIVER  | Color: $COLOR_CAPABLE"
    lpadmin -p "$QUEUE" -v "$DEVICE_URI" -P "$PPD" -E -o printer-error-policy=retry-job
    cupsenable "$QUEUE" 2>/dev/null || true
    cupsaccept "$QUEUE" 2>/dev/null || true
    rm -rf "$WORK"

    # Tighten USB backend perms so CUPS runs it as root (classic CUPS fix)
    chmod 0700 /usr/libexec/cups/backend/usb 2>/dev/null || true

    launchctl stop org.cups.cupsd 2>/dev/null || true
    sleep 1; launchctl start org.cups.cupsd 2>/dev/null || true

    INSTALLED_QUEUE="$QUEUE"
}

# --- Run ---
msg "Installing hp-legacy-mac $VERSION ($ARCH)"
install_bundle
install_filter
detect_printer
match_ppd
configure_queue

cat <<EOF

\033[1;32m✓ Installation complete!\033[0m

Queue: $INSTALLED_QUEUE
Test:  echo "hp-legacy-mac test" | lp -d "$INSTALLED_QUEUE"
Or print from any app:  ⌘P → $INSTALLED_QUEUE

Color models default to color; for mono, choose
"ColorMode → Monochrome" (or the system Black & White option) in the Print dialog.

To uninstall:  sudo sh uninstall.sh
EOF
