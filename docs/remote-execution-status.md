# 远程执行架构 — 落地状态（Remote Execution Status）

> 本文记录 `docs/remote-execution-architecture.md`（§12 分期）的实现进度，作为权威设计文档的「进度旁注」。命名以代码现实为准（`Workspace` / `WorkspaceFolder` / `RuntimeTarget`）。

最后更新：2026-06-24 · 分支 `feat/p3c-remote-preflight`

---

## 1. 分期状态总览

| 期 | 设计 §12 | 状态 | 说明 |
|---|---|---|---|
| 预备 | folders 值对象 | ✅ 已交付 | `Workspace.folders: List<WorkspaceFolder>` |
| P0 | 四旋钮 → `RuntimeTarget` + targets 注册表 | ✅ 已交付 | `targets.json` + `RuntimeTargetRegistry` |
| P1 | home target 归一 | ✅ 已交付 | `HomeTargetController` + `RuntimeTargetPicker` |
| P2 | 去单例 + 控制面/工作面拆分 | ✅ 已交付 | `RuntimeContextRegistry` + 工作区 target UI |
| P3a/P3b | 成员远程：folderAssignments + 反向隧道 + 修 Android mixed | ✅ 已交付 | `services/team_bus/remote/*` |
| P3c | 远程 preflight + CLI 定位泛化 + 工作机物化 | ✅ 已交付 | `services/remote/*` |
| **P3c+（本轮）** | 远程目录选择 UX（§11 末条） | ✅ 已交付 | 见 §2 Phase B |
| **P3d** | 跨机产物传输（§4.2） | ✅ 已交付 | publish/fetch/list_artifacts + 会话 inbox，见 §2 Phase C |
| **P3e** | Windows 远程（§3 / §5.2 / §7.1） | 🟡 部分交付（D.1+D.3） | remoteOs 探测 + windows relay 选择已交付；D.2/D.4 + connect 接线见 §3 |
| **P4** | 连接弹性（§11 首条） | ⏳ 规划就绪，未实现 | 见 §4 Phase E 实现计划 |

---

## 2. 本轮已完成（A / B / C）

### Phase A — P3c 验收清扫
- 基线 gate 全绿（`flutter analyze --no-fatal-infos --no-fatal-warnings` 退出 0；`flutter test --exclude-tags integration` 全部通过）。
- 边界守卫复核：`services/remote` 无 P3d/P4 泄漏；`RemoteOs` 为已序列化的占位字段（未半接线探测），符合 P3c 延期状态。
- 清理 P1+P2 去单例重构遗留的 29 处无用/冗余 import。
- 提交：`chore: P3c 验收清扫 — 清理去单例重构遗留的无用 import`。

### Phase B — 远程工作区目录 UX（§11「远程目录选择 UX」）
解除桌面「项目远程」最后一块 UI 阻塞：本地 `FilePicker` 无法选远程目录。

- **新增** `services/storage/remote_directory_browser.dart`：纯、fs 注入的目录导航器（`resolveInitial` / `list` / `child`），POSIX 路径全部走 `Filesystem.pathContext`，`~`/`.` 经 `resolveSymlink('.')`（SFTP=远程 home）解析。
- **新增** `services/storage/workspace_directory_picker.dart`：UI→target 解析外观（`isRemote` / `targetById` 本地兜底 / `filesystemFor`），经 `RepositoryProvider` 提供。
- **新增** `widgets/remote_directory_browser_dialog.dart`：SFTP 远程目录浏览弹窗（当前路径 + 上一级 + 子目录列表 + 「使用此目录」+ 手填回退 + loading/error）。
- **重构** `utils/workspace_path_picker.dart`：新签名 `pickWorkspaceDirectoryPath(context, {required targetId})`，**删除 `Platform.isAndroid` 分支**，按 `runtimeKindOfId` 路由（ssh→远程浏览器，local/wsl→FilePicker）。Android 的 home target 是 `ssh:*`，因此天然走远程浏览器——这就是 API 的统一。
- **可编辑主目录**：`workspace_details_dialog.dart` 主目录加铅笔编辑，保存经 `SessionRepository.updateWorkspaceFolders` **保留每个 folder 的 targetId**（不再被 `updateWorkspacePaths` 清成 local）。
- 测试：`remote_directory_browser_test.dart` / `workspace_directory_picker_test.dart`（fake Filesystem）。
- l10n en+zh + `gen_warmup_glyphs`。
- gate：`flutter test --exclude-tags integration --concurrency=1` → **+1917 All tests passed**（已独立复跑确认）。
- 提交：`feat: 远程执行架构 P3c+ — 远程工作区目录浏览器 + 统一目录选择 + 可编辑主目录`。

