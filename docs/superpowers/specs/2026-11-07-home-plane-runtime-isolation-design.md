# Home 平面运行时隔离设计（远程设备切换的数据隔离）

- 日期：2026-11-07
- 状态：待审阅
- 来源：移动端连接过远程设备 A 后切到 B，出现 A 的 workspace / launch profile / 搜索索引等数据串到 B；用户要求按最好的架构、可扩展性、性能设计，不考虑工作量与向后兼容。
- 决策：采用「缓存生命周期 = 存储平面生命周期」的完整形态，不做 key 补丁、不做 pilot。

## 背景

### 现象

Android 上 home 可以绑定到远程 SSH 设备。切到另一台远程设备后，部分界面仍显示上一台设备的数据；两台设备的用户名相同时（例如都是 `ubuntu`）尤其容易复现，因为两者解析出的 app-data 根路径字符串完全相同。

### 现有架构

- `HomeStorage` 是 app 级单例门面，保存当前 `RuntimeContext`，`swap()` 发布新平面（`client/lib/services/storage/home_storage.dart:32-115`）。
- repositories / indexes / stores 大多在 `buildAppShell` 中构造一次，之后动态读取 `homeStorage.context`；其中一部分在构造时捕获了 `fs` / 路径。
- 切换 home 的链路：`setHomeTarget`（`client/lib/app/app_shell.dart:1528-1543`）→ `RuntimeContextRegistry.rebindHome` → `homeStorage.swap` → 旧 context retire → `onEvict` 断 SSH 连接（`app_shell.dart:1126-1137`）→ `HomeInvalidationService` 触发整包 reload（`home_invalidation_service.dart:36-233`）。
- reload 合约 `AppDataBootstrap.reloadAll`（`app_data_bootstrap.dart:386-451`）只覆盖约一半的平面状态。

### 根因清单（证据）

1. **静态缓存按路径字符串做 key，且永不清除**
   - `SessionRepository._workspacesIndexByRoot`（`client/lib/repositories/session_repository.dart:62,68,259`）——`static`，key 为 `appDataRoot`。
   - `LaunchProfileRepository._loadAllByRoot`（`client/lib/repositories/launch_profile_repository.dart:28,58`）——同样 `static`、同 key。
   - 两台不同设备路径相同时直接命中上一台设备的内存快照。
2. **索引在首次使用时绑定 `fs`，随 app 生命周期存活**
   - `WorkspaceSearchIndexes`（`client/lib/services/search/workspace_search_indexes.dart:16-56`）：文件索引按 workspace root、内容索引按 workspaceId，均捕获创建时的 `fs`。
   - `WorkspaceFileIndexRegistry.clear()` 的文档写着「Call when the home storage backend changes」（`client/lib/services/file_tree/workspace_file_index.dart:499-505`），但没有任何生产调用点。
3. **大量 repository/store 在构造时捕获 `fs` 或路径，切换后不会自动重建**
   - 典型：`ExtensionRepository`、`CliPresetsRepository`、`HookRepository`、`NotificationCubit`、`AutomationRepository` + `AutomationScheduler`、`FileRuntimeEventJournal`、`FilePromptDeliveryStore`、`PluginRepoDiskCacheService`、`WorkbenchLayoutPersistence`、`EditorCubit`、`WorkspaceShellConnector`。
   - 现有 `reloadAll` 不覆盖 hooks、CLI presets、notifications、automations、hub favorites/catalog、shortcuts、editor buffers、file-tree/search/worktree/run/session-group registries、`HomeWorkspaceUiCache`。
4. **`AiHistoryLoader` 只为远程/SSH context 清理**
   - `RuntimeContextRegistry._notifyEvicted` 仅对 remote / SSH 触发 `onEvict`（`runtime_context_registry.dart:152-156`），local → local 的平面切换不会清 history 缓存。
5. **靠"记得失效"的纪律无法防止回归**
   - 新增一个 `Map<String, X> byRoot` 就能重新引入同类问题；没有结构性约束。

## 目标

