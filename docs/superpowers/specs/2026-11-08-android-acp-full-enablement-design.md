# Android ACP Full Enablement And Unified Launch Policy

日期：2026-11-08

## 背景

当前 ACP 的可用性判断分裂在四条链路上，互相不一致：

| 链路 | 文件 | 现状 |
|---|---|---|
| Landing / 设置 | `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart`、`client/lib/pages/config/cli_readiness_card.dart` | Android 直接返回 `false`，不渲染 ACP 权限 chip / transport pill |
| 会话创建 | `client/lib/repositories/session_repository.dart`、`client/lib/services/chat/launch/session/session_provisional_builder.dart` | ACP-only CLI 通过 `launchesAcpOnly` 推断为 `true`，不检查平台 |
| 团队席位 | `client/lib/services/chat/launch/session/member_acp_stamp.dart` | Android 直接返回 `false`，ACP-only 也被挡掉 |
| 运行时 attach | `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | 不检查平台；Android 个人 ACP-only 实际能跑 |

结果是：Android 上 CodeBuddy / Gemini / Qoder 的个人会话可以跑 ACP，但 UI 不承认它是 ACP，也没有 Ask / Full access 权限选择；团队席位又被平台门禁挡掉。

另外，Antigravity 目前标记为 `AcpLocalOnlyCapability`，远程 CLI 安装和远程 adapter 安装都明确返回 not available，官方 OAuth 登录也在 Android 被排除。

本设计把 ACP 判定收敛成一个平台无关、目标感知的单一入口，并补齐 Android 的完整 ACP 能力：

1. 个人 + 团队/mixed 席位全部放开。
2. Android 不再按平台拦截 ACP。
3. 远程 team ACP 席位补齐 TeamBus MCP reverse tunnel。
4. Antigravity 支持远程 CLI、adapter 安装/定位/启动。
5. Antigravity 支持远程 OAuth 登录。

## 目标

- 所有 ACP 可用性判断只调用 `launch_acp_policy.dart` 的单一入口。
- Android 上，只要 CLI 有 `AcpCapability` 且目标有 exec 通道，ACP 就能启动。
- 双传输 CLI（Claude / Codex / Cursor / OpenCode）在 Android 上可以选择 ACP，并显示 transport pill 与权限 chip。
- Claude / Codex 的远程 adapter 在 Android 上可检测、安装、定位、启动。
- 远程 mixed-team ACP 席位能拿到 TeamBus MCP tunnel 配置。
- Antigravity 在 SSH/Termux 目标上可以安装 CLI + adapter、登录、启动 ACP。
- 旧测试里所有 “Android = false” 的断言更新为新的统一策略。

## 非目标

- WSL ACP：`RuntimeKind.wsl` 仍然没有 exec 通道，继续走 PTY。
- Windows 远程 Antigravity：远程 `uname` 只支持 POSIX；Windows 远程明确报错。
- CodeBuddy / Qoder 的远程 interactive login：它们的 auth store 依赖本地文件，本期不扩展到远程。
- ACP 席位进行中的 SSH 重连：现有缺口单独排期。
- iOS：当前没有 iOS 构建目标。

## 架构

### 1. 单一 ACP 判定

文件：`client/lib/services/chat/launch/session/launch_acp_policy.dart`

新增：

```dart
enum AcpAvailability {
  /// CLI 没有 ACP 能力，或 target 没有 exec 通道。
  unsupported,

  /// 双传输 CLI，用户偏好决定 ACP 或 PTY。
  optional,

  /// ACP-only CLI，支持 target 时必须走 ACP。
  forced,
}

AcpAvailability acpAvailabilityFor({
  required CliTool? cli,
  required String targetId,
});

bool resolveAcpOnTarget({
  required CliTool? cli,
  required String targetId,
  required bool requested,
});

