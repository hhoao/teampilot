# TeamPilot

<p align="center">
  <img src="assets/icon.svg" alt="TeamPilot" width="100"/>
</p>


<p align="center">
  <a href="README.md">English</a> •
  <a href="#核心功能">核心功能</a> •
  <a href="#安装">安装</a> •
  <a href="#支持的-cli">支持的 CLI</a> •
  <a href="#开发">开发</a> •
  <a href="#许可证">许可证</a> •
  <a href="#社区">社区</a>
</p>

<div align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="License"></a>
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/github/v/release/hhoao/teampilot?logo=github&label=Release" alt="TeamPilot Release"></a>
  <a href="https://github.com/hhoao/teampilot/stargazers"><img src="https://img.shields.io/github/stars/hhoao/teampilot?logo=github&label=Stars" alt="TeamPilot Stars"></a>
  <a href="https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml"><img src="https://github.com/hhoao/teampilot/actions/workflows/client-verify.yml/badge.svg" alt="TeamPilot CI"></a>
  <br>
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black" alt="Linux"></a>
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/badge/macOS-000000?logo=apple&logoColor=white" alt="macOS"></a>
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/badge/Windows-0078D6?logo=windows&logoColor=white" alt="Windows"></a>
  <a href="https://github.com/hhoao/teampilot/releases"><img src="https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=black" alt="Android"></a>
  <a href="https://qm.qq.com/"><img src="https://img.shields.io/badge/QQ%20群-1016450915-0099FF?logo=tencentqq&logoColor=white" alt="TeamPilot QQ Group"></a>
  <a href="https://discord.com/channels/1518523215767666719/1518523216912449669"><img src="https://img.shields.io/badge/Discord-加入群组-5865F2?logo=discord&logoColor=white" alt="TeamPilot Discord"></a>
</div>
**TeamPilot** 是一个集成主流 Agent CLI （Claude code、Codex等）的全平台（兼移动端）用户易用的 Agent 工作台， 它可以作为一个对话助手，也可以作为一个功能齐全的 Agent 驱动的 IDE。它在目前流行的 Agent CLI 之上封装一个 UI 层，将它们的聊天记录可视化、配置文件多层隔离化，它能在一个地方管理全 Agent CLI 全局、不同的工作区之间特定的Skills、MCP、Hooks，以及可以给每个Agent CLI配置多种供应商，以让每个会话都能快速使用所有 CLI 的所有自定义模型，同时它还具有独特的专家助手和能让所有 Agent CLI 在多台机器协同工作的功能，它能给任何人提供非常方便的定制化对话能力。

![readme-overview-1](./assets/readme-overview-1.png)

![readme-overview-2](./assets/readme-overview-2.png)

## 核心功能

### 全平台一致的 Agent 客户端

目前市面上的无论是Codex、Claude Code，它们都只有在桌面客户端拥有最丰富的功能，而移动端大多只能对话聊天，而 Teampilot 使用 Flutter，内部抽离了多个文件系统实现，让用户无论是在桌面端还是移动端，都能体验完整一致的功能。

### 多 CLI 功能抽象隔离

TeamPilot的多 CLI功能抽象隔离，将不同 Agent 的 Skills、MCP、Hooks、插件管理都抽象成可视化的用户管理界面，用户只需要在管理界面安装启用相应的功能，即可在聊天时在不同CLI体验到相应的功能，同时 Teampilot 还可以给 Agent CLI 配置多个不同的供应商和凭据，让有多个账户、供应商API的用户可以快速切换模型，专注开发。

### 功能齐全的Agent开发环境

TeamPilot提供常见Agent IDE 能力，包括但不限于，Agent用量查询监听、自动化、任务完成后提示、文件树代码编辑器，源代码管理，（Git 提交图、查看Commit信息、Commit、多分支文件改动对比)、工作区、会话内容搜索、代码文档阅读编辑器、终端工具、快速启动等等。

<p align="center">
  <img src="./assets/readme-banner.png" alt="弧迹" width="640"/>
</p>

### 易用的用户界面

所有的Agent CLI只能在终端中运行，它们都让用户难以操作使用，用户体验差，而且多个 CLI 会让用户来回切换心力疲惫，TeamPilot将目前常用的Agent CLI都集成到了一个用户界面，让用户开发更加专注和高效。

### 专家助手