> 注：本机默认并发跑测试存在 isolate 加载偶发 flake（与改动无关）；统一用 `--concurrency=1` 取干净绿作为 gate 证据。

### Phase C — P3d 跨机产物传输（§4.2）
成员不共享文件系统：bus 只存「句柄」，由唯一能同时触达两台机器的本地 App 在 fetch 时搬字节（§4.2）。

- **新增** `services/team_bus/artifacts/artifact_handle.dart`：`ArtifactKind`（v1 仅 `file`，`dir`/tar 明确延期）+ `ArtifactHandle`（name / publisher / targetId / 绝对路径 / 大小 / publishedAtMs）。bus 永不存字节。
- **新增** `artifact_registry.dart`：会话级内存登记表，按 name 索引；冲突默认拒绝（除非 `overwrite`）；`evictExpired(now)` 按 `ttl`（默认 6h）驱逐久未取用句柄；`clear()` 随会话/挂载拆除清空 = 会话 inbox 生命周期。
- **新增** `artifact_exceptions.dart`：全部失败语义化为 `ArtifactException` 子类（未知/过期、name 冲突、不支持的 kind、源非普通文件、超限、目标已存在、目标逃逸 inbox、源不可读），MCP 层 catch 后回成员清晰错误文案。
- **新增** `artifact_transfer_service.dart`：注入式（`resolveFs(targetId)` / `targetForMember` / `inboxDirFor` / `maxBytes` / 时钟），`publish`（校验是普通文件 + 报得出大小时早限，绝不搬字节）、`list`（先驱逐过期）、`fetch`（取句柄 → 解析 fetcher target fs → **路径逃逸守卫**：dest 经 `pathContext` 归一后必须落在该成员 inbox 内 → 目标存在守卫 → 从 publisher fs 读字节、再限大小、写入 fetcher fs）。默认上限 256 MiB（整体缓冲，限峰值内存；流式为后续增量）。
- **接线** `mcp/teammate_bus_mcp_handler.dart`：新增可注入 `ArtifactTransferService?`，**仅在注入时**才在 `tools/list` 暴露并可分发 `publish_artifact` / `list_artifacts` / `fetch_artifact`（与 task 工具同样的能力门控）。
- **会话级接线** `cubits/chat_cubit.dart` → `cubits/chat/tab_team_bus_coordinator.dart`：`installBusForTab` 构造 handler 时按会话注入 `_buildArtifactService(session)`——`resolveFs` 复用 `SessionLifecycleService.resolveWorkContextForTargetId`（新增公有 seam），`targetForMember` 复用 `memberWorkTarget(...).id`，inbox = 成员工作目录 + `/.teampilot-inbox`。每会话一张 registry（会话级 inbox）。
- 测试（fake filesystem，`InMemoryFilesystem`）：`artifact_registry_test.dart`（4）、`artifact_transfer_service_test.dart`（6：happy path / 未知 / 超限 / 目标存在±overwrite / inbox 逃逸 / 非文件源）、`teammate_bus_artifact_tools_test.dart`（5：工具门控 / publish→list→fetch 往返 / 未知 fetch 报错 / 缺参报错 / 不支持 kind 报错）。
- gate：`flutter analyze` team_bus 0 error（仅一处与本改动无关的既有 `disconnectAtSec` 告警）；`flutter test --concurrency=1 test/services/team_bus/artifacts/` → **+15 All tests passed**。
- 提交：`feat: 远程执行架构 P3d — 跨机产物传输 MCP + 会话 inbox`。

