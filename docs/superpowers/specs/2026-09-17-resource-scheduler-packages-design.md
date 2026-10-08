# Resource scheduler packages

- 日期：2026-09-17
- 状态：已批准
- 来源：Session 工作面供给（ApplyPlan、CLI 缓存、投影器）和启动编排缠在 Flutter `client/lib` 里。SSH 路径另编 bash/tar。目标：抽出纯 Dart 包，Session 初始化对应用只暴露「传入资源 → 可开 PTY 的 spec」。

相关但不替代：

- [2026-09-16-work-plane-apply-design.md](./2026-09-16-work-plane-apply-design.md) — ApplyPlan / applier / 日后 `teampilot-apply`。本 spec 把那一层放进 `teampilot_apply`，不改协议。
- [2026-09-16-workspace-cli-cache-design.md](./2026-09-16-workspace-cli-cache-design.md) — `workspace/cache/cli/{tool}/{providerKey}/` 布局由 scheduler 拥有。

## Goal

把 Session **初始化生命周期**（供给 + CLI contribute + 投影 + apply + 编出启动命令）放进独立调度器包。应用只注入基本资源，用返回值开 PTY/SSH。

结束点是 **spawn-ready spec**（`executable` / `argv` / `env` / `cwd`），不是 tab/cubit，也不是进程已拉起。

工作面只认 `Filesystem`。调度器不分支 local vs SSH。

## Non-goals

- 这次不实现 `teampilot-apply` 二进制（另开 spec；它只依赖 `teampilot_apply` + `teampilot_fs`）。
- 不把 Cursor/Claude/… 实现搬进调度器。
- 不把 `AppSession` / `Workspace` / `TeamProfile` / Flutter 放进任何新包。
- 不把 `dartssh2`、PTY、`SessionLaunchPipeline`、ChatCubit 放进新包。
- 不把现有 SSH bash/tar 编译器搬进新包；删除它是应用侧后续步骤。
- 不自动回滚失败的 apply。
- 不把 CLI 安装（workspace provision / `cursor-agent` 二进制）放进调度器；可执行文件路径由应用写入 DTO。

## Packages

三个包位于 `client/packages/`，纯 Dart，`publish_to: none`，SDK `^3.8.1`。依赖只允许向下：

```
teampilot_fs
     ↑
teampilot_apply
     ↑
teampilot_scheduler
     ↑
teampilot (Flutter client)
```

禁止反向依赖。SFTP、WSL 等 `Filesystem` 实现留在 client（或以后的适配包），不进 `teampilot_fs` 的第一刀。

### `teampilot_fs`

| 放入 | 不放入 |
|---|---|
| `Filesystem`、`FsStat`、`FsWatcher`、`FilesystemLstat` | TeamPilot 路径布局 |
| `LocalFilesystem` | SFTP / WSL 后端 |
| `InMemoryFilesystem`（现 `client/test/support`，升为包内一等后端，供本包和上游测试） | ApplyPlan、Session |

### `teampilot_apply`

依赖：`teampilot_fs`。

| 放入 | 不放入 |
|---|---|
| `ApplyPlan` / `ApplyOp`、JSON、路径沙箱 | `LaunchManifest` |
| `BlobStore` | `WorkPathProjector` |
| `WorkPlaneApplier` | Session DTO、CLI 插件、`ShellLaunchSpec` |

`teampilot-apply` CLI 将来只链这一层：已有 plan + blob + `workFs`。不调用 `scheduler.init`。

### `teampilot_scheduler`

依赖：`teampilot_fs`、`teampilot_apply`。

| 放入 | 不放入 |
|---|---|
| `SessionInitRequest` / `SessionInitResult` | `AppSession`、`TeamProfile` |
| home/work 路径布局（现 `RuntimeLayout` / CLI cache 约定） | Cursor fake HOME 等 CLI 实现 |
| `LaunchManifest` | SSH 编译器、`WorkPlaneScriptRunner` |
| `WorkPathProjector` | PTY / SSH transport |
| `SessionScheduler.init` 编排 | `CliLaunchContext`、`ProcessRunner` |
| `SessionCliPlugin`、`ResourceContributor` 接口 | |

应用把现有 `CliSessionCapability` / `ResourceProviderSet` **适配**成上述接口；相位机（persist / initialize / finalize / tab gate）仍留在应用。

