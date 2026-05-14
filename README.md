# TeamPilot

[English](README.en.md)

基于 **Flutter** 的 **TeamPilot** 桌面客户端：多会话聊天、团队与技能管理、内嵌终端，以及与会话相关的布局与 LLM 配置。应用通过本机上的 **`flashskyai` CLI** 与后端能力对接。

![应用预览](assets/image.png)

## 功能概览

- **聊天工作台**：按团队与会话组织对话，支持从侧边栏新建项目与会话。
- **团队配置**：管理多团队上下文与相关行为。
- **技能（Skills）**：浏览、安装与管理技能包。
- **设置**：布局（含上下文侧栏）、LLM 配置路径、会话与可执行文件偏好等。
- **桌面体验**：窗口尺寸与主题（明/暗/跟随系统）、界面语言（英文 / 简体中文）。
- **内嵌终端**：基于 `xterm` 与 `flutter_pty` 的本地终端集成。

## 环境要求

| 项目 | 说明 |
|------|------|
| [Flutter](https://docs.flutter.dev/get-started/install) | **stable** 渠道；本仓库 `client` 使用 SDK `^3.8.1` |
| `flashskyai` | 需已安装并在 **PATH** 中可执行（应用启动时会解析其路径） |
| 目标平台 | **Linux**、**macOS**、**Windows WSL**（桌面） |

## 仓库结构

```
teampilot/
├── client/          # Flutter 应用（主要代码与各平台 Runner）
├── docs/            # 设计说明与计划文档
├── assets/          # 仓库级资源（如 README 用图）
└── .github/workflows/
    └── release.yml  # 打标签后的桌面安装包构建与 GitHub Release
```

## 本地开发

在 `client` 目录下操作：

```bash
cd client
flutter pub get
flutter run -d linux    # 或 macos / windows
```

代码生成（若修改了带 `json_serializable` 的模型）：

```bash
cd client
dart run build_runner build --delete-conflicting-outputs
```

### 运行测试

```bash
cd client
flutter test
```

## 打包发布（维护者）

CI 使用 [fastforge](https://pub.dev/packages/fastforge) 在 `client/dist/` 产出安装包：

- **Linux**：`.deb`、`.AppImage`
- **macOS**：`.dmg`
- **Windows**：`.msix`、**`.exe`（Inno Setup 安装包）**、`.zip`

推送符合 `v*` 格式的 **Git tag** 会触发 [Release Desktop Packages](.github/workflows/release.yml)，构建三平台产物并创建 **GitHub Release**。也可在 Actions 中 **手动运行（workflow_dispatch）**，可选指定 `ref`。

对 `client/` 的变更会在 [Client Windows (EXE)](.github/workflows/client-windows.yml) 中自动打 Windows EXE 安装包（PR / `main` 推送），产物以 **Artifact** 形式供下载。

本地打包示例：

```bash
dart pub global activate fastforge
cd client
flutter pub get
fastforge package --platform linux --targets deb,appimage
```

Windows 安装包（`.exe`）依赖本机已安装 **Inno Setup 6**（与 CI 中 `choco install innosetup` 一致），然后执行：

```powershell
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform windows --targets exe
```

若仅需可运行的程序、不要安装向导，可直接：

```powershell
cd client
flutter build windows --release
```

可执行文件位于 `client/build/windows/x64/runner/Release/TeamPilot.exe`。

各平台额外依赖（如 Linux 的 GTK、macOS 的 `appdmg` 等）以 CI 工作流中的安装步骤为准。

## 许可证

[MIT License](LICENSE)。
