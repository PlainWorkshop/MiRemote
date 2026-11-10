# MiRemote 小米遥控器

macOS 小米蓝牙语音遥控器工具：为遥控器按键配置系统快捷键，把遥控器语音送入独立的 MiRemote 虚拟麦克风。窗口以遥控器模型和引线展示按键，关闭窗口后仍可从菜单栏打开或退出。

## 目前的支持情况

- 已测试小米蓝牙语音遥控器（USB vendor ID `2717`、product ID `32b8`）；其他遥控器不保证兼容。
- 当前开发机为 macOS 27.3，软件和驱动已在此环境验证。其他 macOS 版本及不同机型尚未完整测试；驱动构建目标最低为 macOS 12，这不等于应用已在该版本验证。
- 源码构建需要 Xcode 和命令行工具；音频驱动安装需要管理员权限和重启。蓝牙配对在 macOS 系统设置中完成。
- 本地构建使用 ad-hoc 签名，未使用 Apple Developer ID 签名或公证。macOS 可能要求在隐私与安全性中手动允许打开；重新签名或移动应用后可能需要重新授权。

## 从源码构建并安装

在终端进入仓库根目录：

```sh
scripts/build-app.sh
scripts/build-driver.sh
scripts/install-app.sh
scripts/install-driver.sh
```

构建输出位于 `build/`。安装应用默认复制到 `/Applications/MiRemoteButtons.app`，目标已存在时不会覆盖；可以向 `install-app.sh` 传入其他完整目标路径。安装驱动需要输入管理员密码，安装到 `/Library/Audio/Plug-Ins/HAL/MiRemote.driver`，同名目标已存在时不会覆盖。**保存工作并重启 Mac**，让系统加载新驱动。

首次打开应用后，按窗口提示授予蓝牙、输入监控、辅助功能和发送按键所需的权限。自动化权限只在使用睡眠动作时需要。权限状态窗口会分别显示 HID 按键连接、BLE 语音连接和音频驱动检测结果。应用窗口打开麦克风开关后，选择 MiRemote 作为微信输入法或其他应用的麦克风。语音键映射可以按需要设置；微信输入法需使用与语音键映射相同的快捷键。

音量条显示遥控器解码音频的数字电平（dBFS），不是经过校准的环境声压。语音流经过 MiRemote 驱动转交给使用它作为输入的应用；本程序不默认保存录音。

## 测试

```sh
scripts/test.sh
```

该脚本每次在新的临时目录构建 App，运行引线映射、收音电平及按键自检；它不会安装或替换驱动，也不验证蓝牙实机和外部语音识别。驱动构建同样在临时目录编译后复制到指定输出，构建过程中打印临时目录位置。

驱动仍需在真实系统上验证设备能被加载、输入输出回环，以及遥控器和目标应用的语音识别。安装/卸载时请避免打断正在进行的音频工作。

## 卸载

先从菜单栏退出应用，再执行：

```sh
scripts/uninstall-app.sh
scripts/uninstall-driver.sh
```

应用默认从 `/Applications/MiRemoteButtons.app` 移入废纸篓；如果安装到了其他位置，将路径作为参数传给卸载脚本。驱动卸载脚本将其移出 HAL 目录并存放在 `/Library/Audio/Plug-Ins/Disabled/`，以便恢复。重新启动 Mac 后设备从系统列表消失。脚本不会删除项目源码或其他音频驱动。

## 许可证

应用沿用 MIT 许可证，见 `LICENSE`。MiRemote 驱动基于 BlackHole v0.5.0，使用 GNU GPL v3；对应修改源码完整归档在 `Driver/MiRemote-driver-source.tar.gz`，许可正文见 `Driver/LICENSE`。其他引用见 `THIRD_PARTY_NOTICES.md`。
