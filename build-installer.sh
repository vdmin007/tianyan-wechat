#!/bin/bash
# 天眼微信 安装包构建脚本
# 用法: ./build-installer.sh [版本号]
#   - 未指定版本号时，自动从 dist/TianYanWeChat.app 的 Info.plist 读取
# 产物: dist/TianYanWeChat-<版本>.pkg
#
# 版本管理规则（实现"发现老版本自动覆盖，不重复安装"）：
#   preinstall 脚本在安装前检测 /Applications/TianYanWeChat.app：
#   - 已安装版本 < 包版本 -> 放行，自动覆盖升级
#   - 已安装版本 == 包版本 -> 中止安装（避免重复安装）
#   - 已安装版本 > 包版本 -> 中止安装（避免降级覆盖）
#   - 未安装 -> 正常安装
set -euo pipefail
cd "$(dirname "$0")"

APP_DIR="dist/TianYanWeChat.app"
PKG_NAME_BASE="TianYanWeChat"
INSTALL_LOCATION="/Applications"
BUNDLE_ID="com.tianyan.wechat"

echo "==> 0/4 前置检查"
if [ ! -d "$APP_DIR" ]; then
  echo "错误: 未找到 $APP_DIR，请先运行 ./build.sh release" >&2
  exit 1
fi

# 从 app 读取版本
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_DIR/Contents/Info.plist")
APP_BUILD=$(plutil -extract CFBundleVersion raw "$APP_DIR/Contents/Info.plist")
if [ -z "${1:-}" ]; then
  PKG_VERSION="$APP_VERSION"
else
  PKG_VERSION="$1"
fi
echo "应用版本: $APP_VERSION (build $APP_BUILD) / 安装包版本: $PKG_VERSION"

# 临时工作目录
TMP=".installer-tmp"
rm -rf "$TMP"
mkdir -p "$TMP/payload" "$TMP/scripts" "$TMP/resources" "$TMP/dist"

echo "==> 1/4 注入版本号到 preinstall/postinstall"
sed "s/@PACKAGE_VERSION@/${PKG_VERSION}/g" installer/scripts/preinstall > "$TMP/scripts/preinstall"
sed "s/@PACKAGE_VERSION@/${PKG_VERSION}/g" installer/scripts/postinstall > "$TMP/scripts/postinstall"
chmod 755 "$TMP/scripts/preinstall" "$TMP/scripts/postinstall"
# 清理 AppleDouble 残留，避免混入包内 Scripts 目录（必须在 pkgbuild 之前）
find "$TMP" -name '._*' -delete

echo "==> 2/4 构建组件包 (pkgbuild)"
# 注: 本机无 Developer ID 证书，安装包不做数字签名；
# 双击安装时若遇 Gatekeeper 拦截，右键->打开 或 sudo installer 安装即可（详见 README 安装说明）。
pkgbuild \
  --component "$APP_DIR" \
  --install-location "$INSTALL_LOCATION" \
  --identifier "$BUNDLE_ID" \
  --version "$PKG_VERSION" \
  --scripts "$TMP/scripts" \
  "$TMP/payload/TianYanWeChat-component.pkg"

echo "==> 3/4 构建分发安装包 (productbuild)"
sed "s/@PACKAGE_VERSION@/${PKG_VERSION}/g" installer/resources/distribution.xml > "$TMP/resources/distribution.xml"
cp installer/resources/welcome.html installer/resources/conclusion.html "$TMP/resources/"

OUT_PKG="dist/${PKG_NAME_BASE}-${PKG_VERSION}.pkg"
productbuild \
  --distribution "$TMP/resources/distribution.xml" \
  --package-path "$TMP/payload" \
  --resources "$TMP/resources" \
  "$TMP/dist/${PKG_NAME_BASE}-${PKG_VERSION}.pkg"

# 拷贝到最终位置
mkdir -p dist
cp "$TMP/dist/${PKG_NAME_BASE}-${PKG_VERSION}.pkg" "$OUT_PKG"

echo "==> 4/4 校验产物"
echo "生成: $OUT_PKG"
ls -lh "$OUT_PKG"

# 清理中间文件
rm -rf "$TMP"

echo "完成。安装: open $OUT_PKG"
echo "静默安装: sudo installer -pkg $OUT_PKG -target /"
echo "(安装包内已含版本门控：旧版本自动覆盖升级，相同/更新版本拒绝重复安装)"