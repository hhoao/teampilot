# CLI 仅完全访问权限设计

## 背景

TeamPilot 当前为多个 CLI 建模了通用的启动权限策略，并在会话输入框、团队配置和自动化编辑器中暴露了权限选择。当前产品实际只支持完全访问权限，因此继续展示其他策略会造成 UI、持久化模型和启动行为之间的不一致。

本设计将“CLI 是否允许用户配置启动权限”和“某个 CLI 如何把完全访问权限转换为启动参数”拆成两个独立职责，并把当前五个内置 CLI 收敛为仅支持完全访问。

## 目标

- Claude、Codex、Cursor、FlashskyAI、OpenCode 都只声明 `fullAccess` 为支持的启动权限策略。
- 所有面向用户的权限策略编辑入口都依据 CLI capability 决定是否显示；当前 CLI 不显示权限选择控件。
- 所有启动路径都从同一 capability 校验权限策略，非支持策略直接产生结构化能力错误。
- 保留各 CLI 的启动参数 provider，使完全访问参数仍由具体 CLI 自己表达。
- 删除权限策略的持久化和会话级覆盖状态，不为旧配置添加迁移、修复或兼容逻辑。
- 为未来支持其他权限策略的 CLI 保留可扩展的 capability 和通用 UI 边界，不增加按 CLI 分支。

## 非目标

- 不改变 CLI 的权限请求卡片、权限回答、hook 或终端等待行为。
- 不改变完全访问权限在各 CLI 中的具体命令行参数或 OpenCode 配置物化方式。
- 不为旧版本保存的权限字段提供迁移、回写或语义兼容。

## 架构

### 启动安全 capability

在 `services/cli/registry/capabilities/` 增加 `CliLaunchSecurityCapability`：

```dart
abstract interface class CliLaunchSecurityCapability implements CliCapability {
  bool get supportsUserConfiguration;
  Set<LaunchSecurityPolicy> get supportedPolicies;
}
```

该 capability 只描述权限策略能力，不拼接 argv，也不负责持久化。当前五个 CLI 的 definition 都必须注册它，并声明：

- `supportsUserConfiguration == false`；
- `supportedPolicies == {LaunchSecurityPolicy.fullAccess}`。

每个 CLI 的 definition 保留可注入的 capability 成员，便于未来某个 CLI 单独启用可配置策略，而无需改动页面或通用启动代码。

### 启动参数 provider

现有 Claude、FlashskyAI、Codex、Cursor、OpenCode 的 `permissionLaunch` provider 继续注册在各自 definition 中。它们只负责把已验证的 `fullAccess` 语义转换为 CLI 专属参数或配置：

- capability 决定策略是否合法、是否可由用户配置；
- `permissionLaunch` 决定合法策略如何落到 CLI；
- `CliLaunchArgAssembler` 是公共校验边界。

`CliLaunchArgAssembler` 在调用 provider 前读取 definition 中的 `CliLaunchSecurityCapability`，校验 `CliLaunchContext` 的策略属于 `supportedPolicies`。不支持的策略抛出包含 CLI、策略和能力原因的 `CliLaunchCapabilityException`，不进行静默回退。

当前所有正常构造的启动上下文都使用 `LaunchSecurityPolicy.fullAccess`。`LaunchSecurityPolicy` 保留为启动层内部语义类型，以便未来扩展 capability；它不再是用户或持久化配置模型。

## UI 与状态

### 输入框

将 `ComposeChrome` 的权限相关零散字段收敛为可选的 `ComposePermissionControl`。`WorkspaceComposeCard` 只在该模型存在时渲染现有 `ComposePermissionChip`。

各页面先从 `CliToolRegistry` 取得目标 CLI 的 `CliLaunchSecurityCapability`：

- `supportsUserConfiguration == false` 时不构造权限控制模型；
- 不在页面中通过 `if (cli == ...)` 判断；
- 现有通用 `ComposePermissionChip` 保留为未来可配置 CLI 的 UI 组件，但当前五个 CLI 不会触发它。

### 其他编辑入口

团队成员配置、工作区 Landing 团队设置和自动化编辑器中的权限策略控件统一移除或改为 capability 驱动。当前 CLI 不支持用户配置，因此这些页面不显示可编辑权限选项，也不再向提交模型写入权限策略。

### 持久化与覆盖状态

移除以下状态中的权限策略字段及相关编辑回调/覆盖逻辑：

- 团队、成员槽位和工作区 agent 配置；
- 自动化配置；
- Landing 启动上下文；
- session continue overrides；
- team/launch profile 选择器与会话 compose 状态。

相关 `toJson` 不再输出权限字段，相关 `fromJson` 不再读取这些字段；不增加 migration 或 legacy normalization。旧文件中的未知字段不属于受支持的数据契约。

## 数据流

```text
CLI definition
  ├─ CliLaunchSecurityCapability: 是否可配置、支持哪些策略
  └─ permissionLaunch: fullAccess 如何表达
          │
用户输入 / 自动化 / SSH / PTY / 预览
          │
          ▼
     CliLaunchContext(fullAccess)
          │
          ▼
  CliLaunchArgAssembler 校验 capability
          │
          ├─ 合法：调用 CLI-specific permissionLaunch
          └─ 非法：CliLaunchCapabilityException
```

任何调用方都不能通过绕过 UI、传入旧状态或直接构造上下文来使用当前 CLI 不支持的权限策略。

## 错误处理

- capability 缺失或策略不在支持集合中：启动装配阶段抛出结构化 `CliLaunchCapabilityException`。
- 页面找不到 capability：视为 CLI definition 注册错误，由 registry 契约测试和断言暴露，不回退到通用权限菜单。
- 用户可见的启动失败继续沿用现有 l10n 与 cubit 状态；诊断信息使用 `AppLogger`，不使用 `print`。

## 测试与验收

### Registry 与启动层

- 遍历所有内置 CLI，断言都注册 `CliLaunchSecurityCapability`。
- 断言五个 CLI 均为不可配置且只支持 `fullAccess`。
- 对每个 CLI 验证 `fullAccess` 的现有 argv/配置输出不变。
- 对每个 CLI 传入非支持策略，断言抛出包含 CLI 和策略信息的 `CliLaunchCapabilityException`。

### 模型与页面

- 团队、成员、工作区 agent、自动化和 session continue 的新序列化结果不包含权限字段。
- Landing 与 History continue compose 在当前 CLI 下不渲染 `ComposePermissionChip`。
- 团队配置和自动化编辑器不再提供权限策略编辑控件。
- 保留的通用权限 chip 单独覆盖未来 capability 允许配置时的选项生成行为。

### 验证命令

按仓库要求执行：

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart <定向测试路径或选项>
cd client && dart run tool/run_tests.dart
```

完整测试套件只在实现完成、定向测试通过后执行一次。
