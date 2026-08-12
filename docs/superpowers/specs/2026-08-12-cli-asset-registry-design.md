# CLI 配置资产 Registry：统一 skills/mcp/plugins/hooks 注册与落盘 — 设计

Date: 2026-08-12
Status: Draft (brainstorming, rev 2)

## 问题

五个 CLI（claude / flashskyai / codex / opencode / cursor）的"中途可注册、最终落文件系统"资产（skills、mcp servers、plugins、hooks）目前没有统一注册与落盘架构：

1. **hook 注入散落 7 处**，每处手写原始 map 模板（`'hooks': [{'type': 'http', 'url': ..., 'headers': ...}]`）：
   - `registry/config_profile/bus_idle_stop_hook.dart`（claude Stop → /idle）
   - `registry/config_profile/agent_status_hooks.dart`（claude/flashskyai 8 事件 → /agent-status）
   - `flashskyai/capabilities/stop_idle_hook.dart`（command 脚本，exit 2 语义）
   - `cursor/provider/cursor_home_bus_overlay.dart`、`cursor_home_agent_status_overlay.dart`（hooks.json + bash 转发）
   - `codex/provider/codex_agent_status_overlay.dart`（config.toml command 脚本）
   - 装配点 `claude/capabilities/config_profile.dart:769-775`（串行 if 拼接）
2. **幂等逻辑重复 7 遍**（按 url 查重 / 按 command 查重两种写法）。
3. **三种配置格式**（settings.json / hooks.json / config.toml）+ 两种 hook 形态（HTTP / command 脚本）散在各处。
4. **MCP 中途注册靠手动 fan-out**：`mcp_registry_service.dart:306` 遍历 `CliTool.values` 挨个写。
5. **能力要注册 hook/skill 没有入口**：新能力（如 prompt-submit ACK）只能再复制一份 merge 模板、再改各 CLI 装配点。
6. **只有"加"没有"减"**：中途禁用资产后配置残留。

根因：**"声明资产"与"CLI 如何落地资产"耦合**，且没有统一的运行时注册中心。

## 架构

**泛型注册表核心 + 按资产类型的窄特化；每个 CLI 一个实现；Capability 构造注入 Registry 注册资产；落盘收敛到统一装配点。**

```
┌─ 泛型核心 CliAssetRegistry<T>（implements CliCapability）──┐
│  纯内存，无 IO：                                           │
│  ├── register / unregister                                 │
│  ├── assetsFor(scope)  ← scope 过滤 + 优先级合并            │
│  ├── fingerprint(assets)                                   │
│  └── 变更通知（register/unregister → notify）               │
└────────────────────────────────────────────────────────┘
                ▲ 类型化窄特化（只留"资产 → 配置片段"纯函数）
┌────────────────────────────────────────────────────────┐
│  HookRegistry extends CliAssetRegistry<CliHookSpec>      │
│    └─ render(assets) → Map<String, Object?> 片段         │
│    └─ 事件名映射 / command 脚本生成                       │
│  McpRegistry extends CliAssetRegistry<McpServerSpec>     │
│  SkillRegistry extends CliAssetRegistry<SkillSpec>       │
└────────────────────────────────────────────────────────┘
                ▲ 每 CLI × 每类型一个实现
┌────────────────────────────────────────────────────────┐
│  ClaudeHookRegistry / OpencodeHookRegistry /            │
│  CursorHookRegistry / CodexHookRegistry / ...           │
│  （一个 CLI 的多个 Registry 共享上下文对象）               │
└────────────────────────────────────────────────────────┘
                ▲ 构造注入（能力层）/ capability 查询（服务层）
┌────────────────────────────────────────────────────────┐
│  PromptSubmitAckCapability({required HookRegistry hooks}) │
│  → hooks.register(CliHookSpec(event: 'promptSubmit', …)) │
└────────────────────────────────────────────────────────┘
```

### 职责分区（SRP）

| 职责 | 归属 | IO |
|------|------|-----|
| 注册 / 查询 / 指纹 / 变更通知 | `CliAssetRegistry<T>` 泛型基类 | 无 |
| 资产 → 配置片段 | 类型特化 `render`（纯函数） | 无 |
| command 脚本生成 | 特化内（codex/cursor/flashskyai） | 无（返回脚本内容） |
| 落盘（materialize / 写文件） | **统一装配点**（`ConfigProfileCapability` 写配置前） | 有 |

