#!/bin/bash
# 打包成 build/AppOffice.app；加 --install 会拷到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d web/node_modules ]; then npm --prefix web ci; fi
npm --prefix web run build
swift build -c release --product AppOffice

APP=build/AppOffice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/AppOffice" "$APP/Contents/MacOS/AppOffice"
cp -R web/dist "$APP/Contents/Resources/web"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.mi.AppOffice</string>
    <key>CFBundleName</key><string>AppOffice</string>
    <key>CFBundleDisplayName</key><string>AppOffice</string>
    <key>CFBundleExecutable</key><string>AppOffice</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "打包好了：$APP"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/AppOffice.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "已安装：$HOME/Applications/AppOffice.app"
fi
