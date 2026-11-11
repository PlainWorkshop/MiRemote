#!/bin/bash
set -euo pipefail
src="${1:-/Applications/MiRemote.app}"
[[ -d "$src" ]] || { printf '应用不存在：%s\n' "$src" >&2; exit 1; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$src/Contents/Info.plist")
[[ "$identifier" == 'local.codex.MiRemoteButtons' ]] || { printf '应用标识不匹配，未移动。\n' >&2; exit 1; }
trash="${HOME}/.Trash/MiRemoteButtons-$(date +%Y%m%d%H%M%S).app"
[[ ! -e "$trash" ]] || { printf '废纸篓中存在同名文件，未移动。\n' >&2; exit 1; }
printf '请先从菜单栏退出应用；将移动到废纸篓：%s\n' "$src"
read -r -p '按回车继续，或按 Ctrl-C 取消。'
mv "$src" "$trash"
printf '已移至废纸篓：%s\n' "$trash"
