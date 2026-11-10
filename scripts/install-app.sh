#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/build/MiRemoteButtons.app"
target="${1:-/Applications/MiRemoteButtons.app}"
[[ -d "$src" ]] || { printf '请先运行 scripts/build-app.sh。\n' >&2; exit 1; }
[[ ! -e "$target" ]] || { printf '目标已存在，未覆盖：%s\n' "$target" >&2; exit 1; }
codesign --verify --strict "$src"
ditto "$src" "$target"
codesign --verify --strict "$target"
printf '已安装：%s\n' "$target"
