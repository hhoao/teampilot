# app_shell.dart 装配层渐进拆分设计

- 日期：2026-11-12
- 状态：待审阅
- 来源：用户指出 `client/lib/app/app_shell.dart` 已超过 5000 行，要求拆分；选择“渐进解耦”方案（方案 1），以多个小 PR 逐步推进、行为零变化。

## 背景

`client/lib/app/app_shell.dart` 当前 5099 行，实际构成：

| 区段 | 行数 | 内容 |
|---|---|---|
| 1–402 | ~400 | import 与零散工具 |
| 402–504 | ~100 | `ManagedProviderControlPlane`、`...Lease`、`buildDefaultManagedProviderUsageRegistry` |
| 505–786 | ~280 | `AppShell` 类：约 120 个注入字段 + 构造器 |
| 787–4629 | ~3840 | 顶层函数 `buildAppShell()`：全局 DI/装配根 |
| 4630–4722 | ~90 | `_DefaultProviderUsageHttpClient`、`_CursorUsageStack`、`_warmCursorUsage` |
| 4723–5099 | ~380 | `TeamPilotBootstrap` widget + 启动重试状态机 |

`buildAppShell()` 是问题核心：约 56 个顺序创建的局部依赖、十来个互相捕获的闭包、一个覆盖后半段的 `try/catch` teardown。它承担了整个应用的装配职责，任何子系统改动都要在 3000 多行里定位。

`docs/CODE_QUALITY.md` 要求 `services/` ≤ 600 行、单函数超过 ~30 行且含分支/IO 时应下沉。`buildAppShell` 远超该标准，且拆分不改变分层：它仍然是 composition root，只是把每个子系统的装配片段移出主文件。

## 目标

1. `app_shell.dart` 降到约 1200~1400 行，只保留 `AppShell` 类、imports、`buildAppShell` 编排器、teardown。
2. 子系统装配逻辑移入 `lib/app/bootstrap/*.dart`，一文件一子系统，单文件 ≤ 300 行、单函数 ≤ 200 行。
3. 行为零变化：不改变初始化顺序、teardown 语义、闭包身份与注册次数。
4. 每个阶段独立可回滚、可验证；不要求一次性完成。

## 非目标

- 不引入 `BootstrapContext` / 每子系统 Bootstrapper 类的彻底对象化重构（方案 3）。
- 不重排启动顺序，不改 home 切换、事件传输、vault 平面、remote boot 的任何语义。
- 不修改 `AppShell` 的字段与构造器契约（除非拆分后确实需要新增一个小型 controller 字段）。
- 不新增功能、不改 UI、不补与拆分无关的测试。

## 约束与关键事实

1. **`late final` 只能以 getter 传入。** `chatCubit`（2928 行）、`homeTargetController`（4411 行）等在装配中段/末段才赋值；抽出的函数若在构造时按值接收，会提前触发 late 初始化并抛错。签名使用 `ChatCubit Function() chatCubit`。
2. **可变捕获状态不能复制。** `var homeTarget`、`termuxConfigCache`、`remoteBootCompleted` / `remoteIndexBootstrapped` / `deferredHomePlaneLoadsDone` / `remoteShowOnboarding` 必须由 controller 或原闭包持有；拆出函数若按值接收会产生多份状态。
3. **teardown 依赖留在编排器作用域。** catch 块使用 `catalogRuntime`、`homeConnectionCubit`、`managedProviderControlPlaneLease`、`memberPresenceCubit`、`homeProfileWatchSub`、`homeConnectivitySub`、`eventTransportController` 及 5 个其它 subscription，这些声明不能搬出 `buildAppShell`。
4. **顺序敏感步骤只搬连续块、不重排**：SSH 旧目录迁移先于 `SshProfileCubit.load()`；managed provider 图后于 home 上下文；team-generation 图后于 chat/workbench cubit。
5. **注册闭包保持同一函数对象**：command bus、catalog registry 注册的是函数引用，搬移后只在原位置调用一次，禁止两边重复注册。
6. **源码 pin 测试必须先改扫描范围**：`test/app/agent_presence_wiring_test.dart`、`test/app/app_shell_bootstrap_retry_test.dart`、`test/integration/home_unreachable_boot_test.dart` 直接读取 `lib/app/app_shell.dart` 文本做断言；任何搬移都会使它们失败。新增 `test/support/app_shell_source.dart` 读取 `lib/app/**` 全部源码拼接，pin 测试改用该 helper。
7. **避免循环依赖**：`lib/app/bootstrap/*` 不引用 `AppShell` 类型；需要 shell 能力时接收回调或窄接口。

