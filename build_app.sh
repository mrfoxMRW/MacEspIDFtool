#!/bin/bash
# 构建并打包 MacEspIDFtool.app（release）
set -e
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release --disable-sandbox

APP="build/MacEspIDFtool.app"
BIN=".build/release/MacEspIDFtool"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacEspIDFtool"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>MacEspIDFtool</string>
	<key>CFBundleDisplayName</key>
	<string>ESP 日志工具</string>
	<key>CFBundleIdentifier</key>
	<string>local.macsespidftool</string>
	<key>CFBundleExecutable</key>
	<string>MacEspIDFtool</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSUIElement</key>
	<false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" 2>/dev/null || true

echo "==> 完成: $APP"
