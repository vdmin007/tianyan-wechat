#!/bin/bash
# 天眼微信构建脚本
# 用法: ./build.sh
# 产物: dist/TianYanWeChat.app
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TianYanWeChat"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BUILD_CFG="${1:-release}"

echo "==> 1/3 编译源码 (swift build -c $BUILD_CFG)"
swift build -c "$BUILD_CFG"

echo "==> 2/3 组装 .app 包"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

BIN=".build/$BUILD_CFG/$APP_NAME"
if [ ! -f "$BIN" ]; then
  echo "错误: 找不到编译产物 $BIN" >&2
  exit 1
fi
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"

# 应用图标（黑色金属微信风 Logo）
if [ -f "assets/AppIcon.icns" ]; then
  cp "assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  echo "    已集成图标 assets/AppIcon.icns"
else
  echo "警告: assets/AppIcon.icns 不存在，应用将使用默认图标" >&2
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>天眼微信</string>
    <key>CFBundleDisplayName</key>
    <string>天眼微信</string>
    <key>CFBundleIdentifier</key>
    <string>com.tianyan.wechat</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>TianYanWeChat</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> 3/3 本地签名 (ad-hoc)"
codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "完成: $APP_DIR"
echo "运行: open $APP_DIR"
echo "(源码方式: swift run 亦可直接调试)"