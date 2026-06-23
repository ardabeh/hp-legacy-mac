# hp-legacy-mac

**Revives legacy HP "host-based" printers that no longer work on modern macOS (especially macOS 26 "Tahoe" / Apple Silicon).**

HP's drivers for these models call legacy ColorSync (`CM*`) APIs that were removed from macOS, so they crash on macOS 26 (`MacColorManager` assertion → *filter failed*). This tool installs the open-source [foo2zjs](https://github.com/OpenPrinting/foo2zjs) driver together with a self-contained ghostscript bundle, in a way that is **compatible with the macOS CUPS sandbox**.

```sh
curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/install.sh -o /tmp/hp-legacy-mac.sh
sudo sh /tmp/hp-legacy-mac.sh
```

Turn the printer on and connect it via USB, then run the command above. The tool auto-detects the model, picks the right driver, and configures the print queue. You enter your password **once** (the single `sudo`); everything else runs automatically.

---

## Why is this needed?

| Layer | Problem | Our fix |
|---|---|---|
| HP driver | On macOS 26, `CMGetDefaultProfileBySpace` → abort | foo2zjs driver |
| ghostscript | Not present on macOS; Homebrew's lives in `/opt/homebrew` | gs + 21 dylibs relocated with `dylibbundler` |
| CUPS sandbox | `/usr/local` and `/opt/homebrew` exec is blocked; `Sandboxing Off` is ignored by Apple's cupsd | Everything lives under `/Library/Printers/hp-legacy-mac` (sandbox-allowed) |
| Color | gs 10.x removed PostScript CRDs → color crashes | ICC-based `gs9` color path (`-c -C gs9`) |
| foomatic-rip | Not present on macOS | A small replacement CUPS filter |

## Supported models

> **Status:** ✅ verified · 🟢 no firmware required (expected to work) · 🟡 requires firmware upload on every power-on (experimental, see below)

### Color (no firmware required)
- ✅ **HP LaserJet CP1025 / CP1025nw** — verified (color + mono)
- 🟢 HP Color LaserJet CP1215
- 🟢 HP Color LaserJet 1500 / 1600 / 2600n

### Mono — requires firmware 🟡
LaserJet 1000, 1005, 1018, 1020, P1005, P1006, P1007, P1008, P1505/n,
M1005, M1120, M1319, M12a, M12w, M1132s, M1212nf, P1102/w, P1566, P1606dn

### Mono — standard (no firmware required) 🟢
LaserJet 1022 / 1022n / 1022nw, P2014 / P2014n, P2035 / P2035n

> 🟡 **Firmware note:** Some mono LaserJets require an HP-proprietary firmware block to be uploaded on every power-on. Automatic firmware download is **not yet** included in this release (on the roadmap). These models are currently **experimental**.

Full list: `ls /Library/Printers/hp-legacy-mac/ppd`

## Usage

After installation, print from any app via **⌘P → queue name**.

- **Color:** Color models default to color. For mono, choose **ColorMode → Monochrome** in the Print dialog, or the system Black & White option.
- **Test:** `echo "test" | lp -d <queue-name>`
- **Force a specific model:** `sudo HP_LEGACY_MODEL="HP LaserJet CP 1025" sh install.sh`

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/ardabeh/hp-legacy-mac/main/uninstall.sh -o /tmp/uninstall.sh
sudo sh /tmp/uninstall.sh
```

## Build from source

```sh
brew install ghostscript jbigkit gnu-sed dylibbundler
sh build/build-bundle.sh        # produces dist/hp-legacy-mac-bundle-arm64.tar.gz
sudo sh install.sh              # uses the local dist/bundle
```

## How it works

1. `install.sh` places the bundle (foo2zjs drivers + standalone ghostscript + PPDs) under `/Library/Printers/hp-legacy-mac`.
2. It detects the connected USB printer model via `ioreg` and matches it against the foo2zjs PPD database.
3. It extracts the driver command from the PPD's `FoomaticRIPCommandLine` and writes a per-queue `queues/<name>.conf`.
4. A single CUPS filter (`/usr/libexec/cups/filter/hp-legacy-mac`) replaces `foomatic-rip`: it reads the queue config from `$PRINTER` and runs the right driver, with color detection.

## Limitations / roadmap

- [ ] Intel (x86_64) bundle
- [ ] Automatic firmware download/upload for firmware-dependent models
- [ ] Field testing of models other than CP1025
- [ ] Signed / notarized `.pkg` (requires a Developer ID)

## License

GPLv2 — derived from foo2zjs. See [LICENSE](LICENSE).
foo2zjs © Rick Richardson and contributors. ghostscript © Artifex.

## Disclaimer

This is a community-built tool with no affiliation to HP. Provided "as is".
