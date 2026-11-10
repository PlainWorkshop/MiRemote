#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$root/build/MiRemoteButtons.app}"
if [[ -e "$out" ]]; then printf '构建目标已存在：%s\n请指定其他路径。\n' "$out" >&2; exit 1; fi
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
cp "$root/Resources/Info.plist" "$out/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$out/Contents/Resources/AppIcon.icns"
swiftc "$root"/Sources/*.swift -o "$out/Contents/MacOS/MiRemoteButtons"
codesign --force --sign - --requirements '=designated => identifier "local.codex.MiRemoteButtons"' "$out"
codesign --verify --strict "$out"
printf '构建完成：%s\n' "$out"