## Call API

```dart
final result = await scheduler.init(
  request: SessionInitRequest(...),
  homeFs: homeFilesystem,
  workFs: workFilesystem,
  plugin: cliPlugin,
  resources: resourceContributors, // skill / mcp / hook
);
```

### `SessionInitRequest`（扁平 DTO）

必填：`workspaceId`、`sessionId`、`memberId`、`cli`（tool id 字符串）、`providerId`、`identityId`、`cliExecutablePath`、`homeRoot`、`workRoot`。

按需：`workingDirectory`、`additionalDirectories`、resume / create native session id、`cliTeamName`、安全策略枚举、要启用的 skill / plugin / mcp id 列表。

不传：`AppSession`、`Workspace`、`TeamProfile`、`RuntimeTarget`。应用在调用前完成 workspace provision，把 CLI 二进制路径写入 `cliExecutablePath`。

`homeFs` 的根是控制面 TeamPilot 数据根（身份、cli-defaults、catalog）。`workFs` 的根是工作面 TeamPilot 数据根。两块盘可以是同一 `LocalFilesystem`（同机）或不同后端（本机 home + SFTP work）。调度器不读 `RuntimeTarget`。

### `SessionSpawnSpec` 与 `SessionInitResult`

插件 `buildSpawn` 返回 `SessionSpawnSpec`：`executable`、`argv`、`env`、`cwd`。

`SessionInitResult` = 该 spawn spec + `warnings` + 可空的 `nativeSessionIdToPersist`（应用写回会话 JSON）。

应用 **不再**用 `CliLaunchContext` 在终端边界拼命令。迁移期应用适配层可以把 `SessionInitResult` 填回旧 `ShellLaunchSpec`，直到终端代码直接吃 result。

## Data flow

包内固定顺序：

1. 按布局解析 home/work 路径（cli-defaults、identities-runtime、workspace `config/{tool}`、`cache/cli/{tool}/{provider}`、session runtime）。
2. Session bootstrap 一次（凭证 ln、workspace trust）——写 `LaunchManifest`，不是直接 mkdir 特例。
3. `ResourceContributor` 与 `SessionCliPlugin.contribute` 往同一 `LaunchManifest` 追加条目。
4. `WorkPathProjector`：manifest + `homeFs` + `workFs` → `ApplyPlan` + blob（provided-link / 计划内 ln / first-fill 悬空 ln / 源缺失且不可投影则失败）。规则与现投影器一致，不在调度器加 GNU mkdir 补丁。
5. `WorkPlaneApplier.apply` 打在 `workFs` 上。
6. `plugin.afterApply`（只拿 `workFs`、layout、env）。需要 `npm` 等进程时，由 **应用侧插件适配器**自己跑，不把 `ProcessRunner` 放进 `scheduler.init`。
7. `plugin.buildSpawn` → `SessionSpawnSpec`，调度器加上 warnings / persist id 成为 `SessionInitResult`。

`teampilot-apply` 只执行第 5 步的引擎，输入是已序列化的 ApplyPlan + blob，不是 `SessionInitRequest`。

## Plugin contracts

```dart
abstract interface class SessionCliPlugin {
  String get toolId;

  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required Filesystem workFs,
    required LaunchManifest manifest,
  });

  String sessionConfigDir(SessionLayout layout, SessionInitRequest request);

  Future<void> afterApply({
    required Filesystem workFs,
    required SessionLayout layout,
    required Map<String, String> environment,
  });

  SessionSpawnSpec buildSpawn({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Map<String, String> environment,
  });
}

abstract interface class ResourceContributor {
  String get id;
  Future<void> contribute({
    required SessionInitRequest request,
    required SessionLayout layout,
    required Filesystem homeFs,
    required LaunchManifest manifest,
  });
}
```

不把现有 `CliSessionCapability`（`ensurePersisted` / `initialize` / `finalize` / `gateConnect` / `afterManifestFlush`）原样搬进包。`gateConnect` 等 tab 生命周期仍在应用；若初始化前就必须拒绝，应用不要调用 `init`。

`afterApply` 禁止 `WorkPlaneScriptRunner`。调度器不注入进程 API；CLI 适配器若要跑命令，在应用里做。

## Errors

