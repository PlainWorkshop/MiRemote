#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/MiRemote.driver}"
if [[ -e "$out" ]]; then printf '构建目标已存在：%s\n请指定其他路径。\n' "$out" >&2; exit 1; fi
scratch="$(mktemp -d "${TMPDIR:-/tmp}/miremote-driver.XXXXXXXX")"
printf '驱动源码及 Xcode 中间文件：%s\n' "$scratch"
tar -xzf "$root/Driver/MiRemote-driver-source.tar.gz" -C "$scratch"
xcodebuild -project "$scratch/BlackHole.xcodeproj" -scheme BlackHole -configuration Release -derivedDataPath "$scratch/build" PRODUCT_BUNDLE_IDENTIFIER=local.codex.MiRemoteAudio CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 build
source_driver="$scratch/build/Build/Products/Release/BlackHole.driver"
[[ -d "$source_driver" ]] || { printf '未找到构建结果：%s\n' "$source_driver" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
ditto "$source_driver" "$out"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName MiRemote' "$out/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$out"
codesign --verify --deep --strict "$out"
printf '构建完成：%s\n' "$out"