Registry **不落盘**——能力不碰文件系统，落盘统一由装配点执行。这是 rev 1 → rev 2 的关键修正（rev 1 把 materialize 放进 Registry，职责过重）。

### 资产模型

```dart
/// rev 2：只建已有真实消费者的类型；agents/rules/commands 等有需求再补。
enum AssetKind { skills, mcp, plugins, hooks }

class CliConfigAsset<T> {
  final AssetKind kind;
  final T payload;          // 类型化内容：SkillSpec / McpServerSpec / CliHookSpec / ...
  final AssetScope scope;   // app | team | workspace | session
  final AssetSource source; // userConfig | pluginBundle | capability | hubInstall
  final int level;          // 同 scope 同 source 内排序，数值大者优先（见合并规则链）
  final String id;          // 资产唯一 id（unregister 用）
}
```

### scope 合并语义（定义死，不留模糊）

资产注册时带 `scope`；落盘时按 bundle 既有优先级合并（team > expert > workspace）：

```
app        → 最低优先级（全局默认，被任何上层覆盖）
team       → 覆盖 app
workspace  → 覆盖 team
session    → 最高优先级（本次会话）
```

### scope 合并语义（定义死，不留模糊）

资产注册时带 `scope`；落盘时按 bundle 既有优先级合并（team > expert > workspace）：

```
app        → 最低优先级（全局默认，被任何上层覆盖）
team       → 覆盖 app
workspace  → 覆盖 team
session    → 最高优先级（本次会话）
```

### 合并规则链（一条规则，不分支）

```
1. scope 层级（session > workspace > team > app）           ← 主序
2. source 优先级（capability > userConfig > pluginBundle）  ← 次序
3. level（同 scope 同 source 内，int，数值大者优先）         ← 末序
4. 注册顺序（仍相同 → 后注册覆盖先注册）                     ← 兜底
```

- `level` 为普通 `int` 字段，不设取值范围、无默认值约束；只在**同 scope 同 source** 内比较，跨 scope / 跨 source 仍由前两级决定。
- 资产生命周期内 `level` 不变（unregister 后重新 register 不得改变相对顺序）。
- 合并逻辑放泛型基类 `assetsFor(scope)`，一次实现全类型复用。

### Registry 接口（泛型核心 + 特化）

```dart
/// 泛型核心：纯内存注册表（无 IO）。
abstract class CliAssetRegistry<T> implements CliCapability {
  void register(CliConfigAsset<T> asset);
  void unregister(String id);
  List<CliConfigAsset<T>> assetsFor(AssetScope scope);   // 过滤 + 优先级合并
  String fingerprint(List<CliConfigAsset<T>> assets);    // 增量重渲染
  void addListener(void Function() onChanged);           // 中途变更通知
}

/// hooks 特化：只加"资产 → 配置片段"。
abstract interface class HookRegistry extends CliAssetRegistry<CliHookSpec> {
  /// 该 CLI 支持的规范事件 → 原生事件名映射
  /// （claude: UserPromptSubmit / cursor: beforeSubmitPrompt / opencode: 插件事件）
  Map<String, String> get eventNameMap;

  /// 纯函数：资产集 → 该 CLI 的 hooks 配置片段（幂等）。
  Map<String, Object?> render(List<CliConfigAsset<CliHookSpec>> assets);

  /// command 类 hook 的脚本内容（codex/cursor/flashskyai；opencode 为插件片段）。
  List<GeneratedScript> generateScripts(List<CliConfigAsset<CliHookSpec>> assets);
}
```

其余类型（`McpRegistry` / `SkillRegistry` / `PluginRegistry`）同构，仅 payload 与 render 输出格式不同。

### Registry 访问双通道

- **能力层：构造注入**（依赖显式，能力直接持有实例并注册资产）。
- **服务层：capability 查询**（`CliToolRegistry.capability<HookRegistry>(cli)`）。Registry 同时 `implements CliCapability` 并挂入各 `CliToolDefinition.capabilities` 列表，服务层（如 MCP fan-out、启动装配）无需持有实例即可按 CLI 查询——与现有 `capability<McpConfigWriterCapability>` 模式一致。