1. **结构性隔离**：任何平面派生状态的生命周期不得超过它所属的存储平面；平面死亡时状态随对象图一起销毁，不存在需要手工维护的失效清单。
2. **消除共享可变全局**：`lib/repositories/` 与 `lib/services/storage/` 不再存在持有平面数据的 `static` 可变缓存。
3. **切换可预测**：换设备 = 换运行时；同一设备重连（profile 编辑 / transport 重建）不重建 UI 状态与值缓存。
4. **失败可回滚**：新平面构造失败时保持旧平面可用，不出现半切换。
5. **性能不回退**：同一身份重连保留热缓存；换设备本来就要全量加载，重建不引入额外 IO。

## 非目标

- 不做离线模式、不做多 home 并行连接。
- 不改 SSH 协议 / worker / 传输层语义。
- 不做 UI 视觉改版。
- 不保留旧内部 API、不写迁移适配层（用户明确不考虑向后兼容）。

## 术语

- **控制面（Device plane）**：设备本地数据，位于 `nativeAppDataPath` / SharedPrefs / keychain。属于手机，不属于某台远端。
- **Home 平面（Home plane）**：位于 `<teampilotRoot>` 的全部数据（workspaces、sessions、launch profiles、providers、skills/plugins/MCP/extensions、automations、notifications、ui、usage、caches）。
- **平面身份（Plane identity）**：`target.id + "\u0000" + appDataRoot`。稳定、可比较；不用对象 identity，也不用 generation。
- **Transport 绑定**：`RuntimeContext`（`fs` + paths）与底层 SSH 连接池。同身份重连只换绑定，不换平面。
- **运行时（HomeRuntime）**：Home 平面的组合根与所有者；持有 `HomeStorage`、全部平面 repository/store/index/cache 与平面级 cubit。

## 设计

### 1. 三层所有权模型

| 层 | 生命周期 | 所有者 | 内容 |
|---|---|---|---|
| L1 控制面 | app | `DeviceRuntime` | AppSettings、主题/locale/zoom、SSH 目录与凭据、vault、Connect、`RemoteCliPathCache`、known hosts、HomeTarget 选择、设备级快捷键 |
| L2 Home 平面 | 每身份一份 | `HomeRuntime` | `HomeStorage`、全部平面 repository/store/index/cache、平面级 cubit、AutomationScheduler、事件传输端点 |
| L3 Transport | 随绑定 | `RuntimeContextRegistry` + `HomeRuntime` lease | `RuntimeContext`、`fs`、SSH storage pool |

所有权规则（唯一判据）：

> 读写发生在 `<teampilotRoot>` 之下 ⇒ 平面对象，由 `HomeRuntime` 构造与销毁。
> 读写发生在 `nativeAppDataPath` / SharedPrefs / keychain / 设备硬件 ⇒ 控制面对象，由 `DeviceRuntime` 构造，app 生命周期。

### 2. 平面身份与切换状态机

`HomeRuntimeIdentity`：

```dart
@immutable
final class HomeRuntimeIdentity {
  const HomeRuntimeIdentity({
    required this.targetId,
    required this.appDataRoot,
  });

  final String targetId;    // 'local' | 'ssh:<profileId>' | 'wsl:<distro>' | 'termux:default'
  final String appDataRoot; // 解析后的 <teampilotRoot>
}
```

`DeviceRuntime` 的 home 状态：

- `ready(identity)`：当前平面已安装。
- `switching(fromIdentity, target)`：正在解析/鉴权新平面；旧平面继续服务。
- `switchFailed(toTarget, error)`：保持旧平面，上报错误（UI 可重试或取消）。

切换规则：

1. 只有**解析成功且身份不同**才进入平面替换。
2. 身份相同（profile 只改了名称等）⇒ transport rebind，不替换平面。
3. **连接端点属于身份**：`targetId` 只含 profile id，因此同一 profile 被改为指向另一台主机（host/port/user 变化）时必须按身份变化处理，不能走 rebind。Plan 2 在解析出 `RuntimeContext` 后比较连接指纹（host/port/user），指纹不同即销毁并重建 runtime；否则两台解析出相同 `appDataRoot` 的主机会互相读到对方的值缓存。
4. 身份不同 ⇒ 构造新 `HomeRuntime` 成功后再发布；旧运行时在新运行时可见之后异步销毁。
5. 平面切换会把导航重置到 home：旧 workspace 路由引用旧平面数据，保留它们没有意义。

### 3. `HomeRuntime`

