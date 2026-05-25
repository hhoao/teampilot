# TeamPilot

[English](README.en.md) · [开发指南](docs/DEVELOPMENT.md) · 架构与 AI 约定见 [CLAUDE.md](CLAUDE.md)

**TeamPilot** 是基于终端 AI Agent 封装的面向团队易用的桌面客户端。它的核心是 **团队能力**：在 GUI 里为每位成员单独指定模型与提示词，按角色分档协作（省 Token、快实现、准验收），并一键为每个成员启动独立内嵌终端，通过本机或远程的 **`flashskyai` / `claude` CLI** 与 Agent 协作；项目与会话则负责把这套团队绑定到具体仓库与对话上。

![应用预览](assets/image.png)

## 核心功能：团队配置

团队配置是 TeamPilot 与「单终端 + 手写参数」方式的根本区别——**先配好团队，再在聊天工作台里按成员并行工作**。

| 配置项 | 作用 |
|--------|------|
| **团队** | 一套完整的多 Agent 方案：选用 `flashskyai` / `claude` 等 CLI、团队级参数，并绑定该团队专用的技能与插件。 |
| **成员** | 团队内的角色（如 `team-lead`、开发者、审查者）：**各自独立**指定模型、Provider、系统提示词与启动参数；连接会话时为**每位成员单独 spawn 一个 PTY 终端**，模型与上下文互不混用。 |
| **技能 / 插件** | 按团队挂载能力扩展；启动时写入该团队隔离的 CLI 配置目录，成员终端自动继承。 |

### 按成员隔离模型：省 Token、分档协作

若全程只用一个模型，往往要么在简单改动上浪费高价 Token，要么在方案与跨模块核对上力不从心。TeamPilot 让**每个成员绑定自己的模型档位**，在同一团队里并行跑不同「智商 / 速度 / 成本」的 Agent：

| 角色示例 | 常见模型档位 | 适合做什么 |
|----------|--------------|------------|
| 统筹 / 方案 | 高级（如 Opus、旗舰档） | 拆需求、写技术方案、定边界与验收标准 |
| 实现 | 轻量 / 快速（如 Haiku、小模型） | 按方案批量改代码、补样板、跑通主路径 |
| 审查 | 中级（如 Sonnet） | Code review、对照方案查漏、跨文件 / 跨模块一致性 |

这不限于写代码：文档起草、调研汇总、运维排障等**任意多步流水线**都可以这样拆——用强模型把需求「想清楚、写清楚」，用轻模型「快执行」，用中级模型「验结果、对齐跨领域约束」，在控制成本的同时加快落地，也更易**精准完成跨模块、跨职能的复杂需求**（而不必让同一个会话又当架构师又当苦力又当质检）。

**典型用法：**

- **模型分档**：为 `team-lead`、实现位、审查位分别配置不同 Provider / 模型；切换成员标签即切换终端与模型，无需反复改全局设置。
- **分工协作**：`team-lead` 负责统筹与委派（FlashSky AI 要求存在名为 `team-lead` 的成员），其他成员承担实现、审查等子任务，在同一窗口内切换终端即可。
- **场景切换**：为「日常开发」「深度重构」「文档撰写」各建一个团队，换任务时切换团队，无需重配模型与提示词。
- **与会话联动**：打开项目会话时，TeamPilot 将当前团队注入启动参数（如 `--team` / `--member`、独立 `CONFIG_DIR`），并支持恢复历史 CLI 会话。

设置入口：**设置 → 团队配置**（路由 `/team-config`）。团队 JSON 保存在应用数据目录的 `teams/` 下；每位成员的运行时 CLI 配置隔离在 `config-profiles/teams/<团队>/members/…`。

## 为什么选择 TeamPilot？

### 技能与插件（依附于团队）

- **技能（Skills）**：在应用里集中浏览、安装和启用；**按团队**挂载后，该团队下所有成员终端共享同一套能力。
- **插件（Plugins）**：可视化安装与管理扩展；约定「这个项目用哪套插件」时，以团队为单位配置，减少成员间环境不一致。

### 聊天与工作台

- **多标签终端**：多个成员 / 会话放在一个窗口里推进，少开一堆系统终端。
- **项目与会话**：按仓库和对话整理记录，并把**当前选中的团队**绑定到该次工作。
- **自动会话标题**：侧栏一眼看出每条对话在聊什么。
- **右侧工具栏**：文件树、成员列表与提示词就在聊天旁，减少来回切换。

