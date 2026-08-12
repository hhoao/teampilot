# CLI 配置资产 Registry：统一 skills/mcp/plugins/hooks 注册与落盘 — 设计

Date: 2026-08-12
Status: Draft (brainstorming)

## 问题

五个 CLI（claude / flashskyai / codex / opencode / cursor）的"中途可注册、最终落文件系统"资产（skills、mcp servers、plugins、hooks、agents、rules、commands）目前没有统一注册与落盘架构：

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

**按资产类型拆 Registry 接口，每个 CLI 一个实现；Capability 构造注入 Registry，通过 Registry 注册资产；落盘（materialize）也在 Registry 中完成。**

```
┌─ 资产类型接口（均 implements CliCapability）─────────────┐
│  SkillRegistry / HookRegistry / McpRegistry /           │
│  PluginRegistry / AgentRegistry / RuleRegistry / ...    │
│  ├── register / unregister 资产                         │
│  ├── assetsFor(scope)                                   │
│  ├── materialize(scope) → 写本地（CLI 语法差异封装在此）  │
│  └── fingerprint / 变更通知                              │
└──────────────────────────────────────────────────────┘
                ▲ 每 CLI × 每类型一个实现
┌──────────────────────────────────────────────────────┐
│  ClaudeSkillRegistry / ClaudeHookRegistry /           │
│  OpencodeSkillRegistry / CursorHookRegistry / ...     │
│  （一个 CLI 的多个 Registry 共享上下文对象）             │
└──────────────────────────────────────────────────────┘
                ▲ 构造注入
┌──────────────────────────────────────────────────────┐
│  Capability（仍是核心抽象）                            │
│  PromptSubmitAckCapability({required HookRegistry hooks}) │
│  → hooks.register(CliHookSpec(event: 'promptSubmit', …)) │
└──────────────────────────────────────────────────────┘
```

### 资产模型（四元组）

```dart
enum AssetKind { skills, mcp, plugins, hooks, agents, rules, commands }

/// 运行时注册的资产声明。
class CliConfigAsset {
  final AssetKind kind;
  final Object payload;      // 类型化内容：SkillSpec / McpServerSpec / CliHookSpec / ...
  final AssetScope scope;    // app | team | workspace | session
  final AssetSource source;  // userConfig | pluginBundle | capability | hubInstall
  final String id;           // 资产唯一 id（unregister 用）
}
```

- **类实例资产**（如 `HookInstance` / MCP handler 对象）：注册后由 Registry 的 `materialize` 序列化为该 CLI 的配置片段；实例自身带 `toConfigFragment()` 或由 Registry 内部映射。
- **文件资产**：直接是配置片段（settings.json 段、脚本文件内容）。
- `source` + `scope` + `priority` 解决冲突（同一 MCP server 来自插件 bundle 与用户配置时谁赢）。

### Registry 接口（每资产类型一个）

```dart
abstract interface class HookRegistry implements CliCapability {
  /// 该 CLI 支持的规范事件 → 原生事件名映射
  /// （claude: UserPromptSubmit / cursor: beforeSubmitPrompt / opencode: 插件事件）
  Map<String, String> get eventNameMap;

  void register(CliConfigAsset asset);       // 运行时注册（中途）
  void unregister(String id);                // 中途移除
  List<CliConfigAsset> assetsFor(AssetScope scope);

  /// 纯函数：把注册的资产渲染为该 CLI 的配置片段。
  /// 幂等；相同输入产出相同输出（可指纹缓存）。
  Map<String, Object?> render(List<CliConfigAsset> assets);

  /// command 类 hook 落盘转发脚本（codex/cursor/flashskyai；opencode 为插件片段）。
  Future<void> provisionArtifacts(RegistryMaterializeContext ctx);

  String fingerprint(List<CliConfigAsset> assets);  // 增量重渲染
}
```

其余类型（`SkillRegistry` / `McpRegistry` / `PluginRegistry` / …）同构，仅 payload 与落地格式不同。已有 `McpConfigWriterCapability` 演进为 `McpRegistry`（重命名 + 补 fingerprint）；`PluginProvisionerCapability` 拆解为 Skills/Agents/Plugins Registry（`PluginComponentKind.supported` 已定好边界）。

