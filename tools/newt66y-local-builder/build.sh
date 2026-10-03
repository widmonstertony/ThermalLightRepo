#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
OUTPUT_DIR="$SCRIPT_DIR/output"
EXPECTED_SHA256="feb2e4559025a45943bbace799fc9c2c81b7bed6a6d32579478d1368e76dc785"
EXPECTED_BUNDLE_ID="com.cl.NewT66y.2026"
EXPECTED_VERSION="2.3.7"
PACKAGE_ID="com.tony.newt66y.localbuild"
PACKAGE_VERSION="2.3.7-2"
ALLOW_OTHER_BUILD=0
OUTPUT_FORMAT="deb"
IPA_PATH=""
PATCH_DYLIB="$SCRIPT_DIR/payload/NewTWebFixV8-ios.dylib"
INJECT_TOOL="$SCRIPT_DIR/tools/inject_macho.py"

usage() {
  cat <<'EOF'
Usage:
  ./Build-NewT66y.command [/path/to/1024app_ios_2.3.7.ipa]
  ./Build-Universal-IPA.command [/path/to/1024app_ios_2.3.7.ipa]
  ./build.sh [--accept-other-build] /path/to/1024app_ios_2.3.7.ipa

The default mode accepts only the locally validated reference SHA-256. Use
--accept-other-build only when you trust a differently signed/repacked copy.
The bundle identifier, app version, archive layout, and arm64 executable are
still validated.

--ipa builds one IPA for iPad installation and PlayCover 3.1.0 import.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --accept-other-build)
      ALLOW_OTHER_BUILD=1
      shift
      ;;
    --ipa)
      OUTPUT_FORMAT="ipa"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "错误：未知选项 $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$IPA_PATH" ]]; then
        echo "错误：只能指定一个 IPA。" >&2
        exit 2
      fi
      IPA_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$IPA_PATH" && -f "$SCRIPT_DIR/1024app_ios_2.3.7.ipa" ]]; then
  IPA_PATH="$SCRIPT_DIR/1024app_ios_2.3.7.ipa"
fi

if [[ -z "$IPA_PATH" ]]; then
  printf '请把你合法取得的 1024app_ios_2.3.7.ipa 拖到这里，然后按回车：\n> '
  IFS= read -r IPA_PATH
  IPA_PATH="${IPA_PATH#\'}"
  IPA_PATH="${IPA_PATH%\'}"
  IPA_PATH="${IPA_PATH#\"}"
  IPA_PATH="${IPA_PATH%\"}"
  IPA_PATH="${IPA_PATH//\\ / }"
fi

if [[ ! -f "$IPA_PATH" ]]; then
  echo "错误：找不到 IPA：$IPA_PATH" >&2
  exit 1
fi

for command_name in unzip shasum file tar ar ditto python3 codesign zip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "错误：缺少系统命令 $command_name。请在 macOS 上运行此工具。" >&2
    exit 1
  fi
done

if [[ ! -f "$PATCH_DYLIB" || ! -f "$INJECT_TOOL" ]]; then
  echo "错误：构建工具缺少 NewTWebFix iOS 补丁或 Mach-O 注入工具。" >&2
  exit 1
fi

if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "错误：找不到 macOS PlistBuddy。请在 macOS 上运行此工具。" >&2
  exit 1
fi

IPA_SHA256="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
if [[ "$IPA_SHA256" != "$EXPECTED_SHA256" ]]; then
  if [[ "$ALLOW_OTHER_BUILD" -ne 1 ]]; then
    cat >&2 <<EOF
错误：IPA SHA-256 与已验证参考副本不一致。
实际：$IPA_SHA256
参考：$EXPECTED_SHA256

如果这是你信任的同版本重签名副本，请先自行核实来源，再使用：
  ./build.sh --accept-other-build "$IPA_PATH"
EOF
    exit 1
  fi
  echo "警告：正在处理非参考哈希的 IPA：$IPA_SHA256" >&2
fi

if unzip -Z1 "$IPA_PATH" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  echo "错误：IPA 包含不安全的绝对路径或上级目录路径。" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/newt66y-builder.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

EXTRACT_DIR="$WORK_DIR/extracted"
PACKAGE_ROOT="$WORK_DIR/package-root"
CONTROL_DIR="$WORK_DIR/control"
DEB_WORK="$WORK_DIR/deb"
mkdir -p "$EXTRACT_DIR" "$PACKAGE_ROOT/var/jb/Applications" "$CONTROL_DIR" "$DEB_WORK" "$OUTPUT_DIR"

unzip -q "$IPA_PATH" -d "$EXTRACT_DIR"

