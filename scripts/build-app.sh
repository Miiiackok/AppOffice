#!/bin/bash
# 打包成 build/AppOffice.app。可选：
#   --install    拷到 ~/Applications
#   --universal  同时编 Apple 芯片和 Intel 两种架构（发布用）
#   --zip        另外压一份 build/AppOffice.zip（发布用）
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=0 UNIVERSAL=0 ZIP=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) UNIVERSAL=1 ;;
        --zip) ZIP=1 ;;
        *) echo "不认识的参数：$arg" >&2; exit 1 ;;
    esac
done
ARCH=()
if [ "$UNIVERSAL" = 1 ]; then ARCH=(--arch arm64 --arch x86_64); fi

if [ ! -d web/node_modules ]; then npm --prefix web ci; fi
npm --prefix web run build
swift build -c release --product AppOffice ${ARCH[@]+"${ARCH[@]}"}

APP=build/AppOffice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release ${ARCH[@]+"${ARCH[@]}"} --show-bin-path)/AppOffice" "$APP/Contents/MacOS/AppOffice"
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

if [ "$ZIP" = 1 ]; then
    rm -f build/AppOffice.zip
    ditto -c -k --keepParent "$APP" build/AppOffice.zip
    echo "压缩好了：build/AppOffice.zip"
fi

if [ "$INSTALL" = 1 ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/AppOffice.app"
    cp -R "$APP" "$HOME/Applications/"
    echo "已安装：$HOME/Applications/AppOffice.app"
fi
