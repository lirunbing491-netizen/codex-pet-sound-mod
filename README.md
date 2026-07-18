# Codex Pet Sound Mod

通用 Codex 桌宠互动音频 Mod。它不包含任何桌宠资源，也不分发 Codex 本体；用户可以继续使用自己安装到 `.codex\pets\<pet-id>` 的任意自定义桌宠。

> 当前版本仅支持 Windows。macOS 和 Linux 尚未适配。
>
> This version currently supports Windows only. macOS and Linux are not supported yet.

## 原理

安装器会基于本机已安装的 Codex 创建一个用户目录下的可写 overlay：

```text
%USERPROFILE%\.codex\pet-sound-mod
```

patched overlay 会把桌宠互动事件写入：

```text
%USERPROFILE%\.codex\pet-sound-mod\logs\pet-events.log
```

音频桥接脚本随 modded Codex 启动，监听该事件日志。每次触发时，它读取：

```text
%USERPROFILE%\.codex\config.toml
```

如果当前选中的是：

```toml
selected-avatar-id = "custom:<pet-id>"
```

则随机播放：

```text
%USERPROFILE%\.codex\pets\<pet-id>\sounds\*.wav
```

## 安装

双击运行：

```text
tools\install-codex-pet-sound-mod.cmd
```

或在 PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\install-codex-pet-sound-mod.ps1"
```

如果已经安装过，需要刷新 overlay：

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\install-codex-pet-sound-mod.ps1" -Force
```

## 启动

安装完成后，用生成的入口启动：

```text
%USERPROFILE%\.codex\pet-sound-mod\Start-Codex-Pet-Sound.cmd
```

不要直接双击 overlay 里的 `ChatGPT.exe`，否则音频桥不会自动启动。

## 给任意桌宠添加声音

先按 Codex 原生方式安装并选择你的自定义桌宠，然后创建：

```text
%USERPROFILE%\.codex\pets\<pet-id>\sounds
```

把 `.wav` 音效放进去即可。文件名不重要，触发时会从所有非空 `.wav` 中随机选择一个。

示例：

```text
%USERPROFILE%\.codex\pets\my-pet\sounds\click-01.wav
%USERPROFILE%\.codex\pets\my-pet\sounds\task-start.wav
```

当前运行时只支持 `.wav`。如果你的素材是 `.mp3`、`.m4a`、`.aac` 等格式，请先转换成 `.wav`。

## 切换桌宠

默认安装不绑定任何具体桌宠。只要 Codex 当前选择的是某个自定义桌宠 `custom:<pet-id>`，音频桥就会播放该桌宠自己的：

```text
.codex\pets\<pet-id>\sounds\*.wav
```

因此你可以安装多个自定义桌宠，并给每个桌宠各自放一套声音。切换桌宠后无需重装 Mod。

## 运行环境

- Windows 版 Codex 桌面应用。当前实现依赖 WindowsApps 路径解析、Windows junction、`powershell.exe` 和 `winmm.dll PlaySound`，不能直接用于 macOS 或 Linux。
- Windows PowerShell：`powershell.exe`
- 已安装并能正常运行的 Codex 桌面版
- Node.js/npm：`npx.cmd` 需要在 `PATH` 中
- 首次运行 `npx --yes @electron/asar` 时需要能访问 npm，除非本机已有缓存

## 回退和卸载

关闭 modded Codex 后，直接启动官方 Codex 即可回退。

如需删除 Mod，删除：

```text
%USERPROFILE%\.codex\pet-sound-mod
```

不要删除 `.codex\pets\<pet-id>`，那是用户自己的桌宠资产。
