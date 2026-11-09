# CLI 代码拆分为独立 agent 包（注册式隔离 + 编译期自动注册）

- 日期：2026-11-09
- 依据：`docs/cli-architecture.md`、`AGENTS.md`、`docs/ARCHITECTURE.md`、`docs/DEVELOPMENT.md`
- 状态：设计已确认，待实现计划（writing-plans）

## 1. 目标与非目标

### 目标

把 `client/lib/services/cli/` 下 9 个 CLI 的实现拆成独立的 Dart 包，使 agent 成为**自注册、自描述的隔离单元**：宿主（app / `teampilot-common` / `teampilot-agent-api`）在编译期不知道"有哪些 agent"，也不对具体 agent 分支；所有 agent 专属信息（元数据、能力、UI）由 agent 包在注册时提供。

采用**编译期自动发现**：app 源码不 import 任何具体 agent 包、不写注册代码；由 `build_runner` 生成器从注解产出注册表。

### 非目标

- 不做运行时插件加载（Flutter AOT 不能动态加载 Dart 包）。
- 不做 Java SPI 式的运行时 classpath 扫描 + 反射；Dart/Flutter 无 `dart:mirrors`。
- 不改变任何 CLI 的运行时行为、能力语义、磁盘格式或 UI 外观。
- 不新增 CLI，不改动 9 个 CLI 的能力注册形状。
- 不引入新的 l10n 机制；`app_en.arb` / `app_zh.arb` 仍是翻译的唯一位置。

## 2. 背景与现状证据

| 事实 | 证据 |
|------|------|
| `services/cli/` 共 409 个 dart 文件：9 个 CLI 目录 + `registry/`（能力接口与共享基础设施约 100 文件）+ 根级 helper + `member_config/` / `session_lifecycle/` / `tasks/` | `find client/lib/services/cli -name '*.dart' \| wc -l` |
| 现有"类 SPI"机制是手写注册：`CliToolRegistry` + `CliToolDefinition` / `CliCapability` + `built_in_cli_tools.dart` 里 9 次 `registry.register(...)` + `CliBootstrap` Map 注入 | `registry/cli_tool_registry.dart:13`、`registry/built_in_cli_tools.dart:55`、`registry/cli_bootstrap.dart` |
| 项目已有开放注册范式：`CatalogKindRegistry` 用 `Map<String, CatalogKindModule>`，module 自己 `advertise()` / `handle()`，宿主只遍历，无 `switch (kind)` | `services/catalog/catalog_kind_registry.dart:28` |
| `CliTool` 是封闭枚举（9 值），409 个文件引用、其中 271 个在 cli 目录外；依赖 `values` 循环、穷尽 switch、静态 keyed map、`decode` 兜底 | `models/team_config.dart:19`、`l10n/l10n_extensions.dart:38-49`、`models/hook_event.dart:58`、`repositories/app_provider_repository.dart:130` |
| CLI 代码通过相对 import 深度依赖 app 内部：63 个 app 内部文件（claude 单个 CLI）、33 个 Flutter UI 文件、19 个 l10n 文件；CLI 之间存在交叉引用 | `client/lib/services/cli/` import 扫描 |
| claude 试点规模：50 个 dart 文件、63 个 app 内部依赖（9 `models/`、46 `services/`、3 `repositories/`、3 `utils/`、2 `l10n/`）、3 个 Flutter 文件、8 个其它 CLI 文件反向 import 它 | 同上 |
| `build.yaml` 的 `auto_apply` / `required_inputs` / `runs_before` / `global_options` 可用；`BuildStep.findAssets` 仅限当前包；`Resolver.libraries` 从 primary input 递归爬 import/export（含依赖包） | `~/.pub-cache/hosted/pub.dev/build_config-1.4.0/lib/src/builder_definition.dart:16,61-69`、`build-4.0.11/lib/src/build_step.dart:77`、`build-4.0.11/lib/src/resolver.dart:23-32`、`build_resolvers-3.0.3/lib/src/resolver.dart:51-88` |
| CI 在 `client` 根跑 `flutter pub get` / `flutter analyze` / `dart run tool/run_tests.dart`；`run_tests.dart` 包装 `flutter test` 并用 `.dart_tool/run_tests.lock` 串行化 | `.github/workflows/client-verify.yml:120-145`、`client/tool/run_tests.dart:1-30` |
| 9 个 `appProviderTool*` 在 `app_en.arb` / `app_zh.arb` 中中英文完全相同（品牌名） | `lib/l10n/app_en.arb:3057-3065`、`app_zh.arb:2658-2666` |

