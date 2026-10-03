#!/bin/bash
# 天眼微信 安装包版本门控单元测试
# 用法: bash scripts/test-preinstall.sh
# 说明: 通过 TY_INSTALLED_APP_PATH 环境变量注入"已安装应用"路径，
#       实测 preinstall 在 未安装/同版本/旧版本/新版本 四场景下的覆盖/阻止行为。
set -uo pipefail
cd "$(dirname "$0")/.."

PREINSTALL_SRC="installer/scripts/preinstall"
PKG_VERSION="1.0.0"

# 用测试版本注入生成 preinstall 副本
TMP_TEST="/tmp/tianyan-preinstall-test"
rm -rf "$TMP_TEST"
mkdir -p "$TMP_TEST"/{notinstalled,same,older,newer}/TianYanWeChat.app/Contents
sed "s/@PACKAGE_VERSION@/${PKG_VERSION}/g" "$PREINSTALL_SRC" > "$TMP_TEST/preinstall"
chmod 755 "$TMP_TEST/preinstall"

mkplist() {
  local ver="$1" dir="$2"
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${ver}" \
    "$dir/TianYanWeChat.app/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${ver}" \
    "$dir/TianYanWeChat.app/Contents/Info.plist"
}
mkplist 1.0.0 "$TMP_TEST/same"
mkplist 0.9.0 "$TMP_TEST/older"
mkplist 1.1.0 "$TMP_TEST/newer"

PASS=0
FAIL=0
run_case() {
  local desc="$1" expected="$2" envvar="$3"
  local out rc
  out=$(eval "TY_INSTALLED_APP_PATH='$envvar' $TMP_TEST/preinstall" 2>&1)
  rc=$?
  if [ "$rc" -eq "$expected" ]; then
    echo "PASS [${desc}] 退出码=${rc}（预期 ${expected}）"
    PASS=$((PASS+1))
  else
    echo "FAIL [${desc}] 退出码=${rc}（预期 ${expected}）"
    echo "--- 输出 ---"
    echo "$out"
    FAIL=$((FAIL+1))
  fi
}

run_case "未安装-放行"          0 ""
run_case "同版本-阻止重复安装"  1 "$TMP_TEST/same/TianYanWeChat.app"
run_case "旧版本-自动覆盖升级"  0 "$TMP_TEST/older/TianYanWeChat.app"
run_case "新版本-阻止降级"      1 "$TMP_TEST/newer/TianYanWeChat.app"

echo ""
echo "结果: ${PASS} 通过 / ${FAIL} 失败"
rm -rf "$TMP_TEST"
[ "$FAIL" -eq 0 ]