### Registry 访问双通道

- **能力层：构造注入**（依赖显式，能力直接持有实例并注册资产）。
- **服务层：capability 查询**（`CliToolRegistry.capability<HookRegistry>(cli)`）。Registry 同时 `implements CliCapability` 并挂入各 `CliToolDefinition.capabilities` 列表，服务层（如 MCP fan-out、启动装配）无需持有实例即可按 CLI 查询——与现有 `capability<McpConfigWriterCapability>` 模式一致。

```dart
// 启动装配（app_shell.dart）
final claudeHooks = ClaudeHookRegistry(ctx: claudeCtx);
final claudeSkills = ClaudeSkillRegistry(ctx: claudeCtx);
cliToolRegistry.register(ClaudeCliTool(hooks: claudeHooks, skills: claudeSkills, ...));
// → ClaudeCliTool.capabilities 列表含 hooks / skills，服务层可 capability<HookRegistry>(CliTool.claude)
```

### Capability 注入

能力构造时注入所需 Registry（启动时组装，依赖显式）：

```dart
// app_shell.dart 启动装配
final claudeHooks = ClaudeHookRegistry(ctx: claudeCtx);
final claudeSkills = ClaudeSkillRegistry(ctx: claudeCtx);
// ... 每 CLI × 每类型实例化
cliToolRegistry.register(ClaudeCliTool(hooks: claudeHooks, skills: claudeSkills, ...));

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

### 落盘与生命周期

- **Registry 生命周期**：App 启动时创建，跨 session 存活（用户确认）。
- **scope 过滤**：`assetsFor(scope)` 按 app/team/workspace/session 过滤；合并语义复用既有 bundle 优先级（team > expert > workspace）。
- **materialize 时机**：launch 装配（`ConfigProfileCapability` 写配置前统一调用）+ 中途 register/unregister 触发 re-materialize。
- **统一装配点**：每个 CLI 的 `ConfigProfileCapability` 实现内，写 settings 前：

```dart
settings = hooks.render(hooks.assetsFor(scope));      // 一个调用替代 7 处 if 拼接
settings = mcp.render(mcp.assetsFor(scope));
// ...
if (fingerprint != cached) await writeSettingsFile(...);  // 指纹 diff 增量写
```

- **中途变更**：register/unregister → 变更通知 → 该 seat re-render → 指纹 diff → 增量写（支持"减"）。

### 与现有代码的映射（演进而非推倒）

| 现状 | 演进后 |
|------|--------|
| `agent_status_hooks.dart` / `bus_idle_stop_hook.dart` / `stop_idle_hook.dart` / cursor/codex overlays | 各 CLI 的 `HookRegistry` 实现（`render` 收敛全部语法差异） |
| `McpConfigWriterCapability` | `McpRegistry`（重命名 + fingerprint） |
| `PluginProvisionerCapability` | 拆解为 `SkillRegistry` / `AgentRegistry` / `PluginRegistry` |
| `ConfigProfileCapability` 装配点 | 保留——它管"文件组装"，资产渲染收敛到 Registry |
| `mcp_registry_service.dart` 手动 fan-out | Registry 查询（`capability<McpRegistry>(cli)`）+ 统一 materialize |

### 本次修复（hook ACK 桥）直接走此通道

`PromptSubmitAckCapability` 注册 `promptSubmit` 事件 → claude/flashskyai/codex 已有 UserPromptSubmit hook 转发到 `/agent-status`；opencode 插件补事件上报；cursor `beforeSubmitPrompt` 确认 payload。hook ACK 桥作为首个 Registry 消费者验证架构。

## 测试策略

- 每个 Registry 的 `render` 是纯函数 → 按 CLI 单测（输入资产集 → 断言配置文件片段），替代现在"合并逻辑散在 7 处难测"的现状。
- 指纹缓存：断言相同输入不触发写盘。
- 中途注册/反注册：register → re-materialize → 断言配置新增；unregister → 断言配置移除。

## 范围外（YAGNI）

- provider 凭据 / auth / 账号类（不属于"可注册资产"）。
- 每 session 新建 Registry（已定为启动时创建 + scope 过滤）。