## 3. 关键决策

| 编号 | 决策 | 被否决方案与理由 |
|------|------|------------------|
| D1 | **编译期解耦**：app 的 pubspec 仍以 path 依赖各 agent 包（Dart 必须把代码编译进二进制），但 app 源码不 import 具体 agent、不写注册代码 | 运行时插件加载：Flutter AOT 不可行 |
| D2 | **全端口倒置**：`teampilot-common` 纯 Dart 零 Flutter；`teampilot-agent-api` 定义全部契约/端口；app 实现宿主侧端口并注入 | 全量下沉（把 ~100 个 app 文件搬进 common）：common 会变成"半个 app"，仍带 Flutter/l10n |
| D3 | **零残留隔离**：宿主里不出现任何具体 agent 字面量、`switch`、`==`、`values` 循环；agent 专属信息全部由 agent 包注册时提供；完整性由契约测试保证 | 保留封闭枚举并下沉到 common：等于让宿主在编译期列全 agent，破坏"注册式隔离"语义 |
| D4 | 身份从封闭枚举 `CliTool` 变为不透明 `AgentId`；终态删除 `CliTool.values` 相关 assert、穷尽 switch、静态 keyed map 与 `decode` 兜底 | 双层 ID（内置枚举 + 第三方开放 ID）：两套 ID 并存、复杂度最高 |
| D5 | **垂直切片**：Spec 1 用 claude 跑通全链路，其余 8 个 CLI 过渡期留在 `services/cli/`，经一次性兼容 adapter 进同一个 `AgentRegistry` | 自底向上（先 271 文件身份迁移）：风险最大的改造前置且看不到成果；先骨架后填充：中间态仍是单体 |
| D6 | **注解 + `build_runner`（2-α）**：清单式 import + `resolver.libraries` 扫描注解 | `tool/` 扫描脚本（方案 1）：可行但用户选择注解式开发体验；`build.yaml` 列包名的 micro-package（2-γ）：9 处 build.yaml + dev_deps，最重；pubspec 驱动发现（2-β）：依赖包资产可见性脆弱，留作后续增强 |
| D7 | `teampilot-agents/` 是**纯容器目录**，里面每一项都是完整同级包；聚合注册包与生成器包拆成两个包 | 容器自身作为 bundle package：容器同时带 pubspec/lib/build.yaml 又嵌子包，结构混乱；bundle 与 builder 合一：运行时包会带 `build`/`source_gen`/`analyzer` 普通依赖 |
| D8 | 接受一处残留：agent UI 工厂里需翻译的文案仍落 `app_en.arb` / `app_zh.arb`（键命名空间 `agentClaudeXxx`），新增 agent 要补两个 arb 文件 | 放宽 l10n 硬规则让包内自带文案：违反 AGENTS.md 且需单独立规 |

2-α 的取舍说明：build_runner 无法枚举目录（`findAssets` 限当前包），但 `Resolver.libraries` 能从 primary input 的 import/export 图递归看到依赖包里的注解类。因此"自动发现"落在**源码 import 图**而非文件系统；新增 agent 仍需改一处清单（manifest 的一行 import）+ 一处 pubspec path dep。这是 Dart 依赖模型下不可消除的成本。

## 4. 目标态架构

### 4.1 包布局

```
client/packages/
  teampilot-common/                     # name: teampilot_common（纯 Dart、零 Flutter）
  teampilot-agent-api/                  # name: teampilot_agent_api
  teampilot-agents/                     # 纯容器，无 pubspec.yaml / lib/ / build.yaml
    teampilot-agent-claude/             # name: teampilot_agent_claude
    teampilot-agent-codex/              # Spec 2+
    teampilot-agent-cursor/             # Spec 3+
    teampilot-agent-opencode/           # Spec 4+
    teampilot-agent-flashskyai/         # Spec 5+
    teampilot-agent-gemini/             # Spec 6+
    teampilot-agent-codebuddy/          # Spec 7+
    teampilot-agent-antigravity/        # Spec 8+
    teampilot-agent-qoder/              # Spec 9
    teampilot-agents-bundle/            # name: teampilot_agents_bundle（运行时注册，app 依赖）
    teampilot-agents-builder/           # name: teampilot_agents_builder（构建期生成器）
```