---

## 3. Phase D（P3e Windows 远程）实现计划 — 规划就绪

设计依据：§3（`remoteOs` 探测）、§5.2（symlink→copy 继承退化）、§7.1（windows 静态 relay）。**远程仍仅 local/wsl/ssh 三 kind，不引入新后端。**

> 本轮交付 **D.1（探测逻辑）+ D.3（windows relay 选择/物化 + 可注入资产解析器）**，均带单测。**D.2（symlink→copy）/ D.4（登录 shell/路径）/ D.1 connect 接线** 仍按下方计划留待后续——避免半接线侵入式改动。提交：`feat: 远程执行架构 P3e（部分） — remoteOs 探测 + 跨平台 relay 选择`。

### D.1 connect 时探测 `remoteOs` — ✅ 探测逻辑已交付
- **新增** `services/remote/remote_os_prober.dart`：注入 `RemoteCommandRunner`，按序 `uname -s`（非空→posix）→ `echo %OS%`（含 `windows`→windows）→ `ver`（含 `windows`→windows）→ 兜底 posix。只读探测、无副作用。
- 测试 `remote_os_prober_test.dart`：Linux/Darwin uname→posix（uname 命中即不再多探）、`%OS%`=Windows_NT→windows、`ver` banner→windows、全静默→posix 兜底。
- **未接线（留待）**：在 ssh target 物化点调用 prober 并写回 `RuntimeTarget.remoteOs` 缓存（`runtime_context_resolver.dart` ssh 分支 / `ssh_client_factory.dart` 连接后）。模型字段与 prober 都就绪，缺的是 connect 序里调用 + 持久化这一步。

### D.2 symlink → copy 继承退化（§5.2）
- 位置：`services/remote/work_machine_materializer.dart` + `RuntimeLayout._ensureInheritedChild`（现成 copyTree 兜底）。
- 改动：物化继承 ancestry 时，若 `target.remoteOs == windows` → 走 copy 而非 symlink。能力位/参数传入，不散落 `if`。
- 测试：windows target 下 `_ensureInheritedChild` 走 copyTree；posix 下仍 symlink（fake fs 断言调用路径）。

### D.3 windows 静态 relay（§7.1）— ✅ 已交付
- **重构** `services/team_bus/remote/relay_provisioner.dart`：
  - `provision(... , RemoteOs remoteOs = posix)`：**posix** = socat → nc → bundled(posix arch) → 抛错；**windows** = 直接 bundled(windows arch)（Windows OpenSSH 几乎无 socat/nc，且无 `sh -c` 握手包装，静态 relay 自带 `--token/--member` 握手是唯一路径，故不再探 socat/nc）。
  - 新增可注入 `RelayAssetResolver`（`Future<List<int>?> Function(assetName)`，构造器可选、保持 `const`）：bundled relay 的二进制字节由它提供；**默认解析器恒返回 null → 抛 `RelayAssetMissingException`（清晰报错，绝不落地坏文件）** —— 即「二进制缺失时明确报错」。
  - 支持矩阵：posix `{linux-x64, linux-arm64}`、windows `{windows-x64, windows-arm64}`（`.exe` 后缀）；不支持的 arch → `RelayUnavailableException`。
  - 物化：写字节 → posix 经命令 runner `chmod +x`（`Filesystem` 无 chmod 原语）；windows 不 chmod。
- **接线** `remote_bus_mount.dart`：新增 `remoteOs`（默认 posix）并透传给 `provision`。
- **外部依赖（阻塞点，仍在）**：真正的预编译静态 relay 二进制（windows-x64/linux/macos）需另行编译并作为 app asset 由实际 `RelayAssetResolver` 提供；本轮只产出选择/物化/握手逻辑 + 注入式资产解析器，二进制未产出（缺失即清晰报错）。
- 测试 `relay_provisioner_test.dart`：posix socat/nc 优先、posix bundled（注入字节 + chmod + 写盘校验）、posix 支持 arch 但无资产→asset-missing、posix 不支持 arch→unavailable、windows `.exe`（零 socat/nc 探测、零 chmod）、windows 无资产→asset-missing、windows 不支持 arch→unavailable。

