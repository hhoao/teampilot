# 云端 ACP 保活代理设计

- 日期：2026-11-13
- 状态：待审阅
- 来源：移动端未连接远程 TeamPilot 时，发消息后网络断开，当前这一轮会跟着 SSH 或本地进程结束。用户有一台常驻的云端服务器，希望这一轮在云端跑完，手机再连上把输出补回。
- 前置：
  - [Session 与共享状态同步设计](2026-11-08-session-and-shared-state-sync-design.md)（`session-protocol.json` + SSH `forwardLocal` 的公布方式；本设计不复用 session plane 的消息）
  - [桌面 Authority 会话创建与全量委托设计](2026-11-12-desktop-authority-session-creation-design.md)（桌面 App 持有运行时；本设计是另一条更小的路径，不实现那份委托）
- 目标：云端常驻一个小进程，由它握着真实 CLI 的 ACP 连接。手机断线之后，这一轮继续跑。手机再连上时，把断线期间的输出补回来。

## 结论

1. 云端跑一个 ACP 代理进程。它对手机是 ACP Agent，对 Claude、Codex 这类 CLI 是 ACP 客户端。两边都是 ACP 帧，不新造会话协议，不用 WebSocket。
2. 代理只听 `127.0.0.1`。手机用现有 SSH `forwardLocal` 接上去。SSH 断了只断转发。
3. 安装、更新、启动只在 CLI 页面做。云端自己从 GitHub Releases 下载二进制。开会话不上传、不代为启动。
4. 代理在听，且公布的版本与 App 钉住的版本一致时，这条会话走代理。否则仍用现在的 SSH `exec` 拉起 CLI，这一轮不保活。
5. 已经用 SSH `exec` 拉起的会话，代理之后上线也不接管。

## 背景与现状

TeamPilot 自己就是 ACP 客户端。本地用 `AcpProcessTransport.start` 做 `Process.start`，标准输出是换行 JSON。连到远程机器时用 `AcpSshTransport`：同一套参数编成 SSH exec，不用登录 shell。这条通道挂在手机这次 SSH 上，通道一关，远端 CLI 就结束。

`productionAcpSpawner` 负责 `initialize` 和按需 `authenticate`。`AcpSessionRuntime` 没有旧 id 就 `session/new`，有 `acp-session.json` 就 `session/load` 或 `session/resume`。加载失败不会改开 `session/new`。

CLI 是否已安装由 `getCliLocation` 判断，它只查找、不安装。安装在机器设置和 CLI 页面完成。远端工作区准备沿用现在的路径、环境和凭据同步。

ACP 库 `acpd` 已有 Agent 与 Client 两侧。CLI 的 ACP 走标准输入输出，没人握着 stdin，进程就会结束。所以保活必须有一个常驻进程一直当 CLI 的客户端。

## 非目标

- 不做完整 TeamPilot 的 headless，也不做桌面 App 关窗后继续。
- 不把保活做进 session plane，不增加 `prompt.send`。
- 不用 WebSocket，不在公网听端口。
- 不在这一层安装 CLI，不上传登录凭据。CLI 页面现有的安装器保持原样。
- 不做 PTY、Git、文件树、工作区界面。
- 不做团队会话、多座位。第一版只做个人 ACP。
- 不让桌面和手机同时挂在同一条会话上。
- 不在发送消息时自动安装或自动启动代理。
- 不把手机上的二进制上传到云端。
- 不使用 npm 或 pub.dev 作为这一层的安装源。云端不需要为它安装 Node 或 Dart。
- 断线后不自动重发还没写完的那一轮，避免和 CLI 自己存下来的半轮叠成两遍。

## 进程与连接

云端只跑这一个进程。它支持的每种 CLI 在 `127.0.0.1` 上听一个端口。地址写在 `<teampilotRoot>/acp-proxy.json`：

```json
{
  "v": 1,
  "version": "0.1.0",
  "bind": "127.0.0.1",
  "pid": 12345,
  "clis": {
    "claude": { "port": 43111 },
    "codex": { "port": 43112 }
  }
}
```

`version` 是这个二进制的版本。`pid` 与 `acp-proxy/acp-proxy.pid` 相同。`clis` 的键是 TeamPilot 里该 ACP CLI 的 id。某种 CLI 没有端口，手机就不要对它走代理。

一条会话是两段：

- 面向手机的 ACP，跟着这次 SSH 转发。转发断了，只丢掉这一段，并 dispose 这段 JSON-RPC。
- 面向 CLI 的 ACP，用现在的 `Process.start` 拉起。标准输入输出一直由代理握着。路径、参数、环境来自手机这次已经准备好的结果。

手机第一次 `session/new`，代理才拉起对应的 CLI。端口决定 CLI 种类。`session/new` 的标准字段继续带工作目录和 MCP 服务器。可执行文件、参数、环境、权限策略放在 `_meta`，因为 ACP 的 `session/new` 没有这些字段。代理确认可执行文件属于该端口的 CLI，再用它们启动。对不上就拒绝这次 `session/new`，不拉起进程。

