#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL=false

if [[ $# -eq 1 && "$1" == "--install" ]]; then
    INSTALL=true
elif [[ $# -ne 0 ]]; then
    printf 'usage: %s [--install]\n' "$0" >&2
    exit 64
fi

BUILD_ROOT="$ROOT/.build"
STAGING="$BUILD_ROOT/Quill.app.staging.$$"
APP="$BUILD_ROOT/Quill.app"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

swift build -c release --product quill
swift build -c release --product quill-icon
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BIN_DIR/quill" "$STAGING/Contents/MacOS/quill"
cp "$ROOT/Packaging/Info.plist" "$STAGING/Contents/Info.plist"
swift run -c release quill-icon \
    --output "$STAGING/Contents/Resources/AppIcon.icns"
chmod 755 "$STAGING/Contents/MacOS/quill"

for required in \
    "$STAGING/Contents/MacOS/quill" \
    "$STAGING/Contents/Info.plist" \
    "$STAGING/Contents/Resources/AppIcon.icns"; do
    if [[ ! -f "$required" ]]; then
        printf 'error: missing bundle file: %s\n' "$required" >&2
        exit 1
    fi
done

plutil -lint "$STAGING/Contents/Info.plist" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGING/Contents/Info.plist")" == "com.digimata.quill" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$STAGING/Contents/Info.plist")" == "true" ]]
ICON_KIND="$(file "$STAGING/Contents/Resources/AppIcon.icns")"
case "$ICON_KIND" in
    *"Mac OS X icon"*) ;;
    *)
        printf 'error: invalid app icon: %s\n' "$ICON_KIND" >&2
        exit 1
        ;;
esac

rm -rf "$APP"
mv "$STAGING" "$APP"
trap - EXIT

if [[ "$INSTALL" == true ]]; then
    INSTALL_APP="/Applications/Quill.app"
    INSTALL_STAGING="/Applications/Quill.app.staging.$$"
    rm -rf "$INSTALL_STAGING"
    ditto "$APP" "$INSTALL_STAGING"
    rm -rf "$INSTALL_APP"
    mv "$INSTALL_STAGING" "$INSTALL_APP"
    printf 'installed: %s\n' "$INSTALL_APP"
    printf 'executable: %s\n' "$INSTALL_APP/Contents/MacOS/quill"
else
    printf 'built: %s\n' "$APP"
    printf 'open:  open %s\n' "$APP"
fi
