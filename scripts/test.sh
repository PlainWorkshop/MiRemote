#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/miremote-test.XXXXXXXX")"
printf '测试目录：%s\n' "$scratch"
"$root/scripts/build-app.sh" "$scratch/MiRemoteButtons.app"
exe="$scratch/MiRemoteButtons.app/Contents/MacOS/MiRemoteButtons"
"$exe" --callout-self-test
"$exe" --voice-meter-self-test
"$exe" --modifier-self-test
printf '应用构建和自检通过。未运行音频驱动安装或实体设备交互。\n'