`teampilot-agents-bundle/`：

```
pubspec.yaml          # dependencies: teampilot_agent_api + 9 个 agent 包 path 依赖
build.yaml            # targets.$default.builders 启用 teampilot_agents_builder|agent_aggregator
lib/agent_manifest.dart       # 手写：@AgentManifest 标注 + 每个 agent barrel 一行 import
lib/register_all.g.dart       # 生成物，提交 git
```

### 4.2 依赖方向

```
teampilot (app)
  ├── teampilot_common            # 运行时
  ├── teampilot_agent_api         # 运行时
  ├── teampilot_agents_bundle     # 运行时
  └── teampilot_agents_builder    # dev_dependencies（构建期）
teampilot_agents_bundle → teampilot_agent_api + 全部 teampilot_agent_*
teampilot_agent_*       → teampilot_agent_api（+ 可选 teampilot_common）
teampilot_agent_api     → teampilot_common（+ 最小 flutter/widgets.dart）
```

**修正记录**：初版把 builder 挂在 bundle 的 `dev_dependencies` 下。pub 不会把 path 依赖的 dev_deps 暴露到根包 `package_config.json`，从 `client` 跑 `build_runner` 会加载不到 Builder。因此 builder 必须是 **`client/pubspec.yaml` 的 `dev_dependencies`**；bundle 的 `build.yaml` 只引用 builder key，不必依赖它。这仍是 dev 依赖，不进 app 运行时。

app 的依赖仍是 3 个运行时包 + 1 个构建期 dev 包，且 app 源码不 import 任何 `teampilot_agent_*`。

### 4.3 命名

目录名用连字符（沿用用户指定），`pubspec.yaml` 的 `name` 用下划线（Dart 包名不允许连字符）：`teampilot-agent-claude` → `teampilot_agent_claude`，`teampilot-agents-bundle` → `teampilot_agents_bundle`，`teampilot-agents-builder` → `teampilot_agents_builder`。

## 5. 契约层

### 5.1 `teampilot-common`（纯 Dart、零 Flutter）

- `AgentId`：不透明值类型，`const AgentId(String value)` + `==` / `hashCode` + JSON 编解码 + 格式校验（非空、小写、`[a-z0-9_-]`）。**没有 `values`，没有任何具体 agent 常量**——这是 D3 的类型基础。
- 纯数据类型下沉：`AppProviderConfig`、`CliPreset`、`CredentialActionResult`、`CredentialLinkResult`、`CredentialProbe`、`HookEntry`、`McpServerSpec`、`SessionUsage` 等 9 个 `models/`，以及 `agent_status/`、history 上下文、resource contribution 等纯数据类与引擎。Spec 1 用一行 `export 'package:teampilot_common/models/app_provider_config.dart';` 兼容旧相对 import 路径；Spec 10 统一改写并删除 facade。
- 不含 `models/team_config.dart`：`CliTool` 在 Spec 1 仍是过渡枚举，留 app。
- 跨 CLI 共享实现（flashskyai / qoder / codebuddy / cursor 复用的 claude history、mcp、hook writer）下沉到 common 的 `claude_family/` 一类共享目录，禁止 agent 包之间互相 import。

### 5.2 `teampilot-agent-api`