## 拆分模式

抽出的装配函数统一形如：

```dart
typedef SessionUsageWiring = ({
  SessionUsageCubit cubit,
  Future<void> Function() warmStartupCaches,
});

SessionUsageWiring wireSessionUsage({
  required HomeStorage storage,
  required CursorUsageApiClient cursorApi,
  required CliToolRegistry registry,
  required SessionRepository sessions,
  LaunchProfileRepository Function() teams,
}) { ... }
```

- 具名参数、显式返回值 record；
- 已构造好的依赖按值传，late/可变依赖按 getter 或 controller 传；
- 装配函数只做构造与连接，不包含启动流程控制；
- 跨子系统共享的启动闭包在阶段 2 升级为 controller 类。

## 阶段计划

### 阶段 0：纯搬移（1 个 PR，预计 −700 行）

| 新文件 | 搬走内容 |
|---|---|
| `lib/app/bootstrap/managed_provider_control_plane.dart` | `ManagedProviderControlPlane`、`ManagedProviderControlPlaneLease`、`buildDefaultManagedProviderUsageRegistry` |
| `lib/app/bootstrap/provider_usage_http_client.dart` | `_DefaultProviderUsageHttpClient`（改为公开名 `DefaultProviderUsageHttpClient`） |
| `lib/app/bootstrap/cursor_usage_stack.dart` | `_CursorUsageStack`、`_warmCursorUsage` |
| `lib/app/team_pilot_bootstrap.dart` | `TeamPilotBootstrap` + `_TeamPilotBootstrapState` |

同步：`lib/main.dart` import 更新；新增 `test/support/app_shell_source.dart`；三个源码 pin 测试改用新 helper。

### 阶段 1：抽取叶子装配块（每 PR 1~2 个，预计 −1400 行）

| 新文件 | 内容 | 量级 |
|---|---|---|
| `bootstrap/session_usage_wiring.dart` | Cursor 栈消费、`SessionUsageCubit`、`warmStartupCaches`、notification/progress | ~80 |
| `bootstrap/catalog_wiring.dart` | skill/plugin/mcp/extension/cliPresets 仓库、skill 安装引擎 | ~140 |
| `bootstrap/session_state_wiring.dart` | `LlmConfigCubit`、`identityRepository`、`sessionLifecycleService`、`sessionRepo`、home index prefetch | ~130 |
| `bootstrap/install_wiring.dart` | repo clone、install job registry | ~65 |
| `bootstrap/hub_wiring.dart` | team hub、expert hub、favorites、clone 服务、capability resolver、roster | ~200 |
| `bootstrap/workspace_wiring.dart` | workbench、floating、git/filetree/search/worktree/sessionGroups/tools/run 注册表、`configCubit` | ~60 |
| `bootstrap/connect_wiring.dart` | Connect 后端、embedded sshd、设备库、paired attempt、`sshConnectionCubit` | ~150 |
| `bootstrap/command_wiring.dart` | `CommandBus`、各 Host、`UiZoomBaseline`、terminal transport/shell ops | ~55 |
| `bootstrap/managed_provider_wiring.dart` | managed-provider 图与延迟 hydration | ~200 |
| `bootstrap/automation_wiring.dart` | automation repo/scheduler/dispatcher/runner/catalog module | ~150 |
| `bootstrap/agent_runtime_wiring.dart` | ask-user/exit-plan/permission gate、projections、gateway、`AgentRuntime`、prompt delivery | ~250 |
| `bootstrap/catalog_runtime_wiring.dart` | `CatalogRuntime.assemble` 的参数装配 | ~90 |
| `bootstrap/chat_session_wiring.dart` | `ChatCubit` 构造 | ~110 |

选块标准：只依赖已构造值或延迟 getter，不参与 teardown，不承载启动流程控制。

其中 `session_runtime_wiring.dart`（session remote activity、authority、protocol、chat history，约 160 行）可以并入阶段 1 的任一 PR。

### 阶段 2：核心平面装配（预计 −680 行）

| 新文件 | 内容 |
|---|---|
| `bootstrap/app_settings_wiring.dart` | `preferences` 派生设置、`SessionPreferencesCubit`、workspace 目录、ACP 日志开关 |
| `bootstrap/ssh_plane_wiring.dart` | SSH 凭据、relay 隧道、known hosts、worker manager、连接 gate、`SshClientFactory`、home target store、SSH catalog 迁移、`LocateRemoteClis` |
| `bootstrap/vault_wiring.dart` | `VaultService` / `VaultAccess` / capture / unlock gate / `VaultCubit` / legacy importer |
| `bootstrap/home_plane_wiring.dart` | home target 解析、`RuntimeContextRegistry`、home 连接尝试、`HomeStorage`、device id、vault scope |
| `bootstrap/platform_wiring.dart` | GitHub 账号、targets store、Termux 配置、remote download / app update |