```dart
// 启动装配（app_shell.dart）
final claudeHooks = ClaudeHookRegistry(ctx: claudeCtx);
cliToolRegistry.register(ClaudeCliTool(hooks: claudeHooks, ...));
// → ClaudeCliTool.capabilities 列表含 hooks，服务层可 capability<HookRegistry>(CliTool.claude)
```

### Capability 注入

能力构造时注入所需 Registry（启动时组装，依赖显式）：

```dart
// 能力注册资产（构造时或首用懒注册）
PromptSubmitAckCapability({required HookRegistry hooks})
  : _hooks = hooks {
  _hooks.register(CliConfigAsset(
    kind: AssetKind.hooks,
    payload: CliHookSpec(event: 'promptSubmit', url: ackEndpoint, ...),
    scope: AssetScope.app,
    source: AssetSource.capability,
    id: 'prompt-submit-ack',
  ));
}
```

### 统一落盘装配点（Registry 不落盘）

每个 CLI 的 `ConfigProfileCapability` 实现内，写配置前统一收集渲染：

```dart
final hooks = _registry.capability<HookRegistry>(cli);      // 服务层查询
final assets = hooks?.assetsFor(scope) ?? const [];
final rendered = hooks?.render(assets);                      // 纯函数
settings = merge(settings, rendered);                        // 片段并入 settings
// ... mcp / skills 同构
if (fingerprint != cached) await writeSettingsFile(...);     // 指纹 diff 增量写
```

- **materialize 时机**：launch 装配（`ConfigProfileCapability` 写配置前）+ 中途 register/unregister 变更通知触发该 seat re-materialize（复用同一装配点）。
- **指纹缓存**：`fingerprint(assets)` 不变则跳过写盘；支持"减"（unregister → 重渲染 → 移除配置项）。

### 与现有代码的映射（演进而非推倒）

| 现状 | 演进后 |
|------|--------|
| `agent_status_hooks.dart` / `bus_idle_stop_hook.dart` / `stop_idle_hook.dart` / cursor/codex overlays | 各 CLI 的 `HookRegistry` 实现（`render` 收敛全部语法差异） |
| `McpConfigWriterCapability` | `McpRegistry`（重命名 + fingerprint，阶段 2） |
| `PluginProvisionerCapability` | `SkillRegistry` / `PluginRegistry`（阶段 3，`PluginComponentKind.supported` 已定好边界） |
| `ConfigProfileCapability` 装配点 | 保留——统一落盘入口，资产渲染收敛到 Registry |
| `mcp_registry_service.dart` 手动 fan-out | Registry 查询（`capability<McpRegistry>(cli)`）+ 统一装配点（阶段 2） |

## 分阶段落地（每阶段有真实消费者）

| 阶段 | 内容 | 消费者 |
|------|------|--------|
| 1（本次） | 泛型核心 + `HookRegistry` | prompt-submit ACK 桥 + 现有 7 处 hook merge 收敛 |
| 2 | `McpRegistry` | `mcp_registry_service` fan-out 替换 |
| 3 | `SkillRegistry` / `PluginRegistry` | plugin provisioner 拆解（按需） |
| 暂不做 | agents / rules / commands | 无真实中途注册需求，`AssetKind` 不建 |

### 本次修复（hook ACK 桥）直接走此通道

阶段 1 内：`PromptSubmitAckCapability` 注册 `promptSubmit` 事件 → claude/flashskyai/codex 已有 UserPromptSubmit hook 转发到 `/agent-status`；opencode 插件补事件上报；cursor `beforeSubmitPrompt` 确认 payload。hook ACK 桥作为首个 Registry 消费者验证架构。

## 测试策略

- 泛型核心：注册/反注册/scope 合并/优先级冲突/指纹——一次实现全类型复用，按类型参数化测试。
- 每个特化 `render` 是纯函数 → 按 CLI 单测（输入资产集 → 断言配置文件片段），替代现在"合并逻辑散在 7 处难测"的现状。
- 指纹缓存：断言相同输入不触发写盘。
- 中途注册/反注册：register → re-materialize → 断言配置新增；unregister → 断言配置移除。

## 范围外（YAGNI）

- provider 凭据 / auth / 账号类（不属于"可注册资产"）。
- 每 session 新建 Registry（已定为启动时创建 + scope 过滤）。
- agents / rules / commands 资产类型（阶段 4+，无消费者前不建）。