默认的 Agent 开发往往难以拥有和匹配现实生活中专家精通的能力和需求，而Skills、Prompt、MCP又难以快速配置和切换，Teampilot提供了专家配置功能，让用户可以高度自定义配置多个强力独特的专家，它们启用后都能应用到当前的聊天会话中，不会和其他的会话冲突，可以在对话时快速切换使用。

### 和多 Agent CLI 专家团队协作

若全程只用一个模型，往往要么在简单改动上浪费高价 Token，要么在方案与跨模块核对上力不从心。TeamPilot 让**每个成员绑定自己的模型档位**，在同一团队里并行跑不同「智商 / 速度 / 成本」的 Agent：

团队由多个专家组成，**各自独立**指定不同的CLI、模型、Provider、系统提示词、启动参数以及所处的机器，聊天时每个成员会有不同的上下文，不同的配置进行相互通信完成工作。

![readme-team-collaboration](./assets/readme-team-collaboration.png)

### 高性能

Teampilot使用了Flutter开发，内部进行了多处优化，它让用户界面的每一个点击都丝滑流畅、每个会话都能快速启动，而且即使对话千轮用户界面还是流畅依旧。

### 完备的远程开发能力

Teampilot提供多种场景远程对话的能力，可以在移动端 app 启动时通过 ssh 连接远程环境，可以配置多个ssh配置，在创建工作区时选中使用进行远程开放，还可以在一个工作区同时包含本地和远程目录，可快速切换环境对话，也可以配置团队让远程和本地协调开发。

### 扩展能力（还在开发）

RTK、CodeGraph

## 安装

在 [GitHub Releases](https://github.com/hhoao/teampilot/releases) 打开最新版本，按系统下载对应文件（文件名形如 `teampilot-<版本>-…`）。

### Linux

**Debian / Ubuntu（`.deb`，推荐）**

```bash
sudo dpkg -i teampilot-*-linux.deb
# 若提示依赖缺失：
sudo apt install -f
```

安装后从应用菜单启动 **TeamPilot**。卸载：`sudo apt remove teampilot`（包名以 deb 元数据为准）。

**AppImage（免安装）**

```bash
chmod +x teampilot-*-linux.AppImage
./teampilot-*-linux.AppImage
```

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

Android 版**不运行本机 PTY**，需通过 **SSH** 连接已安装目标 Agent CLI 的 Linux/macOS/Windows（WSL）主机。

1. 根据 CPU 架构下载 `teampilot-*-arm64-v8a.apk`（多数新机型）或 `teampilot-*-armeabi-v7a.apk`。
2. 允许「未知来源」后安装 APK。
3. 打开应用，在 **设置** 中配置 SSH 主机、用户与密钥（或密码）。
4. 确保远端已安装 CLI 且可在 SSH 登录后的 shell 中执行。

## 支持的 CLI

| CLI | 终端会话 | Provider 配置 | 说明 |
|-----|----------|---------------|------|
| **Claude Code** | ✅ | ✅ | 默认团队 CLI；引导向导可协助检测/安装。 |
| **Codex** | ✅ | ✅ | 可启动；通过消息总线参与混合团队。 |
| **opencode** | ✅ | ✅ | 配置走 `OPENCODE_CONFIG_DIR`。 |
| **cursor** | ✅ | ✅ | `cursor-agent`；按成员隔离 HOME。 |
| **flashskyai** | ✅ | ✅ | 应用启动时自动探测路径。 |



## 开发

| 文档 | 读者 | 内容 |
|------|------|------|
| [开发指南](docs/DEVELOPMENT.md) | 贡献者 / 维护者 | 环境、本地运行、测试、打包与 CI |
| [AGENTS.md](AGENTS.md) | 贡献者 / AI | 仓库结构、架构约定 |



## 引用

* 内嵌终端使用 **[flutter_alacritty](https://github.com/hhoao/flutter_alacritty)** — 一个基于 Alacritty 的 Rust 引擎驱动的 Flutter 组件。



## 致谢

- 文件图标：[Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)（MIT 协议），作者 Philipp Kief / material-extensions。



## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE)。



## 社区

- **QQ 群**：[112856301](https://qm.qq.com/q/ScSC18EPaE)

- **Discord**：[加入群组](https://discord.com/channels/1518523215767666719/1518523216912449669)

  

<p align="left">
  <img src="./assets/readme-qq-qrcode.jpg" alt="QQ 群二维码" width="220"/>
</p>

欢迎反馈问题、交流用法与贡献想法。
