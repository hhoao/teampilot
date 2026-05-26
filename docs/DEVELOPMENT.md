# 开发指南

面向贡献者与维护者。用户使用说明见 [README.md](../README.md)；仓库架构与 AI 协作约定见 [AGENTS.md](../AGENTS.md)。英文版：[DEVELOPMENT.en.md](DEVELOPMENT.en.md)。

## 环境要求

| 项目 | 说明 |
|------|------|
| [Flutter](https://docs.flutter.dev/get-started/install) | **stable**；`client` 要求 SDK `^3.8.1` |
| Git 子模块 | 首次克隆需初始化 `client/packages/`  vendored 依赖 |
| `flashskyai` | 本地跑通团队终端时需在 **PATH** 或应用设置中配置 |
| `claude` | 可选；调试 Claude 团队 / 引导流程时需要 |
| 目标平台 | **Linux / macOS / Windows / Android**（与 CI 一致） |

## 首次克隆

```bash
git clone <repo-url>
cd flashskyai-ui
git submodule update --init --recursive
```

## 本地开发

在 `client` 目录下操作：

```bash
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart   # 首次 / 清缓存后：下载 Noto Sans SC（约 50MB，已 gitignore）
flutter run -d linux      # 或 macos、windows、android
```

应用禁用 `google_fonts` 运行时拉取；简体中文界面依赖 `client/google_fonts/` 内嵌字体。

修改带 `json_serializable` 的模型后：

```bash
cd client
dart run build_runner build --delete-conflicting-outputs
```

### 静态分析

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
```

## 运行测试

单元与组件测试（默认，不含 integration 标签）：

```bash
cd client
flutter test --exclude-tags integration
```

单文件或按名称：

```bash
flutter test test/widget_test.dart
flutter test --plain-name="test name"
```

Linux 上可本地跑 PTY 集成测试（需先构建并设置库路径）：

```bash
cd client
flutter build linux --debug
LD_LIBRARY_PATH=build/linux/x64/debug/bundle/lib flutter test --tags integration
```

## 打包发布

CI 使用 [fastforge](https://pub.dev/packages/fastforge) 在 `client/dist/` 产出安装包：

| 平台 | 产物 |
|------|------|
| Linux | `.deb`、`.AppImage` |
| macOS | `.dmg` |
| Windows | `.msix`、`.exe`（Inno Setup）、`.zip` |
| Android | `teampilot-<version>-armeabi-v7a.apk`、`…-arm64-v8a.apk` |

**发版（推荐）**：合并到 `main` 前在 `client/pubspec.yaml` 中递增 `version:`。[Auto Tag on Version Bump](../.github/workflows/auto-tag.yml) 会检测版本变更、自动推送 **`v*`** 标签，并通过 `workflow_dispatch` 触发 [Release Packages](../.github/workflows/release.yml)（Actions 用 `GITHUB_TOKEN` 推 tag 不会连锁触发其它 workflow）。Release 说明仍由 [git-cliff](https://git-cliff.org/) 根据**自上一版 tag 以来**的 Conventional Commits 生成，与手动打 tag 时相同。

也可手动 `git tag vX.Y.Z && git push origin vX.Y.Z`（本地 push 会走 `release.yml` 的 `on.push.tags`），或在 Release Packages 的 **workflow_dispatch** 中指定任意 `ref` 构建（不创建 Release，除非当前 ref 已是 tag）。

对 `client/` 的变更在 [Client Build Verify](../.github/workflows/client-verify.yml) 中于 **Linux / Windows / macOS / Android** 上执行：`flutter analyze` 与 `flutter test`（不含 integration 标签）。

### 本地打包示例

```bash
dart pub global activate fastforge
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform linux --targets deb,appimage
```

Windows `.exe` 需安装 **Inno Setup 6**（与 CI 一致）：

```powershell
cd client
flutter pub get
dart run tool/sync_bundled_google_fonts.dart
fastforge package --platform windows --targets exe
```

仅生成可运行程序（无安装向导）：

```powershell
flutter build windows --release
# 输出：client/build/windows/x64/runner/Release/TeamPilot.exe
```

各平台系统依赖以 CI 工作流为准；Linux 细节见 [`client/linux/packaging/README.md`](../client/linux/packaging/README.md)。

## 相关文档

| 文档 | 内容 |
|------|------|
| [AGENTS.md](../AGENTS.md) | AI 协作指南：架构、关键路径与改代码约定 |
| [CLAUDE.md](../CLAUDE.md) | Claude Code 入口（指向 AGENTS.md） |
| [插件管理设计](superpowers/specs/2026-05-23-plugin-management-design.md) | 插件架构与存储 |
| [RTK 集成设计](superpowers/specs/2026-05-24-rtk-integration-design.md) | Token 压缩钩子 |
| [Linux 打包](../client/linux/packaging/README.md) | fastforge / deb / AppImage |