- `AgentRegistry`：`Map<AgentId, AgentDefinition>` 开放注册；`register` / `tryGet` / `capability<T>(id)` / `capabilitiesOf<T>` / `all` / `launchable` / `withCapability<T>` / `defaultId`。重复 id 立即 `StateError`。**不提供 `values`、不提供封闭集合**，替换 `built_in_cli_tools.dart:165-205` 里基于 `CliTool.values` 的全量 assert 校验。
- `@TeampilotAgent(id, displayName, icon)`：const 注解，标在 `AgentDefinition` 实现类上。
- `@AgentManifest(defaultId: 'claude')`：标在 `agent_manifest.dart` 的 `library;` 指令上，提供"默认 agent"，取代散落在 271 文件里的 `CliTool.claude` 兜底。spike 验证 resolver 能稳定读到 library 级注解。
- `AgentDefinition`：`AgentId get id` / `Iterable<AgentCapability> get capabilities` / `AgentMetadata get metadata` / `AgentUiFactory get ui`。注解类必须有 `AgentContext` 单参构造函数（builder 构建期校验）。
- `AgentContext` / `AgentPorts`：注入袋，承载宿主侧端口 + home storage + l10n，传给每个 definition 的构造函数。
- 能力接口：把现有 14+ 个 `*Capability` 接口从 `registry/capabilities/` 搬进 api。**Spec 1 沿用现有名字**（`CliCapability` 及 `*Capability` 后缀），不做全局重命名；Spec 10 统一成 `Agent*` 前缀。
- 共享引擎（launch arg assembler、resource assemblers、hook registry、shared tool-call resolvers、default capability 实现）一并搬进 api；依赖 app 运行时的共享实现（安装器、hook provisioner、prompt hub facade、provider 基础设施、workspace trust）留在 app，改由宿主侧端口注入。
- **api 最小依赖 `flutter/widgets.dart`**，只取 `Widget` / `BuildContext` 两个类型，不写 widget、不依赖 material。理由：`AgentUiFactory` 的返回值必须能被 app 直接放进 widget 树；用 `Object` 句柄 + 渲染器会把具体分支又搬回宿主。`common` 保持零 Flutter，agent 包可依赖 Flutter 实现 UI 工厂。

### 5.3 两类端口

D2（端口倒置）与 D3（零残留隔离）的交汇点：

| 类别 | 定义位置 | 实现者 | 消费者 |
|------|----------|--------|--------|
| 宿主侧端口 | api | app，`CliBootstrap` 注入 | agent 包 |
| agent 侧端口 | api | agent 包，注册进 registry | app |

宿主侧（按 claude 的 63 个 app 内部依赖归并，8 组）：

1. `AgentStorage` — home/config 路径、JSON 读写、provider/preset repository、持久化策略。
2. `AgentFileSystem` — `io/filesystem.dart` 的读写/存在性/目录遍历。
3. `AgentProcessRunner` — 一次性 CLI 执行、host/credential host runner。
4. `AgentModelCatalog` — provider 目录、凭证、表单基础设施、tool config generator、workspace trust。
5. `AgentAcpRuntime` — ACP 适配器定位、agent translator、后台 transcript。
6. `AgentHookRuntime` — glue script builder、托管 hook 供给、hook contribution providers。
7. `AgentLocalization` — 按 key 取文案（arb 为唯一来源）。
8. `AgentLogger` — `utils/logging/*`。

agent 侧：

- `AgentMetadata` — `displayName` / 图标 / hook 事件矩阵 / provider 持久化策略 / usage 归类 / transport。**取代 app 里所有 `Map<CliTool, …>` 静态表和 l10n 穷尽 switch**。
- `AgentUiFactory` — 登录弹窗、provider 表单段、credential binding 字段。33 个 Flutter UI 文件的归宿；`InteractiveCliLoginCapability` 里返回 `Widget` 的方法移到此接口。

逐文件把 63 个 app 内部依赖映射到 common（纯数据）/ api（引擎）/ 端口（服务）是实现阶段的工作项，由 `flutter analyze` 与契约测试兜底。

### 5.4 身份语义

- **不破坏隔离**：领域模型里存一个不透明 `AgentId` 作为数据（写进 JSON、显示归属）。session 总得记住自己属于哪个 agent，这是数据不是耦合。
- **破坏隔离、终态必须清零**：`CliTool.values` 当全集循环、l10n 穷尽 switch、`Map<CliTool, HookCliSupport>` 静态矩阵、`== CliTool.codex` 特判、`decode` 把未知 id 兜底成 `claude`。
- `displayName` 是品牌名（en/zh 相同），不走 l10n；UI 工厂里的可翻译文案按 D8 落在 arb。

## 6. 注册机制（2-α）

### 6.1 注解与 manifest