bool canChooseAcpTransport({
  required CliTool? cli,
  required String targetId,
});
```

规则：

| 条件 | 结果 |
|---|---|
| `cli == null` | `unsupported` |
| registry 没有 `AcpCapability(cli)` | `unsupported` |
| `runtimeKindOfId(targetId)` 不是 `local`、`ssh`、`termux` | `unsupported` |
| `launchesAcpOnly(cli)` | `forced` |
| `CliTransportCapability.canChooseTransport(cli)` | `optional` |
| 其他 | `unsupported` |

`AcpNoPtyFallbackCapability` 不参与可用性判定；它只用于 `session_launch_service.supportsPtyTransport`，决定 ACP attach 失败后是否允许 PTY 回退。

`resolveAcpOnTarget`：

```dart
switch (acpAvailabilityFor(cli: cli, targetId: targetId)) {
  case AcpAvailability.unsupported:
    return false;
  case AcpAvailability.forced:
    return true;
  case AcpAvailability.optional:
    return requested;
}
```

`canChooseAcpTransport`：仅当 `acpAvailabilityFor == optional` 且 CLI 声明了 `{pty, acp}` 时为 true，供 target-aware 的 Landing 场景使用。设置页的 transport pill 是全局偏好，直接读 `CliTransportCapability.canChooseTransport`，不依赖 target。

### 2. 调用点统一

| 文件 | 改动 |
|---|---|
| `client/lib/repositories/session_repository.dart` | `resolvedAcp` 改为 `trimmedTeam.isEmpty && resolveAcpOnTarget(cli: cli, targetId: primaryTargetId, requested: acp)`；删除 `launchesAcpOnly` / `AcpLocalOnlyCapability` 分支 |
| `client/lib/services/chat/launch/session/session_provisional_builder.dart` | 用 `projectFolderTarget` / `home` 解析 target，再调用 `resolveAcpOnTarget`；删除本地推断 |
| `client/lib/services/chat/launch/session/member_acp_stamp.dart` | `resolveMemberBindingAcp` 改为 `resolveAcpOnTarget`；删除 `_isAndroid` / `isAndroidOverride` / local-only 判断 |
| `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart` | `willLaunchAcp` / `showLandingAcpPermissionChip` 改为 `resolveAcpOnTarget`；删除 `_isAndroid`；`targetId` 改为必传 |
| `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` | `buildWorkspaceConversationCreateRequest` 只传用户偏好 `acp`，不在这里做 target 判定；删除 `isAndroidOverride` 参数；由 repository 最终决定 |
| `client/lib/services/automation/automation_dispatcher.dart` | 同上：只传偏好，不调用 `resolveLaunchAcp` |
| `client/lib/services/chat/launch/pre_send/local_binary_requirements.dart` | 成员席位改用 `resolveAcpOnTarget`；删除 `isAndroidOverride` |
| `client/lib/services/remote/remote_cli_requirements.dart` | `remoteCliRequirementsForPlacement` 增加 `acpSeed`，按成员 target 调用 `resolveAcpOnTarget`，为 Team ACP 席位追加 adapter requirement |
| `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart` | 构造 `remoteCliRequirementsForPlacement` 时传入成员 ACP seed；seed 命名从 `localMemberAcpSeed` 改为 `memberAcpSeed` |
| `client/lib/models/app_session.dart` | 构造推断只调用 `acpForcedByCli(cli)`；生产路径显式传 `acp` |
| `client/lib/services/chat/session/session_create_request.dart` | `acp` 文档改为“用户偏好”；最终由 repository 结合 target 解析 |
| `client/lib/services/chat/launch/session_launch_service.dart` | `supportsPtyTransport` 改用 `AcpNoPtyFallbackCapability`；删除 local-only 语义 |

`resolveLaunchAcp` 在本次改动中直接删除；所有调用点改为 `resolveAcpOnTarget`，避免两个入口。

### 3. Capability 语义调整

文件：`client/lib/services/cli/registry/capabilities/acp_capability.dart`

- `AcpLocalOnlyCapability` 重命名为 `AcpNoPtyFallbackCapability`。
- 注释改为：ACP-only CLI 在 ACP attach 失败时没有 PTY 回退。
- `AntigravityAcpCapability` 继续实现该 marker，但不再表示“只能本地运行”。
- 所有原先用 `AcpLocalOnlyCapability` 阻止远程的地方删除；只保留 `session_launch_service.supportsPtyTransport` 的用途。

### 4. Android UI

文件：`client/lib/pages/config/cli_readiness_card.dart`

- 删除 `_isAndroid` getter 与 `isAndroidOverride` 参数。
- `initState` 不再跳过 `_refreshLatest` / `_refreshRemoteAdapter`；远程工作区只跑 `_refreshRemoteAdapter`，本地工作区只跑 `_refreshLatest`。
- transport pill 渲染条件改为 `_canChooseTransport`，不再排除 Android。
- ACP adapter 行的 `enabled` 改为 `true`（保留 `isRemote` 对 browse 的限制）。
- 删除 `client/lib/pages/config/cli_config_section.dart` 里的 `isAndroidOverride` 透传。
- `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` 继续用 `willLaunchAcp(... targetId: _homeTargetForLaunch().id)`；现在 Android 会返回真实结果；构造 `WorkspaceLandingLaunchGate` 的 `localMemberAcpSeed` 改名为 `memberAcpSeed`。
- ACP-only CLI 落在 unsupported target（例如 WSL）时，`WorkspaceLandingLaunchGate` 返回新的 `AcpUnsupportedTargetLaunchBlock`，显示“该目标不支持 ACP，且该 CLI 没有 PTY 回退”，而不是静默失败或错误地 spawn PTY。

### 5. 远程 Team ACP 的 TeamBus

文件：`client/lib/services/chat/launch/connect/acp_runtime_attach.dart`

在 `attachMemberAcpRuntime` 中复刻 PTY 路径 `session_shell_connector.dart::_bindMixedRemoteBus`：

1. 判断 `remote = usesSshTransport(launchTarget.kind)`、`mixedBus = team.teamMode == TeamMode.mixed && tab.teamBus != null && gateway.isSessionRegistered(session.sessionId)`。
2. `mixedBus && remote` 时：
   - 从 `tab.memberSshSessions[key]` 取 member SSH session，没有则 `SshMemberSession.open(factory, profile)` 并写回。
   - `workCtx = await _host.lifecycle.resolveWorkContextForTargetId(launchTarget.id)`。
   - `arch = archFromUname(await memberSession.run('uname -m'))`。
   - `binding = await _host.remoteBusSetup!.mountAndBindMixed(...)`，超时 45 秒，与 PTY 路径一致。
3. 把 `binding` 作为 `mixedRemoteBinding` 传给 `_productionExtraMcp` 与 `composeRuntimeExtraMcpServers`。
4. `teammate-bus` MCP 配置因此使用远端 tunnel 端口，而不是远端够不到的裸 loopback。
5. bind 失败或 `remoteBusSetup == null` 时抛 `StateError`，不允许静默启动一个没有 bus 的团队 ACP 席位。
6. `tab.closeMemberRemoteBusMount` 已有清理逻辑；不需要新增关闭路径。

`AcpRuntimeAttach._productionExtraMcp` 签名增加 `RemoteBusBinding? mixedRemoteBinding`，并在调用 `resolveMemberBusMcpTransportConfig` 时传入 `remoteBinding: mixedRemoteBinding`。

### 6. Antigravity 远程 CLI 安装

文件：`client/lib/services/cli/antigravity/capabilities/executable.dart`

`install` 增加 SSH 分支：

1. 校验 `context.sshProfile != null`。
2. `context.host.report(CliInstallPhase.installingCli, detail: 'Antigravity CLI')`。
3. `runSsh(profile, CliInstallerCommand.unixShellScript('curl -fsSL https://antigravity.google/cli/install.sh | bash'))`。
4. 失败时返回 `installerFailureMessage`。
5. `context.host.report(CliInstallPhase.locatingExecutable)`。
6. 用 `DefaultRemoteCliLocator('agy')` 定位；runner 复用 `context.host.runSsh(profile, CliInstallerCommand.unixShellScript(command))`，把 `CliInstallerCommandResult` 转成 `SshCommandResult`。
7. 返回 `executablePath`；定位失败时返回明确错误。

### 7. Antigravity 远程 adapter 安装

文件：`client/lib/services/cli/antigravity/capabilities/acp_adapter_installer.dart`

`install` 增加 SSH 分支：

1. 校验 `context.sshProfile != null`，否则失败。
2. 通过 `runSsh` 探测：
   - `uname -s` → `Linux` / `Darwin`
   - `uname -m` → `x86_64` / `amd64` / `aarch64` / `arm64`
3. 映射：
   - `Linux + x86_64/amd64` → `linux-x86_64`
   - `Linux + aarch64/arm64` → `linux-aarch64`
   - `Darwin + x86_64` → `darwin-x86_64`
   - `Darwin + arm64` → `darwin-aarch64`
   - 其他（含 Windows）→ 返回明确失败：远程 Antigravity adapter 仅支持 POSIX。
4. 远端安装目录：`$HOME/.local/share/teampilot/toolchain/antigravity-acp/<version>`。
5. 生成 POSIX shell 脚本并通过 `runSsh` 执行：
   - `mkdir -p` 安装目录；
   - `curl` 或 `wget` 下载 `antigravityAcpArchiveUrl(assetKey)`；
   - SHA-256 校验：优先 `sha256sum -c`，否则 `shasum -a 256 -c`；
   - 解压：优先 `unzip -oq`，否则 `python3 -m zipfile -e`；
   - `chmod +x` `agy_acp_server.par` 与 `localharness_external`；
   - 输出最终绝对路径。
6. 解析 stdout 最后一个非空行作为 `executablePath`。
7. 报告 `CliInstallPhase.downloading` / `extracting` / `locatingExecutable`。
8. 远程路径由现有 `RemoteCliReadinessService._installAdapter` 写入 `targets.json` 的 `acpAdapterPathOverrides`；`_locateAdapterWithRun` 优先使用 override。

`resolveInstalledPath` / `latestVersion` 保持本地语义；远程路径只走 override。

### 8. Antigravity launch 参数

文件：`client/lib/services/cli/antigravity/capabilities/acp.dart`

- 删除 `AcpLocalOnlyCapability`，改实现 `AcpNoPtyFallbackCapability`。
- `launchArgCandidates` 始终返回：
  ```dart
  [
    [executable, '--uid='],
    [executable],
  ]
  ```
  这样 Android → Linux 远端也会先尝试 `--uid=`；macOS/Windows 上第一个候选被拒时回退第二个。删除 `_usesUid` / `linuxUid` 的平台判断与构造参数。
- `agentExecutable` 保持 `.par` / `.exe` 的现有逻辑；Android 是 Unix，远端正向使用 `.par`。Windows 远程 Antigravity 在非目标内。

### 9. Antigravity 远程 OAuth 登录

#### 9.1 目标解析

- 从 `cli_readiness_card.dart` 抽出 `remoteSshProfileFromContext(context)`（`ConnectionModeService` + `SshProfileCubit` + `TermuxCubit`），供 readiness 与 login 共用。
- `SshClientFactory` 已经在 `client/lib/main.dart` 通过 `RepositoryProvider<SshClientFactory>.value(value: shell.sshClientFactory)` 暴露，登录对话框直接 `context.read<SshClientFactory>()`。
- `AntigravityProviderCapability.appliesTo` 对 official 模式返回 true（桌面和 Android 都显示登录按钮）。
- `AntigravityProviderCapability.buildLoginDialog`：
  - 能解析到远程 profile 且当前是 remote work plane：返回 `AntigravityRemoteLoginDialog`。
  - 否则返回现有本地 `AntigravityLoginDialog`。

#### 9.2 远程登录终端

新文件：`client/lib/services/cli/antigravity/provider/antigravity_remote_login_dialog.dart`

- 构造参数：`provider`、`executable`、`SshProfile`、`SshClientFactory`、`verifyModels` 回调。
- 启动：
  1. `SshMemberSession.open(factory, profile)`。
  2. 远端根目录：`$HOME/.local/share/teampilot/cli-login/antigravity/<providerId>`；`mkdir -p home workspace`。
  3. 定位远端 `agy`：`DefaultRemoteCliLocator('agy').locate(run)`；如果 `executable` 是绝对路径则直接用。
  4. `memberSession.openPty(command: ...)`，command 使用 POSIX shell 设置：
     - `HOME=<remote home>`
     - `GEMINI_HOME=<remote home>/.gemini`
     - `TERM=xterm-256color`
     - `COLORTERM=truecolor`
     - `cd <remote workspace>`
     - `exec <absolute agy>`
  5. 终端输出接到现有 `TerminalEngine`，输入/resize 接回 PTY。
- Done：
  1. 通过 `memberSession.runWithResult` 执行 `HOME=... GEMINI_HOME=... <agy> models`。
  2. exit 0 → 关闭并返回 true；否则显示验证失败。
- 关闭：关闭 PTY、关闭 `SshMemberSession`、取消订阅。
- 失败：显示 `antigravityCredentialsLoginFailed` 文案；保留取消路径。

#### 9.3 OAuth 回调验证

远端 OAuth 的主要风险是 `agy` 使用 `localhost` 回调时，手机浏览器无法访问远端 loopback。实现计划第一步是真实远端 spike：

1. 在远端 SSH PTY 运行 `agy`，记录登录方式：
   - device-code（打印 code + URL）→ 直接支持；
   - localhost redirect（打印 `http://127.0.0.1:<port>/...`）→ 在登录对话框里建立本地到远端该端口的反向/本地转发；
   - 其他 → 记录并在对话框里显示可操作错误。