- 阶段：`layout` → `contribute` → `project` → `apply` → `afterApply` → `spawn`。
- 失败抛 `SessionInitException(stage, path?, cause)`。**不自动回滚**。
- 路径逃出 `workRoot`、不可投影且 `sourceFs` 无内容：失败，不在调度器里对 dangling `mkdir` 做特例。
- 应用将异常映射到现有 launch 错误 UI。成功路径上的非致命问题进 `warnings`。
- `teampilot_apply` 只保留协议版本 / `workRoot` 不匹配 / 路径沙箱错误；没有 Session 异常类型。

## Client leftovers

仍留在 Flutter 应用：

- `SessionLaunchPipeline`、cubit、tab、会话 JSON 持久化。
- `AppSession` → `SessionInitRequest` 适配器。
- CLI 与 Resource 的插件适配器。
- PTY / SSH 开进程（输入是 `SessionInitResult`）。
- SFTP / WSL `Filesystem`、workspace provision（装 CLI 二进制）。
- 在 work `Filesystem` 上直接 apply 可用之前：现有 SSH bash/tar 编译器作为 **应用内临时适配**，调用点在 client 的 flush，不进三个新包。

client 已有 SFTP `Filesystem`。目标态是第 5 步直接打在这块盘上，然后删除编译器。

## Testing

| 包 | 怎么测 |
|---|---|
| `teampilot_fs` | 包内 `dart test`；迁 `LocalFilesystem` / in-memory 测试 |
| `teampilot_apply` | 包内 `dart test`；迁 ApplyPlan 沙箱、blob、applier |
| `teampilot_scheduler` | 包内 `dart test`；两块 `InMemoryFilesystem` + fake plugin / contributor。覆盖 provided-link、计划内 ln、first-fill 悬空 ln、不可投影且源缺失失败。不测 Cursor 真供给 |
| client | `cd client && dart run tool/run_tests.dart`；DTO 适配 + 现有 Cursor/Claude 测试。禁止在 `client/` 直接 `flutter test` |

## Migration

四步，每步可单独合入、测试保持绿：

1. **抽 `teampilot_fs`**：移动接口与本地/内存实现；client 改 import。行为不变。
2. **抽 `teampilot_apply`**：移动 ApplyPlan / blob / applier；client 改依赖。行为不变。
3. **建 `teampilot_scheduler`**：迁布局、manifest、投影器；实现 `init`。`SessionConnectOrchestrator` 改为调 `scheduler.init`；CLI 经适配器接入。返回 spawn-ready result；应用终端层可暂把 result 填回旧 `ShellLaunchSpec`。
4. **远程 apply**：client 用 SFTP `Filesystem` 跑 `WorkPlaneApplier`，删除 bash/tar 编译器。可晚于 3，且不把编译器带进新包。

实现计划按包拆成独立 plan 也可以，但依赖顺序必须是 1 → 2 → 3 → 4。

## Current mapping

| 现位置 | 去向 |
|---|---|
| `client/lib/services/io/filesystem.dart`、`local_filesystem.dart` | `teampilot_fs` |
| `client/test/support/in_memory_filesystem.dart` | `teampilot_fs` |
| `apply_plan.dart`、`blob_store.dart`、`work_plane_applier.dart` | `teampilot_apply` |
| `launch_manifest.dart`、`work_path_projector.dart`、`runtime_layout.dart`、`workspace_cli_cache.dart` | `teampilot_scheduler`（client 改依赖该包，不再维护第二份路径算法） |
| `session_connect_orchestrator.dart` / `session_lifecycle_service.dart` 中的 connect 供给 | 逻辑进 `SessionScheduler.init`；应用只留适配 |
| `apply_plan_ssh_compiler.dart` | 留 client，直到步骤 4 删除 |
| `services/cli/**` | 留 client，适配 `SessionCliPlugin` |

## Decisions (locked)

1. 第一消费者方向包含 `teampilot-apply`，但 Session 初始化走 scheduler；helper 只链 apply。
2. 包做到 spawn-ready spec；应用只开 PTY/SSH。
3. 工作面只注入 `Filesystem`。
4. CLI 实现当插件注入。
5. 入口是小 DTO + `homeFs` + `workFs`。
6. 三包立刻切开，不做成一个胖 `teampilot_runtime`。
