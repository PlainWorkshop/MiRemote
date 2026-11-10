#!/bin/bash
set -euo pipefail
src='/Library/Audio/Plug-Ins/HAL/MiRemote.driver'
backup='/Library/Audio/Plug-Ins/Disabled/MiRemote.driver'
[[ -d "$src" ]] || { printf 'MiRemote 驱动未安装。\n'; exit 0; }
[[ ! -e "$backup" ]] || { printf '停用目录已有 MiRemote 驱动，未覆盖：%s\n' "$backup" >&2; exit 1; }
printf '将停用 MiRemote 驱动并保留可恢复副本。需要管理员密码；重启后生效。\n'
read -r -p '按回车继续，或按 Ctrl-C 取消。'
sudo -v
sudo /bin/mkdir -p "$(dirname "$backup")"
sudo /bin/mv "$src" "$backup"
printf '已停用。重启 Mac 后生效。副本：%s\n' "$backup"
