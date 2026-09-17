# Veycomm

一个原生、轻量的 macOS 菜单栏快捷键工具。它把全局快捷键映射到应用、链接、脚本或文本输入，不使用 Electron，也没有网络请求或分析追踪。

## 功能

- 注册系统级快捷键，即使应用不在前台也可触发
- 动作：打开应用、打开 URL/文件、执行 shell 脚本、粘贴文本
- 菜单栏常驻，隐藏 Dock 图标
- 从设置中添加、编辑、启用或停用动作
- 检测本应用内的快捷键冲突
- 支持 macOS 登录时启动（macOS 13+）
- 所有配置仅保存在本机 `UserDefaults`

为覆盖已被其他应用占用的组合键（例如 `⌘D`），Veycomm 会请求“辅助功能”权限；它只会拦截你已配置的组合键。未授权时仍使用标准系统热键注册。

“粘贴文本”会模拟一次 Command-V，因此 macOS 可能要求你在“系统设置 → 隐私与安全性 → 辅助功能”中授权本应用。

登录启动优先使用 macOS 的 `SMAppService`。未以 Developer ID 签名的本地开发包若被系统拒绝，则自动安装仅属于当前用户的 LaunchAgent；关闭该选项会将其移除。

## 开发与构建

需要 macOS 13 或更新版本，以及完整 Xcode：

```sh
swift run
```

创建本地可运行的 `.app` 包：

```sh
chmod +x Scripts/make-app.sh
Scripts/make-app.sh
open dist/Veycomm.app
```

创建供安装的 DMG（打开后将应用拖到“应用程序”文件夹）：

```sh
Scripts/make-dmg.sh
open dist/Veycomm.dmg
```

在 Xcode 中可用 `File → Open…` 打开 `Package.swift`。发布前请用自己的 Developer ID 证书签名并公证；脚本只使用本地 ad-hoc 签名。

> GitHub Release 中的本地构建 DMG 没有 Developer ID 公证。首次运行时，macOS 可能要求你在“系统设置 → 隐私与安全性”中确认打开。维护者发布正式版本前应配置 Developer ID 签名与 Apple 公证。

## 本机构建、验证与发布

GitHub Actions 只检查源代码，**不会**构建、签名或上传安装包。这样 GitHub Release 中的 DMG 永远就是维护者在本机实际测试过的那一份文件。

每次发布按此顺序操作：

```sh
# 1. 本机构建一个指定版本
VERSION=0.4.0 Scripts/make-app.sh
Scripts/make-dmg.sh

# 2. 打开 dist/Veycomm.dmg，拖入“应用程序”，启动并手动验证：
#    授权、全局快捷键、划词翻译、设置窗口、登录启动。

# 3. 仅在验证通过后，上传当前这个 DMG（不会重新构建）
Scripts/publish-local-release.sh 0.4.0
```

发布脚本会先校验 DMG、要求代码已提交，然后创建 tag 并上传 `dist/Veycomm.dmg`。后续更新仍建议使用 Developer ID 签名与公证，以让 macOS 的权限和信任跨版本稳定保留。

## 快捷键录制

点击快捷键字段后按下组合键。必须包含 Command、Option、Control 或 Shift 中至少一个修饰键，避免劫持普通输入。按 Escape 清除录制状态。

## 许可证

[MIT](LICENSE)
