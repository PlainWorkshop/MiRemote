#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-$root/build/MiRemote.driver}"
target='/Library/Audio/Plug-Ins/HAL/MiRemote.driver'
[[ -d "$src" ]] || { printf '请先构建驱动：%s\n' "$src" >&2; exit 1; }
[[ ! -e "$target" ]] || { printf '系统中已存在 MiRemote.driver，未覆盖。\n' >&2; exit 1; }
codesign --verify --strict "$src"
printf '将安装 MiRemote 驱动；需要管理员密码。安装后请保存工作并重启 Mac。\n'
read -r -p '按回车继续，或按 Ctrl-C 取消。'
sudo -v
sudo /usr/bin/ditto "$src" "$target"
sudo /usr/sbin/chown -R root:wheel "$target"
codesign --verify --strict "$target"
printf '驱动文件已安装，请重启 Mac 以加载驱动。\n'