```dart
final class HomeRuntime {
  HomeRuntime._({
    required this.identity,
    required this.storage,
    required this.contextLease,
  });

  final HomeRuntimeIdentity identity;
  final HomeStorage storage;
  final RuntimeContextLease contextLease;

  int get transportGeneration;
  bool get disposed;

  // 平面组件（late final：未使用不构造）
  late final SessionRepository sessionRepo;
  late final LaunchProfileRepository launchProfiles;
  late final WorkspaceSearchIndexes searchIndexes;
  late final ChatCubit chat;
  // ... 其余按映射表

  Future<void> warm();
  Future<void> rebindTransport(RuntimeContext next);
  Future<void> dispose();
}
```

约束：

- 所有平面对象只允许在 `HomeRuntime` 的 factory / `late final` 初始化器中构造。
- `HomeRuntime` 维护一个内部 `List<FutureOr<void> Function()> _disposables`；每个平面组件注册自己的销毁动作。
- `dispose()` 幂等；按「停止生产者 → 排空在途 → 关闭 cubit → 释放索引/缓存 → 释放 context lease」顺序执行。
- 不暴露 `AppShell`，平面内部的服务互相通过构造参数注入，不通过全局查找。

### 4. 组合根与文件结构

为满足 `docs/CODE_QUALITY.md:184-188`（`app_shell.dart` 接近 4200 行，新增 ~80 行必须抽 factory），拆成：

| 文件 | 职责 | 目标规模 |
|---|---|---|
| `client/lib/app/device_runtime.dart` | L1 组合根：设备本地服务、SSH/vault/connect/settings、home 选择与切换状态机 | ≤600 行 |
| `client/lib/app/home_runtime.dart` | `HomeRuntime` 定义、身份、lease、生命周期 | ≤600 行 |
| `client/lib/app/home_runtime_factory.dart` | L2 组合根：构造 repository/store/index/cubit（必要时再按域拆 `home_runtime_data.dart` / `home_runtime_cubits.dart`） | 各 ≤600 行 |
| `client/lib/app/home_runtime_host.dart` | Widget 绑定：监听运行时变化，按身份重建子树 | ≤300 行 |
| `client/lib/app/app_shell.dart` | 启动编排 + 根 Widget；不再持有平面对象 | ≤800 行 |
| `client/lib/services/storage/home_runtime_identity.dart` | 身份值对象 | ≤80 行 |

### 5. UI 绑定

`main.dart` 的 Provider 树拆成两层：

- **外层 `DeviceProviderScope`**：保持 app 生命周期，内容来自 `DeviceRuntime`。
- **内层 `HomeRuntimeScope`**：由 `HomeRuntimeHost` 提供，内容来自当前 `HomeRuntime`；使用 `KeyedSubtree(key: ValueKey(identity.toString()))` 包裹平面子树。

行为：

- 身份变化：旧子树卸载 → 旧 cubit 关闭（由 runtime.dispose 负责）→ 新子树挂载并读取新 runtime。
- 控制面 Provider 不重建：主题、设置、SSH 目录不闪断。
- `MaterialApp.router` 位于平面子树内，因此换设备时导航栈重置；这是刻意行为。
- 页面只能通过 `context.read<X>()` 拿到平面对象；禁止把平面 cubit 缓存在长生命周期静态字段中。

### 6. 所有权映射（关键项）

**控制面（L1）**

- Settings：`AppSettingsRepository`、`AiFeatureSettingsCubit`、`DiscoverySettingsCubit`、`SessionPreferencesCubit`、`LayoutCubit`。
- SSH / 连接：`SshProfileCubit`、`SshProfileRepository`、`RemoteTargetRepository`、`SshCredentialStore`、`SshKnownHostRepository`、`SshClientFactory`、`SshProfileConnectionCoordinator`、`SshConnectionCubit`、`TermuxCubit`、`ConnectionModeService`。
- Connect：`ConnectCubit`、`PairedDeviceStore`、embedded/system sshd backends。
- 凭据：`VaultService`、`VaultCubit`、`VaultCredentialCapture`、`VaultUnlockGate`、`GithubCredentialsStore`、`ManagedProviderSecretStore`。
- Home 选择：`HomeTargetController`、`HomeTargetStore`、`RuntimeContextRegistry`。
- 设备缓存：`RemoteCliPathCache`、`RemoteDownloadCatalogCubit`、catalog-cache store。
- 设备 UX：`AppUpdateCubit`、`CommandBus`、`UiZoomBaseline`、`FloatingSurfaceRegistry`、`FloatingMaximizeInsets`、`WorkspaceDirectoryPicker`、`TerminalTransportFactory`。
- **`ShortcutCubit` 迁到控制面**：键位属于手机 UX，不应随远程设备变化；新增设备本地 store（`nativeAppDataPath/shortcuts.json`）。