```dart
// teampilot-agent-claude/lib/teampilot_agent_claude.dart
export 'src/claude_agent_definition.dart';

// teampilot-agent-claude/lib/src/claude_agent_definition.dart
@TeampilotAgent(
  id: 'claude',
  displayName: 'Claude Code',
  icon: 'packages/teampilot_agent_claude/assets/claude.svg',
)
final class ClaudeAgentDefinition implements AgentDefinition {
  ClaudeAgentDefinition(this.context);

  final AgentContext context;

  @override
  AgentId get id => const AgentId('claude');

  @override
  Iterable<AgentCapability> get capabilities => buildClaudeCapabilities(context);

  @override
  AgentMetadata get metadata => const ClaudeAgentMetadata();

  @override
  AgentUiFactory get ui => const ClaudeAgentUiFactory();
}
```

`buildClaudeCapabilities(context)` 由包内实现，构造迁入后的各 capability 实例，运行时服务一律从
`context` 的宿主端口取。图标资源随 agent 包自带，在包 `pubspec.yaml` 的 `flutter.assets` 中声明，
按 `packages/teampilot_agent_claude/assets/claude.svg` 这类路径引用，不引用 app 的 `assets/` 目录。

```dart
// teampilot-agents-bundle/lib/agent_manifest.dart
@AgentManifest(defaultId: 'claude')
library;

import 'package:teampilot_agent_claude/teampilot_agent_claude.dart';
// Spec 2+ 每加一个 agent，这里加一行 import
```

### 6.2 Builder（`teampilot-agents-builder`）

- `build.yaml`：`build_extensions: {'lib/agent_manifest.dart': ['lib/register_all.g.dart']}`，`auto_apply: none`，`build_to: source`。
- bundle 的 `build.yaml` 用 `targets.$default.builders` 显式启用 `teampilot_agents_builder|agent_aggregator`。
- `build(BuildStep step)`：
  1. primary input = bundle 的 `lib/agent_manifest.dart`；
  2. `await for (final lib in step.resolver.libraries)` → 找 `@TeampilotAgent` 标注的类（manifest 已 import 各 barrel，resolver 递归爬进依赖包）；
  3. 由类的 `source.uri` 算出 `package:` import URI；
  4. 校验**静态形状**：注解字段完整、id 格式与唯一性、注解类实现 `AgentDefinition`、声明 `metadata` / `ui` getter、存在 `AgentContext` 单参构造、barrel 已导出注解类；失败即 `log.severe` 并使 build 失败，消息含包名 + id + 修复建议；
  5. 按 `id` 排序生成，保证产物确定。

运行时完整性（必需 capability 是否齐全、`AgentMetadata` 字段、`AgentUiFactory` 是否非空、每个 locale 是否有标签）无法由静态分析判定，统一由 bundle 契约测试保证（见第 10 节），不在 builder 里做不可靠的推断。

### 6.3 生成物

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:teampilot_agent_api/teampilot_agent_api.dart' as api;
import 'package:teampilot_agent_claude/teampilot_agent_claude.dart' as a0;

void registerAllAgents(api.AgentRegistry registry, api.AgentContext context) {
  registry.register(a0.ClaudeAgentDefinition(context));
}
```

生成物提交 git，因此日常 `flutter analyze` 不必先跑生成器，不破坏仓库的 fast inner loop。

### 6.4 一致性保证

- `agent_manifest.dart` 的 import 集合与 bundle pubspec 的 agent path deps 集合必须一致，由第 10 节的一致性测试校验（测试可直读文件；builder 不读 pubspec，避免非 root 包资产可见性问题）。
- CI 跑 `dart run build_runner build --delete-conflicting-outputs` 后 `git diff --exit-code -- packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart`，等价于脚本方案的 `--check`。
- 明确禁止：生成文件里 `if (id == 'claude')`、builder 用 `dart:io` 读目录或 `package_config.json`、`AgentRegistry` 提供 `values` 或封闭集合。

## 7. 数据流

```
app_shell.dart
  → HostPorts（app 实现的 8 组宿主端口）
  → AgentContext(ports, storage, l10n)
  → registerAllAgents(AgentRegistry.builtIn(), context)     # bundle 生成物
  → legacyAdapter.registerLegacy(registry, context)         # 8 个旧 CLI，过渡
  → CliToolRegistry facade 指向同一个 registry
  → 现有 ~85 个调用点零改动
