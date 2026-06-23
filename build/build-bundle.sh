#!/bin/sh
# hp-legacy-mac — yeniden dağıtılabilir, kendi kendine yeten paketi sıfırdan üretir.
# Çıktı: dist/bundle/  ve  dist/hp-legacy-mac-bundle-<arch>.tar.gz
#
# Gereksinimler: Homebrew, Xcode Command Line Tools.
#   brew install ghostscript jbigkit gnu-sed dylibbundler
#
# Kullanım:  sh build/build-bundle.sh
set -eu

ARCH="$(uname -m)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
B="$ROOT/dist/bundle"
BREW="$(brew --prefix)"
FOO2ZJS_REPO="https://github.com/OpenPrinting/foo2zjs.git"

echo ">>> Bağımlılıklar denetleniyor..."
for f in ghostscript jbigkit gnu-sed dylibbundler; do
    brew list "$f" >/dev/null 2>&1 || brew install "$f"
done
GS="$BREW/bin/gs"; GSED="$BREW/bin/gsed"

echo ">>> foo2zjs kaynağı alınıyor..."
git clone --depth 1 "$FOO2ZJS_REPO" "$WORK/foo2zjs"
cd "$WORK/foo2zjs"

echo ">>> Sürücüler derleniyor..."
CF="-O2 -Wall -I$BREW/include"; LF="-L$BREW/lib"
make foo2zjs foo2hp foo2xqx foo2lava foo2qpdl foo2oak foo2slx foo2hiperc foo2hbpl2 foo2ddst arm2hpdl \
     CFLAGS="$CF" LDFLAGS="$LF"
for w in foo2zjs-wrapper foo2hp2600-wrapper foo2oak-wrapper foo2lava-wrapper foo2qpdl-wrapper \
         foo2slx-wrapper foo2hiperc-wrapper foo2hbpl2-wrapper foo2ddst-wrapper foo2xqx-wrapper foo2zjs-pstops; do
    make "$w"
done

echo ">>> Paket toplanıyor..."
rm -rf "$B"; mkdir -p "$B/bin" "$B/libs" "$B/share" "$B/ppd"
cp foo2zjs foo2hp foo2xqx foo2lava foo2qpdl foo2oak foo2slx foo2hiperc foo2hbpl2 foo2ddst arm2hpdl "$B/bin/"
cp foo2zjs-wrapper foo2hp2600-wrapper foo2oak-wrapper foo2lava-wrapper foo2qpdl-wrapper \
   foo2slx-wrapper foo2hiperc-wrapper foo2hbpl2-wrapper foo2ddst-wrapper foo2xqx-wrapper foo2zjs-pstops "$B/bin/"
cp "$GS" "$B/bin/gs"; cp "$GSED" "$B/bin/gsed"
for p in PPD/HP-*.ppd; do gzip -c "$p" > "$B/ppd/$(basename "$p").gz"; done
cp -RL "$BREW/share/ghostscript" "$B/share/ghostscript"

echo ">>> ghostscript bağımlılıkları paketleniyor (dylibbundler)..."
( cd "$B" && dylibbundler -of -b -x ./bin/gs -d ./libs/ -p @executable_path/../libs/ >/dev/null )

cp "$ROOT/src/cups-filter" "$B/cups-filter"
cp "$ROOT/VERSION" "$B/VERSION" 2>/dev/null || echo "v1.0.0" > "$B/VERSION"
chmod 755 "$B"/bin/*

echo ">>> Tarball üretiliyor..."
TAR="$ROOT/dist/hp-legacy-mac-bundle-$ARCH.tar.gz"
( cd "$ROOT/dist" && tar -czf "$TAR" bundle )
rm -rf "$WORK"
echo ">>> TAMAM: $TAR ($(du -sh "$TAR" | cut -f1))"
echo "    Doğrula: otool -L $B/bin/gs | grep -i homebrew  (boş olmalı)"
