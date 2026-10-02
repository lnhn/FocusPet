#!/bin/bash
# 把 SwiftPM 产物包装成可运行的 .app（UserNotifications、自启等功能需要正式 bundle）
# 用法: ./package-app.sh [debug|release]   （默认 debug）
set -e
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
APP=.build/$CONFIG/FocusPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/$CONFIG/FocusPet "$APP/Contents/MacOS/FocusPet"

# SwiftPM 资源包（帧动画素材）：Bundle.module 在 Bundle.main.resourceURL
# （即 Contents/Resources/）下查找
for b in .build/$CONFIG/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

cp Sources/FocusPet/Info.plist "$APP/Contents/Info.plist"
cp "$(dirname "$0")/../FocusPetAssets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# ad-hoc 签名（通知投递对签名有要求）；失败不阻断，直接运行通常也可工作
codesign --force --sign - "$APP/Contents/MacOS/FocusPet" 2>/dev/null || true

echo "打包完成($CONFIG): $(pwd)/$APP"