```

过渡 adapter 把 8 个 `CliToolDefinition` 包成 `AgentDefinition`（`id → AgentId(cli.value)`；capabilities 原样，因为能力接口已搬进 api）。claude 的 `ClaudeBootstrapEntry` 不再需要，注入改走 `AgentContext`。

**过渡产物清单（Spec 10 全部删除）**：`CliTool` 枚举、`CliToolRegistry` facade、legacy adapter、`services/cli/claude/` 与 `services/cli/registry/` 的 re-export facade、`client/lib/models/*.dart` 的 re-export facade、`CliBootstrap` 里对应 claude 的条目。

## 8. 错误与失败模式

| 阶段 | 处理 |
|------|------|
| 构建期 | 注解字段缺失、id 非法/重复、注解类未实现 `AgentDefinition`、无 `AgentContext` 构造、barrel 未导出 → `log.severe` 并使 build 失败，消息带包名 + id + 修复建议 |
| 测试期 | 必需 capability 未注册、`AgentMetadata` 字段缺失、`AgentUiFactory` 为空、缺 locale 标签、manifest import 与 bundle pubspec path deps 不一致、生成物过期 → 契约测试 / CI `git diff --exit-code` 红 |
| 注入期 | `AgentContext` 缺端口 → `registerAllAgents` 开头 fail-fast `StateError` 列出缺失端口，不允许 null 传播到深处才崩 |
| 运行期未知 id | 持久化里的 `cli` 不是已注册 `AgentId` → `UnknownAgentException(id, 已注册列表)` 或 UI 显示"该 agent 不可用"；**禁止兜底成 claude** |
| 能力缺失 | `capability<T>` 返回 null → 走现有 no-op / 结构化 unsupported diagnostic，不静默退化成另一套 CLI 分支 |

## 9. 子项目拆分与 Spec 1 范围

整体拆为 10 个子项目，每个单独走 spec → plan → 实现：

- **Spec 1（本文的实现范围）**：claude 垂直切片，内部设两个检查点。
  - **1A**：spike → 包骨架（5 个包 + 容器）→ 契约层定义 → 最小注册链路跑通。
  - **1B**：claude 50 文件迁入包、63 个 app 内部依赖改走 common/api/端口、3 个 Flutter UI 文件改走 `AgentUiFactory`、app 侧适配器与 import 机械改写（`registry/` 接口改 import api，约 150 文件）、过渡 facade 与 legacy adapter、全量测试。
  - 全程 `flutter analyze` + 测试保持绿；8 个 CLI 保持现状。
- **Spec 2–9**：按 claude 模板逐个迁移其余 8 个 CLI，每迁一个删对应过渡 facade / adapter 条目，跑同一套契约测试。
- **Spec 10**：删 `CliTool`、`CliToolRegistry` facade、legacy adapter 与全部 facade；271 文件 `CliTool → AgentId`、穷尽 switch / 静态 Map / `values` 循环改遍历 registry 或查 `AgentMetadata`、`decode` 去兜底、能力接口统一 `Agent*` 前缀；回填 `cli-architecture.md` / `ARCHITECTURE.md` / `AGENTS.md`。

### Spike（1A 第 0 步，时间盒、可丢弃）

用最小 throwaway 包验证三件事：

1. `step.resolver.libraries` 能看到 path 依赖包里 `@TeampilotAgent` 标注的类；
2. `dart run build_runner build` 能在**非 root** 的 path 包里生成 `build_to: source` 产物，`targets.$default.builders` 启用语法正确；
3. 生成物 import 依赖包 barrel 后能被 app 编译并注册。

三项全过才进 1B；任一不过 → 退回 2-γ（micro-package 模块 + `global_options` 清单）或方案 1（`tool/` 脚本），损失只有 spike 成本，结论与理由写回本文档。

## 10. 测试与验证

### 测试分层

- **Builder 单测**（`build_test` / `testBuilder`，内存 `MultiPackageAssetReader` 注入 fake，符合 CODE_QUALITY"不直连真实 FS/子进程"）：产出快照、id 重复/非法、注解字段缺失、未实现 `AgentDefinition`、缺 `metadata` / `ui` getter、缺 `AgentContext` 构造、排序稳定、barrel 未导出。
- **Bundle 契约测试**：注册后 id 集合 == manifest 声明、每个 agent 必备 capability 全集（把 `built_in_cli_tools.dart:208` 的 `_verifyRequired<T>` 改成遍历 registry 而非 `CliTool.values`）、metadata / 图标 / `AgentUiFactory` 非空、每个 locale 有标签、`defaultId` 已注册。
- **api 单测**：`AgentId` 等值 / JSON / 校验、`AgentRegistry` 重复注册、未知 id 抛 `UnknownAgentException`。
- **app 回归**：现有 cli 测试全绿（facade + adapter 保证）；新增用例验证 `CliToolRegistry` facade 与 `AgentRegistry` 查同一份数据、未知 id 不兜底。
- **一致性测试**：`run_tests.dart` 加一项校验 manifest import 集合与 bundle pubspec path deps 集合相等。

### CI / 验证接线

- `.github/workflows/client-verify.yml` 在 Analyze 之后加：`dart run build_runner build --delete-conflicting-outputs` + `git diff --exit-code -- packages/teampilot-agents/teampilot-agents-bundle/lib/register_all.g.dart`。
- 包级测试：扩展 `client/tool/run_tests.dart` 支持 `--package <path>`（复用同一把 `.dart_tool/run_tests.lock`，在包目录内执行），遵守 AGENTS.md"不要直接 `flutter test`"；CI 加对应 step。
- 遵守硬规则：内层 `flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件用 `dart run tool/run_tests.dart <path> --plain-name`；完成前 `flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart` 全量跑一次（后台）。
- `client/pubspec.yaml` 的 `dev_dependencies` 本来已有 `build_runner`（`:117`），无需新增；只加 `teampilot_agents_builder` 的 path dev dep。

## 11. 后续 Spec 的接口约定

每个 agent 包必须：

- pubspec 只依赖 `teampilot_agent_api`（+ 可选 `teampilot_common`）；
- `lib/<name>.dart` barrel 导出唯一带 `@TeampilotAgent` 的 `AgentDefinition` 实现类；
- 所有 app 依赖只能经 `AgentContext` 端口；
- 禁止任何以 `package:teampilot/` 开头的 import、禁止 import 其它 agent 包（交叉复用下沉到 common 共享层）；
- UI 一律经 `AgentUiFactory`。

新增 agent 的改动面：容器加一个包 + bundle pubspec 一行 path dep + `agent_manifest.dart` 一行 import + 两个 arb 补键（仅当该 agent 的 UI 工厂含需翻译文案时）+ 重新生成并提交 `register_all.g.dart`。**app 源码零改动**。

每个 Spec 的完成不变量：`flutter analyze` 绿；全量 `run_tests.dart` 绿；生成物与 manifest 一致；app 源码中新增的具体 agent 字面量为 0（过渡例外清单逐 Spec 缩短）。

## 12. 风险与缓解

| 风险 | 缓解 |
|------|------|
| `resolver.libraries` 看不到依赖包注解，或非 root 包无法生成 `.g.dart` | Spike 前置验证；失败退回 2-γ / 方案 1（D6 已记录） |
| Spec 1 的 1B 改造面大（50 文件 + 63 依赖 + ~150 import 机械改写） | 1A 先验证机制；import 改写用脚本 + `flutter analyze` 兜底；全程保持绿 |
| 过渡期双 ID（`CliTool` + `AgentId`）与 facade 被误当成永久架构 | 本文档第 7 节列出完整"过渡产物清单"，Spec 10 全删；facade 文件头标注 `TRANSITIONAL` |
| build_runner 使开发循环变慢 | 生成物提交 git，日常 `flutter analyze` 不必先跑生成器；仅改动 agent 时重新生成 |
| l10n 硬规则与"零残留"张力 | D8 明确接受一处数据性残留；`displayName` 为品牌名不走 l10n |

## 13. 已明确排除

- 运行时动态加载 Dart 包 / `dart:mirrors` / classpath 扫描。
- 保留封闭 `CliTool` 枚举并下沉到 common。
- 双层 ID（内置枚举 + 开放字符串）。
- 把容器 `teampilot-agents/` 自身做成 package。
- bundle 与 builder 合并为一个包。
- builder 用 `dart:io` 读目录或 `package_config.json` 做发现。
- 放宽 AGENTS.md 的 l10n 硬规则让包内自带翻译。
