#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
APP="$ROOT/Lyriczzz.app"
REAL_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk"
SDK="/tmp/lyriczzz-sdk2/MacOSX.sdk"
OVERLAY="$ROOT/Branding/sdk-overlay.yaml"

if [[ ! -d "$SDK/System" ]]; then
  echo "Preparing a Swift SDK this compiler can read…"
  rm -rf /tmp/lyriczzz-sdk2
  mkdir -p /tmp/lyriczzz-sdk2
  cp -cR "$REAL_SDK" "$SDK"
  python3 - <<'PY'
import os
root = "/tmp/lyriczzz-sdk2/MacOSX.sdk"
old = b"Apple Swift version 6.2 effective-5.10 (swiftlang-6.2.3.3.2 clang-1700.6.3.2)"
new = b"Apple Swift version 6.2.4 effective-5.10 (swiftlang-6.2.4.1.4 clang-1700.6.4.2)"
count = 0
for dirpath, _, files in os.walk(root):
    for name in files:
        if not name.endswith(".swiftinterface"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, "rb") as handle:
            data = handle.read()
        if old not in data:
            continue
        with open(path, "wb") as handle:
            handle.write(data.replace(old, new))
        count += 1
print(f"patched {count} interfaces")
PY
fi

mkdir -p "$ROOT/Branding"
cat > /tmp/lyriczzz-empty.modulemap <<'EOF'
// Hides a duplicated SwiftBridging module map in Command Line Tools.
EOF
cat > "$OVERLAY" <<'EOF'
{
  "version": 0,
  "roots": [
    {
      "name": "/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap",
      "type": "file",
      "external-contents": "/tmp/lyriczzz-empty.modulemap"
    }
  ]
}
EOF

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling lyriczzz…"
swiftc \
  -parse-as-library \
  -O \
  -swift-version 5 \
  -sdk "$SDK" \
  -target arm64e-apple-macosx26.2 \
  -vfsoverlay "$OVERLAY" \
  -framework AppKit \
  -framework SwiftUI \
  -o "$APP/Contents/MacOS/Lyriczzz" \
  "$ROOT"/Sources/*.swift

clang -O2 -arch arm64e -o "$APP/Contents/MacOS/playback-helper" "$ROOT/Sources/playback-helper.c"
chmod +x "$APP/Contents/MacOS/playback-helper"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/now-playing.js" "$APP/Contents/Resources/now-playing.js"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ICON_SRC="$ROOT/Branding/lyriczzz-icon.jpg"
WORD_SRC="$ROOT/Branding/lyriczzz-wordmark.jpg"
SET="$ROOT/Branding/AppIcon.iconset"
rm -rf "$SET"
mkdir -p "$SET"
for spec in "16:icon_16x16" "32:icon_16x16@2x" "32:icon_32x32" "64:icon_32x32@2x" "128:icon_128x128" "256:icon_128x128@2x" "256:icon_256x256" "512:icon_256x256@2x" "512:icon_512x512" "1024:icon_512x512@2x"; do
  size="${spec%%:*}"
  name="${spec##*:}"
  sips -s format png -z "$size" "$size" "$ICON_SRC" --out "$SET/${name}.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
sips -s format png "$ICON_SRC" --out "$APP/Contents/Resources/mark.png" >/dev/null
sips -s format png "$WORD_SRC" --out "$APP/Contents/Resources/wordmark.png" >/dev/null

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