### 设置与集成

- **RTK（可选）**：可在设置中开启，帮助压缩会话占用、延长可用上下文。

## 安装

在 [GitHub Releases](https://github.com/hhoa/flashskyai-ui/releases) 打开最新版本，按系统下载对应文件（文件名形如 `teampilot-<版本>-…`）。

### Linux

**Debian / Ubuntu（`.deb`，推荐）**

```bash
sudo dpkg -i teampilot-*-linux.deb
# 若提示依赖缺失：
sudo apt install -f
```

安装后从应用菜单启动 **TeamPilot**。卸载：`sudo apt remove flashskyai-client`（包名以 deb 元数据为准）。

**AppImage（免安装）**

```bash
chmod +x teampilot-*-linux.AppImage
./teampilot-*-linux.AppImage
```

需要 `libfuse2`（Ubuntu 22.04+ 常需 `sudo apt install libfuse2`）。若希望写入开始菜单 / Dock，可配合 [AppImageLauncher](https://github.com/TheAssassin/AppImageLauncher)。

桌面端在本机直接启动 `flashskyai` / `claude` 终端；也可在设置中改用 **SSH** 连接远端主机（CLI 在远端运行）。

### macOS

1. 下载 `teampilot-*-macos.dmg`。
2. 打开 DMG，将 **TeamPilot** 拖入「应用程序」。
3. 首次启动若被 Gatekeeper 拦截：「系统设置 → 隐私与安全性」中允许，或右键应用 →「打开」。

### Windows

任选一种安装包（同一 Release 中通常都有）：

| 文件 | 说明 |
|------|------|
| `*-windows-setup.exe` | **推荐**：Inno Setup 安装向导，自动创建快捷方式 |
| `*.msix` | 适用于已启用旁加载 / 企业分发的环境 |
| `*.zip` | 便携包：解压后运行其中的 `TeamPilot.exe`，不写注册表 |

若 CLI 安装在 **WSL** 内，可在设置中将应用数据或 CLI 路径指向 WSL；亦可在设置中配置 **SSH** 连接远端 Linux 开发机。

### Android

Android 版**不运行本机 PTY**，需通过 **SSH** 连接已安装 `flashskyai` / `claude` 的 Linux/macOS/Windows（WSL）主机。

1. 根据 CPU 架构下载 `teampilot-*-arm64-v8a.apk`（多数新机型）或 `teampilot-*-armeabi-v7a.apk`。
2. 允许「未知来源」后安装 APK。
3. 打开应用，在 **设置** 中配置 SSH 主机、用户与密钥（或密码）。
4. 确保远端已安装 CLI 且可在 SSH 登录后的 shell 中执行。

## 支持的 CLI

| CLI | 终端会话 | Provider 配置 | 说明 |
|-----|----------|---------------|------|
| **flashskyai** | ✅ | ✅ | 默认团队 CLI；应用启动时自动探测路径。 |
| **claude** | ✅ | ✅ | 引导向导可协助检测/安装。 |
| **codex** | ❌ | ✅ | 仅 Provider 目录管理，暂不支持启动 PTY 会话。 |

## 使用前准备

完成[安装](#安装)后，在**运行 TeamPilot 的机器**（桌面为本机，Android 为 SSH 所连远端）准备：

| 项目 | 说明 |
|------|------|
| **`flashskyai`** | 已安装且在登录 shell 的 **PATH** 中，或在 **设置 → 会话** 中填写 CLI 绝对路径 |
| **`claude`** | 可选；使用 Claude 团队或首次引导安装时需要 |

首次启动可按引导检测 CLI。安装包由 CI 自动构建；从源码编译见 **[开发指南](docs/DEVELOPMENT.md)**。

## 更多文档

| 文档 | 读者 | 内容 |
|------|------|------|
| [开发指南](docs/DEVELOPMENT.md) | 贡献者 / 维护者 | 环境、本地运行、测试、打包与 CI |
| [CLAUDE.md](CLAUDE.md) | 贡献者 / AI | 仓库结构、数据目录、架构约定 |

## 许可证

[MIT License](LICENSE)。