2. `agy models` 验证通过后，再验证 ACP adapter `initialize` / `session/new` 能读到同一份认证。
3. 如果远端 keyring 不可用：
   - 优先使用 `GEMINI_HOME` 下的文件凭据；
   - 若 CLI 强制 keyring 且无法工作，保留 API key / ADC 作为可用路径，并在 spec 的 smoke 记录里标注 OAuth 的远端限制。

该 spike 的结论决定本节是否需要端口转发代码；不影响第 1–8 节的实现。

### 10. 文档

- `docs/ARCHITECTURE.md`：删除 “Android is still gated off”，改为统一策略说明；补充远程 Team ACP bus 与 Antigravity 远程安装。
- `docs/remote-acp-adapter-smoke.md`：增加 Android 端、Antigravity CLI/adapter、OAuth 的 checklist。
- `docs/cli-architecture.md`：注明 ACP 判定入口是 `launch_acp_policy.dart`，新增 CLI 时只声明能力，不写平台分支。
- 本 spec。

## 测试

### 单元测试

| 文件 | 覆盖 |
|---|---|
| `client/test/services/chat/launch/session/launch_acp_policy_test.dart`（新） | Android/local/SSH/Termux/WSL × 双传输/ACP-only/无 ACP；`requested` true/false；no-PTY marker 不再阻止远程 |
| `client/test/repositories/session_repository_acp_test.dart` | 个人 Claude requested true 持久化 true；requested false 持久化 false；Gemini/CodeBuddy/Qoder 仍强制 true；团队 session.acp false |
| `client/test/services/chat/launch/session/antigravity_acp_gate_test.dart` | Antigravity 在 local/SSH 都可 ACP；WSL false；Android 不再特殊 |
| `client/test/services/chat/launch/session/qoder_member_acp_stamp_test.dart` | Android 团队席位按 target 解析，不再一律 false |
| `client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart` | Android 上 Claude requested true → chip 显示；Gemini/CodeBuddy/Qoder → chip 显示；无 ACP CLI → 不显示 |
| `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` | Android 个人/团队放开的用例 |
| `client/test/pages/config/cli_config_section_test.dart` | Android 渲染 transport pill；adapter 行可操作 |
| `client/test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart` | ACP-only CLI 在 WSL/unsupported target 上被 `AcpUnsupportedTargetLaunchBlock` 拦住 |
| `client/test/services/chat/launch/acp_runtime_attach_test.dart` | 远程 mixed 席位绑定 `RemoteMemberBusSetup`，`teammate-bus` 配置使用 tunnel 端口；绑定失败抛错 |
| `client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart` | 远程 asset 映射、URL/SHA、脚本内容、路径解析、失败分支 |
| `client/test/services/cli/antigravity/antigravity_acp_capability_test.dart` | `--uid=` 候选始终先试、回退候选；远程环境 |
| `client/test/services/cli/antigravity/antigravity_provider_test.dart` | Android/remote `appliesTo` 为 true；本地仍为 true |
| `client/test/services/cli/antigravity/antigravity_remote_login_dialog_test.dart`（新） | fake SSH session + fake PTY：命令、HOME/GEMINI_HOME、Done 验证、dispose 清理 |