重连时手机照常 `initialize`，再 `session/load`：

- 子进程还在：接上它，补发磁盘缓冲和内存里的尾部。不对还活着的 CLI 再做一次 `session/load`。它只有这一个客户端。
- 子进程没了：用这次 `_meta` 和 `acp-session.json` 里的目录重新拉起，再对 CLI 做 `session/load` 或 `session/resume`。失败就把错误交回手机，不另开 `session/new`。

补发结束时如果这一轮还没停，连接保持打开，后续 `session/update` 继续推给手机。手机把这一轮视为仍在进行，不再发一次相同的 `session/prompt`。

同一条用户消息如果在这一轮已经交给 CLI、而这一轮还没结束，再次到来的相同 `session/prompt` 不另开一轮，而是接上正在跑的那一轮。这一轮已经结束后，相同文本是新的一轮。

## 谁可以连接

ACP 连接上没有客户端身份，代理不区分「手机」和「桌面」。它只保证一条会话同时只有一条连接。

同一条会话的新连接完成 `session/load` 时，旧的那条如果还没超时，代理把它关掉。会话和子进程不动。这是重连。代理不同时向两条连接推同一条会话。

`session/new` 建立另一条会话，和已有会话互不影响。

## 组成

实现分成三块，可以分开测：

- **代理进程：** 听端口、拉起 CLI、保活、缓冲、关闭和空闲回收。
- **安装：** CLI 页面的机器级卡片，以及云端从 GitHub Releases 下载并 `--detach`。发布版本、资产名和 SHA-256 由 App 钉住，方式与 `AntigravityAcpAdapterInstaller` 相同。
- **选路：** 开会话时按地址文件决定走 `forwardLocal` 还是现有的 SSH `exec`。

## 开会话时怎么选路

安装、更新、启动只在 CLI 页面做。开会话不上传，也不代为启动。

手机准备走 ACP 时先读 `acp-proxy.json`：

- 公布的 `version` 等于 App 钉住的代理版本，且 `pid` 对应的进程正在听该 CLI 的端口：用 SSH `forwardLocal` 接上去。
- 文件不在、版本不一致、pid 不是正在听的进程、或端口没人听：仍用现在的 SSH `exec`。这一轮不保活。界面可以提示去 CLI 页面安装或启动。发送本身不触发安装或启动。

版本不一致时不用旧代理，避免两边的 ACP 处理分叉。

## 安装

CLI 页面在当前工作面是远程机器时，增加一张机器级卡片，不放进某个 CLI 自己的卡片里。它看三件事：

- 二进制在不在。
- `acp-proxy.json` 的 `version` 是否旧于 App 钉住的发布版本。
- 端口是否由 `acp-proxy.pid` 里的进程在听。

对应的操作是安装、更新、启动。检测和进度沿用现有安装任务（下载、解压、定位）。

发布物是 GitHub Releases 上的 Linux 二进制，`x86_64` 和 `aarch64` 各一份，并公布 SHA-256。点安装后，云端在自己的终端里执行 `uname -m`，只接受这两种架构，`curl` 对应地址，校验 SHA-256，放进 `<teampilotRoot>/acp-proxy/teampilot-acp-proxy` 并加上可执行权限。临时文件换到正式路径，中途失败不留下半个新文件。然后执行：

```text
teampilot-acp-proxy --root <teampilotRoot> --detach
```

进程自己 `setsid`。拉起它的 SSH 命令退出后它还在。它写 `acp-proxy.json` 和 `acp-proxy.pid`，再听端口。

更新时只向 `acp-proxy.pid` 里的进程发停止，等它退出后换上新二进制再拉起。端口上不是这个 pid 的程序不动，安装失败。

其他架构直接失败，不反复下载。会话结束和空闲回收都不卸载它。要去掉时，停掉这个 pid，删掉 `acp-proxy/` 和 `acp-proxy.json`。

## 断线、关闭和内存

断线和关闭是两件事。

- 手机断线：丢掉面向手机的连接。子进程和正在跑的那一轮继续。每段连接在 socket 结束时 dispose。
- `session/cancel`：转给 CLI，只取消这一轮，会话还在。
- `session/close`：关掉上游会话。子进程不退出就先关 stdin，再结束进程。删掉这一条的缓冲目录。

输出先写入缓冲目录。内存里只留一段有上限的尾部，更早的从内存丢掉。补发时读磁盘，再加上还在跑的尾部。

CLI 进程才是大块内存，按这些规则释放：

- 断线且这一轮还在跑，或正在等手机回答权限：不因为断线杀掉。这一轮结束并且没有未完成的权限等待之后，若手机还没回来，开始空闲计时。
- 断线时没有在跑的轮次，也没有未完成的权限等待：立刻开始同一段空闲计时。
- 空闲时间默认 30 分钟，可用启动参数配置。时间到了，按 `session/close` 同样的方式收掉子进程和缓冲目录。
- 手机上的 `acp-transcript.jsonl` 和 `acp-session.json` 不动。下次走代理时，再按 `acp-session.json` 拉起并 load。
- 代理进程自己退出：对所有子进程做同样的关闭。没有会话时，它只剩监听端口。