**Home 平面（L2）**

- 存储：`HomeStorage`。
- 数据层：`SessionRepository`、`SessionLifecycleService`、`LaunchProfileRepository`、`WorkspaceProjectConfigRepository`、`AppProviderRepository`、`ManagedProviderRepository`、`ManagedProviderUsageRepository`、`HookRepository`、`CliPresetsRepository`、`ExtensionRepository`、`AutomationRepository`、`PluginRepoDiskCacheService`、`LocalExpertStore`、`ExpertHubCatalog`、`ExpertCapabilityResolver`、`FileRuntimeEventJournal`、`FilePromptDeliveryStore`、`InstallJobRegistry`、`NotificationRecorder`。
- 索引/注册表：`WorkspaceSearchIndexes`、`WorkspaceFileTreeStore`、`GitRepoStore`、`WorkspaceWorktreeRegistry`、`WorkspaceRunRegistry`、`WorkspaceSessionGroupsRegistry`、`WorkspaceToolsScopeRegistry`、`WorkspaceTerminalRegistry`、`WorkspaceShellConnector`、`WorkspaceTerminalSessionOps`、`WorkspaceTerminalRunService`、`WorkbenchLayoutPersistence`。
- 缓存：`HomeWorkspaceUiCache`、`AiHistoryLoader`、`SessionUsageServices`（实例内不再按 generation 做 key）、`ComposeDraftCache`、`MarkdownNetworkImageStore`（实例化，去掉静态 `storageHome`）。
- 设备 UI 偏好与平面 UI 偏好的切分：主题 / locale / typography / zoom 属于手机，留在 `LayoutCubit`（控制面）；workspace 收藏、打开的 workspace tab、workspace display prefs 引用平面 workspaceId，随 `HomeWorkspaceUiCache` 留在平面。
- Cubit：`ChatCubit`、`LaunchProfileCubit`、`SessionUsageCubit`、`AppProviderCubit`、`ManagedProviderCubit`、`ManagedProviderUsageCubit`、`LlmConfigCubit`、`WorkspaceToolsCubit`、`PluginCubit`、`CliPresetsCubit`、`SkillCubit`、`McpCubit`、`HookCubit`、`TeamHubCubit`、`ExpertHubCubit`、`ExtensionCubit`、`NotificationCubit`、`ProgressActivityCubit`、`AutomationCubit`、`AutomationScheduler`、`EditorCubit`、`WorkbenchCubit`、`FloatingWorkspaceCubit`、`RepoCloneCubit`、`AiHistoryCubit`、`MailboxCubit`、`BoardCubit`、`MemberPresenceCubit`、`AgentAttentionCubit`、`SeatLeaseCubit`、`AgentRuntime`、`TeamGenerationGraph`。
- 命令宿主：`WorkspaceChromeCommands`、`RunCommandHost`、`WorkspaceSearchHost`、`WorkspaceContentSearchHost`（持有平面服务引用）。

### 7. 缓存策略

- **值缓存**（不持 `fs`）：作为 `HomeRuntime` 的实例字段。平面存活期间保留，平面销毁即释放。`SessionRepository` / `LaunchProfileRepository` 中的静态 map 删除，改为实例 map。
- **绑 `fs` 的缓存**（`WorkspaceSearchIndexes`、`WorkspaceFileTreeStore`、`GitRepoStore` 等）：
  - 同身份 transport rebind：`HomeRuntime.rebindTransport` 递增 `transportGeneration` 并清空绑 `fs` 的索引；值缓存保留。
  - 身份变化：整个 runtime 销毁，无需单独失效。
- **无全局静态平面缓存**：`MarkdownNetworkImageStore.storageHome` 这类静态入口收窄为 runtime 注入的实例；`ComposeDraftCache` 保持按 session/workspace UUID 的内存表，但实例挂在 runtime 上。
- **不使用路径作为唯一 key**：身份进入所有必须跨平面共享的 map；首选直接消除跨平面共享。