APP_LIST="$WORK_DIR/app-list.txt"
find "$EXTRACT_DIR/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print >"$APP_LIST" 2>/dev/null || true
APP_COUNT="$(awk 'END { print NR + 0 }' "$APP_LIST")"
if [[ "$APP_COUNT" -ne 1 ]]; then
  echo "错误：IPA 必须包含且只能包含一个 Payload/*.app。" >&2
  exit 1
fi

SOURCE_APP="$(sed -n '1p' "$APP_LIST")"
if find "$SOURCE_APP" -type l -print -quit | grep -q .; then
  echo "错误：App 包含符号链接；为避免越界读取，构建已停止。" >&2
  exit 1
fi
INFO_PLIST="$SOURCE_APP/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "错误：App 缺少 Info.plist。" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "错误：Bundle ID 应为 $EXPECTED_BUNDLE_ID，实际为 ${BUNDLE_ID:-<空>}。" >&2
  exit 1
fi
if [[ "$APP_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "错误：App 版本应为 $EXPECTED_VERSION，实际为 ${APP_VERSION:-<空>}。" >&2
  exit 1
fi
if [[ -z "$EXECUTABLE_NAME" || ! -f "$SOURCE_APP/$EXECUTABLE_NAME" ]]; then
  echo "错误：找不到 Info.plist 指定的主程序。" >&2
  exit 1
fi
if ! file "$SOURCE_APP/$EXECUTABLE_NAME" | grep -q 'Mach-O 64-bit executable arm64'; then
  echo "错误：主程序不是预期的 arm64 Mach-O 可执行文件。" >&2
  exit 1
fi

if [[ "$OUTPUT_FORMAT" == "ipa" ]]; then
  TARGET_APP="$WORK_DIR/ipa/Payload/NewT66y.app"
  mkdir -p "$(dirname "$TARGET_APP")"
else
  TARGET_APP="$PACKAGE_ROOT/var/jb/Applications/NewT66y.app"
fi
ditto "$SOURCE_APP" "$TARGET_APP"
rm -rf "$TARGET_APP/_CodeSignature"
rm -f "$TARGET_APP/embedded.mobileprovision"
find "$TARGET_APP" -name '.DS_Store' -delete
chmod 0755 "$TARGET_APP/$EXECUTABLE_NAME"

mkdir -p "$TARGET_APP/Frameworks"
cp "$PATCH_DYLIB" "$TARGET_APP/Frameworks/NewTWebFixV8.dylib"
chmod 0755 "$TARGET_APP/Frameworks/NewTWebFixV8.dylib"
python3 "$INJECT_TOOL" \
  "$TARGET_APP/$EXECUTABLE_NAME" \
  "$WORK_DIR/$EXECUTABLE_NAME.patched" \
  '@executable_path/Frameworks/NewTWebFixV8.dylib'
mv "$WORK_DIR/$EXECUTABLE_NAME.patched" "$TARGET_APP/$EXECUTABLE_NAME"
chmod 0755 "$TARGET_APP/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.cl.NewT66y.2026.webfix8' "$TARGET_APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 小草补丁V8' "$TARGET_APP/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string 小草补丁V8' "$TARGET_APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 小草补丁V8' "$TARGET_APP/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :CFBundleName string 小草补丁V8' "$TARGET_APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :UIFileSharingEnabled true' "$TARGET_APP/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :UIFileSharingEnabled bool true' "$TARGET_APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSSupportsOpeningDocumentsInPlace true' "$TARGET_APP/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :LSSupportsOpeningDocumentsInPlace bool true' "$TARGET_APP/Info.plist"

if [[ "$OUTPUT_FORMAT" == "ipa" ]]; then
  codesign --force --sign - "$TARGET_APP/Frameworks/NewTWebFixV8.dylib"
  codesign --force --deep --sign - "$TARGET_APP"
  codesign --verify --deep --strict "$TARGET_APP"

  OUTPUT_NAME="NewT66y-2.3.7-Universal-Mac-iPad-VidCatch.ipa"
  OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"
  rm -f "$OUTPUT_PATH"
  (
    cd "$WORK_DIR/ipa"
    COPYFILE_DISABLE=1 zip -qry "$OUTPUT_PATH" Payload \
      -x '*/.DS_Store' -x '*/._*' -x '__MACOSX/*'
  )
  unzip -t "$OUTPUT_PATH" >/dev/null
  OUTPUT_SHA256="$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
  cat <<EOF

通用 IPA 构建成功：
  $OUTPUT_PATH

输入 IPA SHA-256：$IPA_SHA256
输出 IPA SHA-256：$OUTPUT_SHA256

iPad：使用 TrollStore、越狱安装器，或用自己的证书重新签名后安装。
Mac：把同一份 IPA 导入 PlayCover 3.1.0；PlayCover 会转换为 Mac Catalyst。
下载位置：iPad 的“文件 > 在我的 iPad 上 > 小草补丁V8 > VidCatch”。

请勿把生成的 IPA 提交到公开仓库或转发给其他人。
EOF
  exit 0
fi

INSTALLED_SIZE="$(du -sk "$TARGET_APP" | awk '{print $1}')"
cat >"$CONTROL_DIR/control" <<EOF
Package: $PACKAGE_ID
Name: NewT66y 2.3.7 (Local Build)
Version: $PACKAGE_VERSION
Architecture: iphoneos-arm64
Description: Locally patched NewT66y 2.3.7 with iPad Files video download support for the owner's iOS/iPadOS 16 rootless jailbreak device. The public Tony Repo does not distribute the app binary.
Maintainer: Local Builder User
Author: Original application rights remain with their respective owner
Section: Applications
Depends: firmware (>= 16.0), firmware (<< 17.0), ldid, uikittools
Priority: optional
Installed-Size: $INSTALLED_SIZE
Rootless: true
EOF

cat >"$CONTROL_DIR/preinst" <<'EOF'
#!/bin/sh
killall NewT66y >/dev/null 2>&1 || true
exit 0
EOF

cat >"$CONTROL_DIR/postinst" <<'EOF'
#!/bin/sh
set -e
APP_PATH=/var/jb/Applications/NewT66y.app
EXECUTABLE="$APP_PATH/NewT66y"
PATCH_DYLIB="$APP_PATH/Frameworks/NewTWebFixV8.dylib"

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$PATCH_DYLIB"
  ldid -S "$EXECUTABLE"
elif [ -x /var/jb/usr/bin/ldid ]; then
  /var/jb/usr/bin/ldid -S "$PATCH_DYLIB"
  /var/jb/usr/bin/ldid -S "$EXECUTABLE"
else
  echo "NewT66y local package requires ldid." >&2
  exit 1
fi

chmod 0755 "$EXECUTABLE"
if command -v uicache >/dev/null 2>&1; then
  uicache -p "$APP_PATH" || true
elif [ -x /var/jb/usr/bin/uicache ]; then
  /var/jb/usr/bin/uicache -p "$APP_PATH" || true
fi
exit 0
EOF

cat >"$CONTROL_DIR/prerm" <<'EOF'
#!/bin/sh
killall NewT66y >/dev/null 2>&1 || true
exit 0
EOF

cat >"$CONTROL_DIR/postrm" <<'EOF'
#!/bin/sh
if command -v uicache >/dev/null 2>&1; then
  uicache -u com.cl.NewT66y.2026.webfix8 || true
elif [ -x /var/jb/usr/bin/uicache ]; then
  /var/jb/usr/bin/uicache -u com.cl.NewT66y.2026.webfix8 || true
fi
exit 0
EOF

chmod 0755 "$CONTROL_DIR/preinst" "$CONTROL_DIR/postinst" "$CONTROL_DIR/prerm" "$CONTROL_DIR/postrm"
printf '2.0\n' >"$DEB_WORK/debian-binary"

export COPYFILE_DISABLE=1
tar -C "$CONTROL_DIR" -czf "$DEB_WORK/control.tar.gz" .
tar -C "$PACKAGE_ROOT" -czf "$DEB_WORK/data.tar.gz" .

OUTPUT_NAME="${PACKAGE_ID}_${PACKAGE_VERSION}_iphoneos-arm64.deb"
OUTPUT_PATH="$OUTPUT_DIR/$OUTPUT_NAME"
rm -f "$OUTPUT_PATH"
(
  cd "$DEB_WORK"
  # macOS ar otherwise adds a Mach-O symbol table and can omit non-object
  # members after ranlib rejects them. Debian archives need plain members.
  ar -rcS "$OUTPUT_PATH" debian-binary control.tar.gz data.tar.gz
)

OUTPUT_SHA256="$(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
cat <<EOF

构建成功：
  $OUTPUT_PATH

输入 IPA SHA-256：$IPA_SHA256
输出 DEB SHA-256：$OUTPUT_SHA256

下一步：把 DEB 传到你自己的 iOS/iPadOS 16 rootless 越狱设备，使用
Sileo、Zebra、Filza 或 dpkg 本地安装。设备需要可用的 ldid 和 uikittools。

请勿把生成的 DEB 提交到公开仓库或转发给其他人。
EOF