## 手机不在时 CLI 的反向请求

权限策略和路径、环境一起放在 `session/new` 的 `_meta` 里，就是现在的 `LaunchSecurityPolicy`。

手机还连着时，这些请求原样转给手机，由现在的逻辑回答：

- `session/request_permission`
- Cursor 的 `cursor/ask_question`、`cursor/create_plan`
- 其余要客户端应答的请求

手机断线之后：

- **完全访问：** 代理使用与 `autoAllowAcpPermissionOptionId` 相同的规则回答 `session/request_permission`。能授权的选项就选上。
- **每次询问：** 不代答。请求一直开着，等手机回来选。等到现在的权限超时（24 小时）还没人答，就按取消回给 CLI。这段时间算这一轮还在跑，空闲回收不动它。
- **必须人来答的问题**（Cursor 的提问、建计划）：同样不代答，等手机或等到超时再取消。代理不编造答案。
- **只是通知**（待办、任务进度）：记进缓冲。不需要手机在线。

## 落盘

代理不写手机那份 `sessions/<id>/runtime/acp-transcript.jsonl` 和 `acp-session.json`。这两份仍由手机在连着的时候按现在的方式写。重连后的历史合并走现在的 `_mergeReplayedHistory`：已有的行保留，缺的内容补上。

云端 TeamPilot 根目录下：

| 路径 | 内容 |
| --- | --- |
| `acp-proxy.json` | 版本、绑定地址、pid、每种 CLI 的端口 |
| `acp-proxy/teampilot-acp-proxy` | 下载来的二进制 |
| `acp-proxy/acp-proxy.pid` | 代理自己的 pid |
| `acp-proxy/sessions/<agentSessionId>/` | CLI 的 session id、工作目录、启动路径、参数、环境，以及还没交给手机的输出 |

缓冲目录权限为仅所有者可读写。环境里可能有已经同步到云端的凭据，不写进日志。

`session/close` 和空闲回收删掉对应的缓冲目录。代理进程崩溃后，缓冲目录还在，子进程会因为 stdin 关闭而退出。用户在 CLI 页面把代理重新启动后，下一次 `session/load` 先用 CLI 自己恢复出来的历史，再补上缓冲里有、而 CLI 历史里没有的部分。

## 失败

失败时不留半套状态：

- `session/new` 时 CLI 起不来、握手失败、没登录，或可执行文件不属于该端口：把错误交回手机，表里不留这条会话，子进程收掉。
- 对 CLI 的 `session/load` / `session/resume` 失败：错误交回手机，不另开 `session/new`。
- 开会话时发现代理没在听：走 SSH `exec`。不在这条路径上启动代理，也不反复下载。
- 安装时端口被别的程序占用：不覆盖地址文件，安装失败。
- 架构不是 `x86_64` 或 `aarch64`：安装失败并说明原因。
- 代理进程崩溃：子进程一起退出。在 CLI 页面再次启动之前，新的 ACP 会话走 SSH `exec`。

## 测试

- 代理单测：手机连接断开后子进程仍在；对活着的 CLI 不发出第二次 `session/load`；补发来自缓冲；加载失败不调用 `session/new`；同一轮进行中的重复 `session/prompt` 不另开一轮；这一轮结束后相同文本会开新一轮。
- 代理单测：`session/close` 关掉子进程并删除缓冲；`session/cancel` 留下会话；空闲 30 分钟只在没有进行中的轮次和权限等待时触发；权限等待期间不回收。
- 代理单测：完全访问在断线时自动选择可授权选项；每次询问和 Cursor 提问在断线时挂起，超时后取消。
- 代理单测：同一会话的新连接替换旧连接；另一条会话不受影响。
- 安装单测：按 `uname -m` 选择资产并校验 SHA-256；只停止 pid 文件里的进程；端口被占用时失败且不改地址文件。
- 手机选路单测：版本一致且 pid 正在听则走 `forwardLocal`；缺文件、版本不同、或端口没人听则走现有 SSH `exec`，并且不调用安装或启动。
- CLI 页面：远程工作面显示这一张卡片的未安装、可更新、已安装未运行、运行中四种状态。本地工作面不显示。

## 已知限制

- 手机完全离线、而且请求还没交到代理时，这一轮无法在云端开始。
- 权限设为每次询问，或 CLI 提出必须人答的问题时，手机不在则这一轮停在该请求上，直到手机回来或满 24 小时取消。
- 代理进程崩溃时，正在跑的 CLI 会一起退出。已经写进 CLI 自己会话里的内容可以在代理重新启动后 load；没写进 CLI、只留在缓冲里的尾部，会在下次 `session/load` 时补上。
- 没安装或没启动代理时，行为与今天相同，断线会结束这一轮。
