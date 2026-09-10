# 中央事件发布层（AsyncDispatcher）设计

- 日期：2026-09-10
- 状态：已批准（方案 A：单一中央 AsyncDispatcher，架构参照 Hadoop YARN `org.apache.hadoop.yarn.event`）
- 背景：`feat-host-session-runtime` 分支的教训——runtime daemon 在没有统一事件架构时另起平行事件体系，导致服务间耦合失控、回归不断。本设计先落地进程内事件发布层，作为后续 Runtime daemon 接入的地基。

## 目标与非目标

### 目标

1. 移植 YARN `event` 包核心语义到 Dart/Flutter：`Event` / `EventHandler` / `Dispatcher` / `AsyncDispatcher`。
2. 让服务之间通过中央 dispatcher 的事件发布联系起来（发布方入队即返回，消费方按事件族注册 handler）。
3. 迁移两个现有事件源（`CatalogMutationBus`、`WorkspaceFsWatcher`）作为首批接入，行为等价。
4. 新增 Session 生命周期事件族，作为 Runtime daemon 的地基。

### 非目标

- 不迁移、不包装、不改动 `agent_runtime/`（`RuntimeEventEnvelope`、`SeatEventStream`、`AgentEventGateway` 保持原样；二期收编时让 envelope 实现 `DispatcherEvent` 接口）。
- 不做跨进程事件传输（Runtime daemon 的 envelope 传输层是后续期）。
- 不做查询面/RPC（文件列表、git 状态查询走现有服务接口；事件只承载失效信号与事实广播）。
- PTY 帧等高频字节流不进 dispatcher。
- 不引入有界队列的阻塞语义。

## 包结构（对应 YARN event 包）

新目录 `client/lib/services/event/`：

| YARN | Dart 对应 | 职责 |
|---|---|---|
| `Event<TYPE extends Enum>` | `DispatcherEvent<K extends Enum>` | `K get kind; DateTime get timestamp;` |
| `AbstractEvent<TYPE>` | 各事件族 sealed class 基类 | 提供 kind/timestamp 构造 |
| `EventHandler<T>` | `EventHandler<T extends DispatcherEvent>` | `void handle(T event)` |
| `Dispatcher` 接口 | `Dispatcher` | `void dispatch(event)`（发布口）+ `void register<K>(EventHandler)` / `void unregister(handler)` |
| `AsyncDispatcher` | `AsyncDispatcher` | 队列 + 消费循环 + 按族路由 + 多播 |
| `EventDispatcher`（单族独立队列便捷类） | 不移植 | Dart 单线程无对应需求（YAGNI） |

事件词汇表分域：每个事件族自带 sealed class + 自己的 kind 枚举（同 YARN 每域一个 `EventType` 枚举的作风）。dispatcher 泛型于族，不认识任何具体词汇。

## AsyncDispatcher 语义（与 YARN 异同逐条明示）

| 性质 | YARN | 本设计 |
|---|---|---|
| 发布 | `getEventHandler().handle(e)` 入 `BlockingQueue` 即返回 | `dispatch(event)` 入队即返回，永不阻塞 |
| 消费 | 单 `eventHandlingThread` | 单 Future 消费循环（Dart 单线程事件循环替代） |
| 路由 | `Map<Class<Enum>, EventHandler>`，register 时同族已有则包 `MultiListenerHandler` | 同语义：`Map<K, EventHandler>`，已有 handler 自动包多播列表 |
| 错误隔离 | 默认 `exitOnDispatchException=true` 进程退出 | **偏离**：单 handler 抛异常 → `AppLogger.error` + 继续处理下一个事件（桌面 app 不能整体退出） |
| 顺序 | 同 dispatcher 全局有序 | 同 |
| 生命周期 | service start/stop，`drainEventsOnStop` | `start()` / `stop()`，stop 时 drain 剩余事件再关闭（退出路径不丢已发布事件） |
| 可观测 | `EventTypeMetrics` 每类计数 | 每族事件计数 + 队列深度；深度 >1000 时 `AppLogger.warn` |
| 队列 | 有界 `LinkedBlockingQueue`（防多线程生产者内存失控） | **偏离**：无界队列 + 深度告警（Dart 单线程生产者不会真正并发堆积，不引入阻塞语义） |

## 首批事件族

```dart
// 1. Session 生命周期（新造；Runtime daemon 地基）
enum SessionLifecycleKind {
  sessionSpawned, sessionStarted, seatStarted,
  seatInterrupted, seatExited, sessionClosed,
}
sealed class SessionLifecycleEvent implements DispatcherEvent<SessionLifecycleKind> {
  // 字段：sessionId、memberId（seat 事件）、occurredAt
}

// 2. Catalog 变更（迁移 CatalogMutationEvent，词汇照搬不动）
// 3. Workspace FS 失效（迁移 FsChangeBatch，包一层 WorkspaceFsChangedEvent）
```

发布点：

- Session 生命周期：`SessionLaunchService` / 会话关闭路径的 spawn/start/exit 钩子处 dispatch。
- Catalog：`CatalogMutationBus.emit` 内部转发 `dispatch`。
- FS：`WorkspaceFsWatcher` 去抖批次的发出点转发 `dispatch`。

## 迁移策略（行为等价重构）

- `CatalogMutationBus`、`WorkspaceFsWatcher` 对外订阅接口**保留不变**（消费方零改动），内部改为向 dispatcher 发布 + Stream 适配器回填。
- 注入：`app_shell.dart` 构造单个 `AsyncDispatcher`，注入两个迁移源与 `SessionLaunchService`（依赖注入规则，不用全局单例）。

## 测试策略

- Dispatcher 单测：入队即返回、全局有序、按族路由、多播、unregister、handler 异常不阻断后续、stop 时 drain、队列深度告警。
- 迁移对照：`CatalogMutationBus` / `WorkspaceFsWatcher` 现有测试原样必须通过（行为等价证据）。
- 新增 session 生命周期发布点测试。

### 验收标准（用户已确认）

测试绿（`flutter analyze --no-fatal-infos --no-fatal-warnings` + `dart run tool/run_tests.dart` 全套）+ 行为等价（迁移源现有测试原样通过）。UI 无任何变化（本期为等价重构）。

## 工作方式

新开 git worktree 实施（不污染主仓正在运行的应用）。