### 8. 同身份 transport rebind

触发：当前 home profile 的 host/port/user/auth 变化、重连成功、profile 文档重载。

流程：

1. 解析新 `RuntimeContext`（失败保持旧绑定）。
2. `homeStorage.swap(next)`（现有 drain-safe：先发布、后 retire 旧 context）。
3. `transportGeneration++`。
4. 清空绑 `fs` 索引；rebind 事件传输端点。
5. 不重建 cubit、不重跑 `warm()`、不重置导航。

与旧 `reinstallStorageContext` 的差异：不再通过 `HomeInvalidationService` 的 generation barrier / echo 机制间接触发 reload；rebind 是显式命令。

### 9. Work-plane context lease

`RuntimeContextRegistry` 从「home 特化缓存」改为**纯 broker + 引用计数**：

- `Future<RuntimeContextLease> acquire(RuntimeTarget target)`；`lease.release()`。
- 计数归零且 target 不是当前 home 时，`disposeContext` + 关闭 transport。
- `HomeRuntime` 持有 home lease；workspace/session 级服务在首次使用 work target 时 acquire，workspace 关闭或 runtime 销毁时 release。
- 效果：work-plane 连接不会再跨 home 泄漏；同一 work target 被多个 workspace 使用时仍只开一条连接。

### 10. 事件传输

- app 级 `AsyncDispatcher` / `AgentPresenceProjection` 保持在 `TeamPilotBootstrap`（app 生命周期）。
- `EventTransportController` 仍为设备级，但端点绑定当前 runtime 的 `HomeStorage`：runtime 安装/rebind 时 apply，runtime 销毁时 stop。
- 不随平面创建新的 dispatcher，避免事件重复投递。

### 11. 错误处理与销毁顺序

- **切换失败**：新 context 解析或 runtime 构造失败 → 释放已构造的部分 → 保持旧 runtime 与旧绑定 → 向 UI 报错；不发布半成品。
- **销毁顺序**（`HomeRuntime.dispose`）：
  1. 停止生产者：scheduler、watcher、subscription、event endpoint。
  2. 排空在途：依赖 `HomeStorage.swap` 的 retire 契约；必要时 `await` 已登记的 drain future。
  3. 关闭 cubit（`close()`）。
  4. 释放索引/缓存（`dispose()` / `clear()`）。
  5. `contextLease.release()`（registry 决定是否断开 transport）。
- **销毁是异步且 off-frame**：新平面发布后，旧 runtime 的 dispose 由 `unawaited` 执行；失败只记录 `AppLogger`，不阻塞切换。
- **幂等**：重复 `dispose()` 是 no-op。

### 12. 删除项（不保留兼容）

- 删除 `HomeInvalidationService`、`HomeStorageInvalidator`、`HomeSshProfileImpact` 的 generation barrier / echo 逻辑及其测试。
- 删除 `SessionRepository.debugResetWorkspacesIndexCache`、`LaunchProfileRepository` 静态缓存及对应测试钩子。
- 删除 `AppDataBootstrap.reloadAll` 中「平面切换后补漏」的语义；平面构建改为 runtime 的 `warm()`。
- 删除 `HomeStorage` 的 app 级单例使用方式；保留其 drain-safe `swap()` 语义。
- 更新 `docs/ARCHITECTURE.md`、`docs/workspace-storage-layout.md` 的所有权说明。

### 13. 不变量与强制

- **I1**：`lib/repositories/`、`lib/services/storage/`、`lib/services/search/` 不新增持有平面数据的 `static` 可变字段。用源码扫描测试 + 小允许清单（纯常量、无平面输入）守住。
- **I2**：平面对象只能由 `HomeRuntimeFactory` 构造；Provider 树分层测试断言每个 Provider 的类型属于正确层。
- **I3**：任何 `HomeStorage` 读取都必须来自平面作用域；控制面代码不得依赖它。
- **I4**：`HomeRuntime.dispose()` 后，所有已构造平面组件的 `disposed`/`isClosed` 为真；重复 dispose 无副作用。
- **I5**：同身份 rebind 不改变 runtime 对象、cubit 实例与值缓存；`transportGeneration` 恰好 +1。

### 14. 性能