### 手动 smoke

1. Android → SSH Linux：
   - Claude/Codex：缺 adapter 时 readiness 面板出现；安装后 `targets.json` 有 override；首轮对话成功。
   - Cursor/OpenCode：直接 ACP 启动。
   - Gemini/CodeBuddy/Qoder：个人 + mixed 席位都能 ACP。
2. Android → SSH Linux，mixed team：
   - 远端成员拿到 teammate-bus tunnel 端口；
   - 用户指令能通过 TeamBus 送达。
3. Android → SSH Linux，Antigravity：
   - CLI 安装成功；
   - adapter 安装成功并写入 override；
   - 官方 OAuth 登录成功，`agy models` 通过；
   - ACP `session/new` 与首轮对话成功。
4. WSL：继续走 PTY，不显示 ACP 控件。
5. 桌面 local：原有 ACP/PTY 行为不回归。

### 收尾命令

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart
```

## 实施阶段

| 阶段 | 内容 | 依赖 |
|---|---|---|
| 1 | 统一 `launch_acp_policy` + 所有调用点 + Android UI 门禁移除 | 无 |
| 2 | 远程 team ACP 的 TeamBus binding | 阶段 1 |
| 3 | Antigravity 远程 CLI/adapter 安装 + launch 参数 | 阶段 1 |
| 4 | Antigravity 远程 OAuth 登录 + 回调 spike | 阶段 3 |
| 5 | 文档、smoke、全量测试 | 阶段 1–4 |

## 风险

| 风险 | 处理 |
|---|---|
| 远端 OAuth 使用 loopback 回调 | spike 后加端口转发；device-code 优先 |
| 远端无 keyring | 优先 `GEMINI_HOME` 文件凭据；否则保留 API key/ADC |
| 远端缺少 `curl` / `unzip` / `python3` | 安装脚本明确报错；文档记录依赖 |
| 远程 mixed bus 受 `AllowTcpForwarding` / `GatewayPorts` 限制 | 45 秒超时 + 明确错误；与 PTY 路径一致 |
| Android 上本地 discovery 不运行 | 只走 remote readiness；本地 binary gate 在远程工作区不参与 |
| Windows 远程 Antigravity | 明确返回“仅 POSIX 远端支持” |
| 旧测试大量断言 Android false | 阶段 1 集中更新，避免后续阶段反复改 |