本阶段仍然只搬连续块，`homeTarget` 等可变状态通过 getter/controller 暴露，不复制。

### 阶段 3：跨块共享闭包升级为 controller（预计 −970 行）

| 新文件 | 内容 |
|---|---|
| `bootstrap/home_plane_switch.dart` | `HomePlaneSwitchController`：`persistSshHomePathCacheIfLive`、`setHomeTarget`、`rebindHomeStoragePlane`、`switchHomeTarget` |
| `bootstrap/shell_boot.dart` | `ShellBootController`：`warmShellAndPrepareInteractive`、remote boot 链、`bootstrapAppData`、`reconnectHomeSshIfNeeded`、home 连接订阅 |

controller 持有可变状态（`homeTarget`、remote boot flags），对外暴露与原闭包同名的回调，保证注册身份与调用点不变。

### 阶段 4：编排器收尾

`buildAppShell` 只保留：按顺序调用各 wiring、给 `late final` 赋值、构造 `AppShell`、`try/catch` teardown。预期 `app_shell.dart` 约 1200~1400 行；其中 imports ~400、`AppShell` 类 ~290、编排与 shell 构造 ~500~700。如编排器仍超过 300 行，再拆私有 `_wireCoreServices` / `_wireProductGraph`，但不再新增 business 文件。

## PR 顺序

| PR | 内容 |
|---|---|
| PR-0 | 阶段 0：纯搬移 + `test/support/app_shell_source.dart` |
| PR-1~3 | 阶段 1 叶子块，两两一组：`session_usage+notification` → `catalog+install` → `hub+workspace` |
| PR-4~5 | 阶段 1 其余：`connect+command` → `managed_provider+automation` |
| PR-6 | `agent_runtime + session_runtime` |
| PR-7~8 | 阶段 2 核心平面：`app_settings+ssh_plane` → `vault+home_plane+platform` |
| PR-9~10 | 阶段 3：`HomePlaneSwitchController`、`ShellBootController` |
| PR-11 | 阶段 4 编排器收尾 |

每个 PR 独立可回滚，行为零变化。实现计划把上表细化为约 22 个可独立验证的任务；可按任务两两合并回这张表的 PR 粒度。

## 验证策略

每个 PR：

```bash
cd client
flutter analyze
dart run tool/run_tests.dart test/app test/integration/home_unreachable_boot_test.dart
```

再按被抽块补跑对应单测（如 `test/app/session_usage_services_test.dart`、`test/app/app_shell_provider_usage_bootstrap_test.dart`、`test/services/vault/legacy_import_test.dart`）。

交付前：`cd client && dart run tool/run_tests.dart`（全量，后台，遵守共享测试锁规则）。

纯搬移不新增功能测试；阶段 3 中可独立测试的纯判定逻辑（如 plane 切换条件）补单测。

## 风险清单

| # | 风险 | 规避 |
|---|---|---|
| 1 | `late final` 提前初始化 | 一律 getter 传参；code review 检查抽出函数签名 |
| 2 | 可变捕获被复制 | 状态留在 controller/闭包持有者；不在抽取函数内存 `var` |
| 3 | teardown 找不到依赖 | 相关声明保留在 `buildAppShell` |
| 4 | 顺序敏感步骤被打乱 | 只搬连续块，PR 内不改调用顺序 |
| 5 | 注册闭包重复/身份变化 | 搬移后在原位置只调用一次；不新增第二次注册 |
| 6 | 源码 pin 测试失败 | PR-0 先加 `test/support/app_shell_source.dart` 并改扫描范围 |
| 7 | 循环 import | `bootstrap/*` 不依赖 `AppShell`，用回调/接口 |

## 验收标准

1. `app_shell.dart` 约 1200~1400 行；`lib/app/bootstrap/*` 单文件 ≤ 300 行。
2. `flutter analyze` 无新增问题。
3. 定向测试与交付前全量测试全绿。
4. 三个源码 pin 测试保留全部断言，只改变扫描位置。
5. diff 以搬移为主；无初始化顺序、teardown、事件注册行为变化。
6. 每个阶段可独立回滚。
