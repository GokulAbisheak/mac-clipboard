#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAKE_DMG=false
for arg in "$@"; do
    case "$arg" in
        --dmg) MAKE_DMG=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [--dmg]"
            echo "  Builds release, assembles dist/Clipboard.app."
            echo "  --dmg  read-write DMG + Finder layout (background, compact window, drag hint)."
            exit 0
            ;;
    esac
done

echo "→ swift build -c release"
swift build -c release

RELEASE_DIR="$(swift build -c release --show-bin-path)"
BIN="$RELEASE_DIR/Clipboard"
BUNDLE="$RELEASE_DIR/Clipboard_Clipboard.bundle"
ICNS="$ROOT/Sources/Clipboard/Resources/clipboard.icns"
PLIST="$ROOT/Support/Info.plist"

for f in "$BIN" "$BUNDLE" "$ICNS" "$PLIST"; do
    if [[ ! -e "$f" ]]; then
        echo "error: missing $f" >&2
        exit 1
    fi
done

APP="$ROOT/dist/Clipboard.app"
echo "→ Assemble $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Clipboard"
chmod +x "$APP/Contents/MacOS/Clipboard"
cp "$PLIST" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/clipboard.icns"
cp -R "$BUNDLE" "$APP/Clipboard_Clipboard.bundle"

echo "→ Done: $APP"

if $MAKE_DMG; then
    DMG="$ROOT/dist/Clipboard.dmg"
    DMG_RW="$ROOT/dist/.rw.Clipboard.dmg"
    rm -f "$DMG" "$DMG_RW"

    STAGING="$(mktemp -d "${TMPDIR:-/tmp}/clipboard-dmg-staging.XXXXXX")"
    cleanup_staging() { rm -rf "$STAGING"; }
    trap cleanup_staging EXIT

    mkdir -p "$STAGING/.background"
    RENDER_BIN="$(mktemp "${TMPDIR:-/tmp}/render-dmg-bg.XXXXXX")"
    swiftc -O "$ROOT/scripts/render-dmg-background.swift" -o "$RENDER_BIN"
    "$RENDER_BIN" 480 360 "$STAGING/.background/background.png"
    rm -f "$RENDER_BIN"

    cp -R "$APP" "$STAGING/"

    echo "→ Create read-write disk image"
    hdiutil create -quiet -srcfolder "$STAGING" -volname "Clipboard" \
        -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$DMG_RW"

    MOUNT_DIR=""
    DEV_SLICE=""
    cleanup_mount() {
        if [[ -n "$DEV_SLICE" ]]; then
            hdiutil detach "$DEV_SLICE" -quiet || true
            return
        fi
        if [[ -n "$MOUNT_DIR" ]] && mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
            hdiutil detach "$MOUNT_DIR" -quiet || true
        fi
    }

    echo "→ Mount & configure Finder layout"
    ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$DMG_RW")"
    MOUNT_DIR="$(echo "$ATTACH_OUT" | grep '/Volumes/' | sed -n 's|^.*\(/Volumes/.*\)$|\1|p' | tail -1)"
    DEV_SLICE="$(echo "$ATTACH_OUT" | grep Apple_HFS | head -1 | awk '{print $1}')"
    if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
        echo "error: could not parse mount point from hdiutil attach" >&2
        echo "$ATTACH_OUT" >&2
        exit 1
    fi
    if [[ -z "$DEV_SLICE" ]]; then
        echo "error: could not parse HFS device from hdiutil attach" >&2
        echo "$ATTACH_OUT" >&2
        exit 1
    fi
    trap 'cleanup_mount; rm -rf "$STAGING"; rm -f "$DMG_RW"' EXIT

    ln -sf /Applications "$MOUNT_DIR/Applications"

    VOLNAME="$(basename "$MOUNT_DIR")"
    echo "→ Finder cosmetics (volume: $VOLNAME)"
    sleep 5
    osascript "$ROOT/scripts/dmg-finder.applescript" "$VOLNAME" "$MOUNT_DIR" || {
        echo "warning: AppleScript failed; DMG will still work but layout may be default." >&2
    }

    sync
    cleanup_mount
    MOUNT_DIR=""
    DEV_SLICE=""
    trap 'rm -rf "$STAGING"; rm -f "$DMG_RW"' EXIT

    echo "→ Compress $DMG"
    hdiutil convert -quiet -ov "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
    rm -f "$DMG_RW"

    trap - EXIT
    cleanup_staging
    echo "→ Done: $DMG"
fi