- **换设备**：与现状同量级的全量加载；额外收益是旧平面内存被释放，而不是持续累积。
- **同身份重连**：不重建 cubit、不清值缓存，只重建 transport 与绑 `fs` 索引；优于现状（现状会触发部分 reload）。
- **懒构造**：`late final` 保证未访问的子系统不分配。
- **UI**：控制面 Provider 稳定，主题/设置不闪断；仅平面子树重建。
- **销毁**：不在切换关键帧内同步执行；避免 UI 卡顿。

## 测试

### 新增

- `test/app/home_runtime_identity_test.dart`：身份相等性；同 target 不同 root、不同 target 同 root 均不相等。
- `test/app/home_runtime_lifecycle_test.dart`：构造失败回滚；dispose 幂等与顺序；构造子集失败时已构造部分被释放。
- `test/app/home_runtime_isolation_test.dart`：两个身份、相同 `appDataRoot`，断言 `SessionRepository` / `LaunchProfileRepository` / `WorkspaceSearchIndexes` / `AiHistoryLoader` 实例与内部状态完全独立；B 读不到 A 的 workspace / launch profile。
- `test/app/home_runtime_rebind_test.dart`：同身份 rebind 保留值缓存、清空绑 `fs` 索引、`transportGeneration` +1、cubit 实例不变。
- `test/app/home_runtime_host_test.dart`：身份变化重建平面子树；控制面 Provider 实例不变；旧 cubit 已关闭；导航重置到 home。
- `test/app/home_runtime_ownership_guard_test.dart`：源码/Provider 分层断言 I1–I2。

### 调整/删除

- 保留并改写 `home_storage_test.dart`（drain-safe swap 语义不变）。
- 删除 `home_invalidation_service_test.dart`、`home_storage_invalidator_test.dart`、`home_ssh_profile_impact_test.dart`。
- 改写 `runtime_context_registry_test.dart` 为 lease/refcount 语义。
- 改写 `test/app/session_usage_services_test.dart`：从 generation key 改为 runtime 实例隔离。
- Android 手测：home A → 切 B（同用户名）→ 确认 workspace / launch profile / 搜索 / 通知 / automation / editor 均不串；切回 A 确认数据恢复且热缓存命中。

## 风险

1. **改动面大**：Provider 树、启动编排、cubit 所有权同时变化。缓解：单个 spec 内分四期实现，每期独立测试通过后再前进（见下）。
2. **导航重置**：换设备重置路由栈是刻意的；需要在 UI 上给出清晰的「已切换设备」反馈。
3. **Work-plane 多目标语义**：lease/refcount 改变现有「work context 永久缓存」的行为；需要覆盖同一 work target 被多 workspace 共享、以及 home 切换后 work context 释放的测试。
4. **销毁与在途操作竞争**：沿用 `HomeStorage` 的 drain-safe 契约；新增测试覆盖 dispose 期间的 in-flight 读写。
5. **启动时长**：runtime 构造如果同步做太多 IO 会拖慢启动；要求构造阶段只做依赖装配，所有 IO 进入 `warm()`。

## 内部实施分期

- **Phase A — 身份与骨架**：`HomeRuntimeIdentity`、`HomeRuntime`、factory 骨架；迁移两个静态缓存、`WorkspaceSearchIndexes`、`AiHistoryLoader`；隔离测试先绿。
- **Phase B — 数据层**：把全部平面 repository/store/index/cache 迁入 runtime；删除旧 `reloadAll` 补漏路径。
- **Phase C — Cubit 与 UI**：平面 cubit 迁入 runtime；`HomeRuntimeHost` 与双层 Provider 树；导航重置行为落地。
- **Phase D — 清理与文档**：删除 `HomeInvalidationService` 系列；broker lease 化；更新架构文档与手测清单。

## 决策记录

1. 控制面（SSH 目录、vault、设置、Connect、设备 UI 偏好）**不随**换设备重建。
2. 平面身份 = `target.id + appDataRoot`；同身份 reconnect 只换 transport。
3. 平面级 cubit 随 runtime 重建，页面不得跨平面持有。
4. `HomeStorage` 降级为平面对象，不再是 app 级单例。
5. Work-plane context 由 registry 引用计数，归零即释放。
6. `ShortcutCubit` 迁到设备本地：键位是手机 UX。
7. 不保留旧失效链路（`HomeInvalidationService` 等），不做向后兼容。