### D.4 登录 shell / 路径语义（§5.3）
- 位置：`services/session/launch_command_builder.dart`（远程命令拼装）。
- 改动：windows 远程的路径分隔符、引用、登录 shell（`cmd`/`powershell` vs `sh -lc`）分支；远程 app-data root 与工作目录按 windows 语义解析。
- 测试：windows 远程的 launch argv / 路径拼装快照。

### D.5 验收
- 单测覆盖以上分支；POSIX 远程回归不变；Windows 远程各通一条逻辑路径（受 D.3 二进制资产限制，端到端真机验证需补 relay 二进制）。

---

## 4. Phase E（P4 连接弹性）实现计划 — 规划就绪

设计依据：§11 首条、§12 P4。目标：某远程 target 掉线只降级该机会话/成员，其余团队继续；自动重连 + 会话恢复 + per-target 状态 UI。

### E.1 per-target 连接登记 + 心跳/超时
- 位置：扩展 `services/storage/runtime_context_registry.dart`（已持有 per-target `SSHClient`）+ `services/ssh/ssh_client_factory.dart`。
- 改动：每个 ssh target 一个连接「监督者」——心跳（周期 keepalive / `SSHClient` ping）、超时判定、状态枚举（`connected` / `degraded` / `reconnecting` / `down`）。状态对外用流暴露（cubit 可订阅）。

### E.2 掉线隔离
- 改动：连接事件只影响该 target 的 `RuntimeContext` 与挂在其上的会话/成员；控制面（home）与其它 target 不受影响。`RuntimeContextRegistry.dispose/forTarget` 配合状态机做隔离回收。

### E.3 自动重连 + 重建反向隧道 + 重注 MCP 端口 + 重发门铃
- 位置：`services/team_bus/remote/remote_bus_mount.dart`（隧道/relay）+ `reverse_tunnel.dart`。
- 改动：重连成功后重建 `ReverseTunnel`（新端口 `<P>`）、重写该成员 MCP 配置指向新端口、重发门铃（stdin 注入 + `read_messages`）。隧道/pump 生命周期与重连协同。

### E.4 会话自动 resume
- 位置：`services/session/session_lifecycle_service.dart` + chat cubit 启动序。
- 改动：掉线会话在重连后按 `AppSession.folderAssignments` + 各成员 target 的 fs 重新定位工作目录与 `--resume`/`--session-id`，自动恢复。不做跨 target 迁移（§11：换机即重新分配）。

### E.5 per-target 连接状态 UI
- 位置：工作区/成员视图（`pages/home_workspace/workspace/*`）+ 复用 `MemberPresenceCubit` 模式新增连接状态展示。
- 改动：每 target 显示 connected/degraded/reconnecting/down，掉线时明确提示「仅该机成员降级」。l10n en+zh。

### E.6 验收
- 用 fake/mock SSH 连接模拟 disconnect/reconnect：断一台远程机→仅其成员降级、自动重连后会话恢复、其余团队不受影响。
- 单测覆盖状态机（心跳超时→down→reconnecting→connected）与隧道重建路径。

---

## 5. 已知阻塞 / 依赖

- **Windows 静态 relay 二进制（D.3）**：需为 windows-x64（及 linux/macos）预编译静态 relay 并入 `assets/`；本轮只产出选择/物化/握手逻辑与测试，二进制资产需另行提供。
- **真机/跨机端到端验证**：D/E 的真实 SSH（尤其 Windows OpenSSH）端到端需要实机环境；本仓测试以 fake fs / mock 连接覆盖分支逻辑，真机金路径需手测记录。
- **本机测试并发 flake**：`flutter test` 默认并发在本机偶发 isolate 加载错误，统一用 `--concurrency=1` 取 gate 证据。
