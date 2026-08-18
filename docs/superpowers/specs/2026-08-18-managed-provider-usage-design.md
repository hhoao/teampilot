# Managed Provider 余额与额度中心设计

日期：2026-08-18

状态：已确认设计，待实现计划

## 背景

TeamPilot 当前的 Provider 配置按 CLI 分组存储在 `AppProviderConfig` 中，并服务于 Claude、Codex、OpenCode 等 CLI 的启动配置。余额、订阅额度和限额查询的生命周期不同于 CLI 启动配置：一个 Provider 可能被多个 CLI 使用，也可能暂时不与任何 CLI 关联。

本功能参考 Orca 的底部用量入口和 cc-switch 的余额/套餐模型，第一期建立独立的 Managed Provider 领域。它提供 Provider 管理、余额/额度查询、缓存和左下角摘要入口，但不修改现有 `/providers/:cli` 数据结构，也不把 Managed Provider 自动注入 CLI。

## 目标

第一期完成以下能力：

1. 管理与 CLI 无关的全局 Managed Provider。
2. 同时表达 API 金额余额、订阅额度、Token 额度、速率限制窗口等不同类型的用量。
3. 通过适配器注册表支持官方 Provider、已知特殊接口和声明式 HTTP JSON 接口。
4. 使用统一缓存和刷新协调器，保留最后一次成功结果并准确标记过期或失败。
5. 在桌面端工作区左下角提供摘要入口，在移动端提供等价的 Bottom Sheet 入口。
6. 凭据、缓存、日志和 UI 状态分层，避免敏感信息扩散。
7. 为未来的 `ManagedProvider ↔ CliTool / AppProviderConfig` 关联保留稳定边界。

## 非目标

第一期不包含：

- 修改或迁移现有 `/providers/:cli` Provider 列表；
- 将 Managed Provider 自动写入 Claude、Codex、OpenCode 或其他 CLI 配置；
- Managed Provider 与 CLI Provider 的关联 UI；
- 任意用户脚本执行；
- 支付、自动充值、账单结算或 Provider 后台管理；
- 把查询失败当作余额为零。

## 领域模型

### ManagedProvider

`ManagedProvider` 是独立于 `AppProviderConfig` 的全局实体。它不包含 `CliTool` 字段。

建议字段：

```text
id                 稳定 ID，创建后不因改名变化
name               用户可见名称
brand              展示品牌与图标元数据
websiteUrl         Provider 管理入口
kind               apiBalance / subscriptionQuota / customHttp
adapterId          查询适配器注册表中的稳定 ID
endpointConfig     适配器所需的非敏感配置
credentialRef      指向 SecretStore 的引用
displayConfig      货币、单位、小数位和显示偏好
enabled            是否参与自动刷新和状态栏摘要
createdAt
updatedAt
schemaVersion      配置版本，用于迁移
unknownFields      保留未来字段，避免降级版本丢数据
```

`ManagedProvider` 不保存 API Key、OAuth Token 或查询结果。

### ProviderUsageSnapshot

查询结果单独保存，并由 Provider ID 关联：

```text
providerId
status             loading / ready / stale / error / unsupported
measures[]
fetchedAt
staleAt
lastErrorCode
lastErrorMessage   已脱敏，可供 UI 展示
adapterVersion
```

### ProviderUsageMeasure

一个 Provider 可以返回多个 measure，例如余额和两个套餐窗口：

```text
label              例如 Balance、5h、Weekly
kind               balance / quota / token / rateLimit
total              可为空
used               可为空
remaining          可为空
unit               USD、CNY、requests、tokens 或百分比等
currency           可为空
resetsAt           可为空
```

金额使用十进制字符串或定点数值模型，禁止用二进制浮点数作为持久化金额。百分比在标准化阶段限制到 0–100，异常值转为解析错误。

### 未来关联模型

后续关联功能只新增独立模型，不改变上述实体：

```text
ManagedProviderBinding {
  managedProviderId
  cli
  appProviderId
}
```

同一个 Managed Provider 可以关联多个 CLI，也可以长期保持未关联状态。

## 持久化与凭据安全

配置和快照使用 `AppStorage` / `RuntimeContextRegistry` 的路径抽象，不使用 `Directory.current`：

```text
<teampilotRoot>/providers/managed/providers.json
<teampilotRoot>/providers/managed/usage-cache.json
```

凭据不写入上述 JSON。通过可注入的 `ManagedProviderSecretStore` 保存和读取：

- native desktop：系统 Keychain/Credential Manager；
- Android：Keystore-backed secure storage；
- WSL/SSH：由对应 RuntimeContext 提供的凭据后端；
- 测试：内存实现。

查询适配器只获得当前请求所需的凭据，页面、快照和普通日志只持有 `credentialRef`。错误日志必须脱敏 URL 查询参数、Authorization、API Key、Token 和响应中的潜在凭据。删除 Managed Provider 时删除凭据引用和对应快照；如果后端无法安全删除凭据，操作必须返回明确错误而不是静默遗留。

配置文件采用顶层 schema version 和未知字段保留策略。旧版本或损坏的配置只能导致该配置项进入恢复/错误状态，不得阻止其他 Provider 加载。

## 查询适配器

新增独立于 CLI registry 的 `ManagedProviderUsageRegistry`：

```text
ManagedProviderUsageRegistry
  ├─ OfficialSubscriptionAdapter
  ├─ KnownApiBalanceAdapter
  └─ HttpJsonMappingAdapter
```

统一接口的职责是读取一个 Provider，并返回标准化快照：

```dart
abstract interface class ManagedProviderUsageAdapter {
  String get id;

  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  });
}
```

适配器分层：

1. `OfficialSubscriptionAdapter`：处理官方订阅认证、多个时间窗口和重置时间。它通过独立的凭据来源工作，不读取 CLI Provider 列表。
2. `KnownApiBalanceAdapter`：处理已知 Provider 的特殊 Endpoint、签名或非通用返回格式。
3. `HttpJsonMappingAdapter`：处理普通中转站。配置请求方法、Endpoint、认证位置、JSON 字段路径、单位、货币和可选的套餐数组映射。

适配器不能直接更新 Cubit、路由或 Widget。新增 Provider 只需要注册元数据和适配器，不应在页面中增加 `if provider == ...` 分支。

任意脚本适配器只作为未来扩展点，第一期不执行用户提供的代码。这样既保留 cc-switch 的扩展方向，也避免把任意代码、网络权限和凭据注入同时引入客户端核心链路。

## 查询协调与状态流

新增：

- `ManagedProviderRepository`：Provider CRUD 和配置迁移；
- `ManagedProviderUsageRepository`：快照持久化、TTL 和删除清理；
- `ManagedProviderUsageCoordinator`：并发去重、刷新调度、适配器调用和错误归类；
- `ManagedProviderCubit`：管理配置状态；
- `ManagedProviderUsageCubit`：管理查询状态；
- `ManagedProviderCredentialResolver`：根据 `credentialRef` 向 SecretStore 取凭据。

状态流：

```text
AppShell 启动
  → 加载 ManagedProvider 配置
  → 加载 usage-cache
  → 左下角先渲染缓存
  → 缓存过期后 Coordinator 后台刷新
  → Adapter 查询并标准化
  → 成功：保存快照并广播
  → 失败：保留旧快照并标记 stale/error
```

一致性规则：

- 每个 Provider 同时最多一个请求；
- 全部刷新和单个刷新都经过同一个 Coordinator；
- 请求使用代次或等效的旧结果淘汰机制，旧请求不能覆盖新请求；
- Provider 被删除、禁用或凭据变更时，旧请求结果必须被忽略；
- 缓存具有明确的 `fetchedAt` 和 `staleAt`；
- 应用进入后台暂停自动轮询，恢复前台后按 TTL 判断是否刷新；
- 失败不清除最后一次成功的 measure；
- 错误分类包括 `missingCredential`、`authenticationFailed`、`networkFailed`、`httpFailed`、`responseParseFailed` 和 `unsupported`。

## UI 与路由

### Provider 管理页

新增全局 Managed Provider 管理视图，例如 `HomeGlobalView.managedProviders`，保留现有 `HomeGlobalView.providers` 的 CLI Provider 页面不变。

管理页包含：

- Provider 列表：名称、品牌、类型、凭据状态、余额状态、最后更新时间；
- 新增/编辑表单：基本信息、认证方式、适配器、Endpoint、展示单位；
- 声明式 HTTP JSON 的字段映射编辑器；
- 测试查询按钮；
- 单个 Provider 刷新、启用/禁用和删除；
- 跳转 Provider 官网；
- 查询失败时显示错误分类和重新配置入口。

测试查询只更新内存结果，保存成功后才写入配置和缓存；已保存的配置即使测试暂时失败也可以保留，但必须显示明确的错误状态。

### 左下角摘要入口

扩展 `WorkspaceStatusBar` 为左右两组：

```text
leadingItems  → Managed Provider Usage
trailingItems → Progress / Resource / SSH
```

新增 `ManagedProviderUsageStatusItem`：

- 一个 Provider：显示图标和主要余额/额度；
- 多个 Provider：显示图标组和 Provider 数量；
- 有 stale/error：显示警告点，但仍显示最后一次成功值；
- 无 Provider：显示添加入口；
- 点击打开约 360px 的 Usage Popover；
- Popover 顶部提供全部刷新和进入管理页；
- 每行显示 Provider、measure、进度条或金额、重置时间、更新时间和状态；
- 点击行进入 Managed Provider 详情；
- 桌面端使用 `TpPopover`，移动端使用 Bottom Sheet；
- 移动端没有桌面状态栏时，从 Home Sidebar/Footer 提供同一个 launcher。

状态栏只负责摘要、刷新和导航，不执行 HTTP 请求。它依赖 AppShell 级别的 `ManagedProviderUsageCubit`，切换工作区不会重复创建查询状态。

## 测试策略

### Model 与 Repository

- JSON 往返、schema migration、未知字段保留；
- 金额字符串和百分比边界；
- 配置/快照损坏时的局部恢复；
- TTL、删除清理和禁用 Provider；
- 快照中不出现凭据字段。

### SecretStore 与安全

- 引用解析和后端替换；
- 删除行为和删除失败；
- 日志、异常和 URL 脱敏；
- UI 只显示掩码后的凭据状态。

### Adapter 与 Coordinator

- 官方订阅、多窗口套餐和重置时间；
- HTTP JSON 成功、认证失败、网络失败、非 JSON、字段缺失和多个套餐；
- 并发去重、刷新代次、旧结果淘汰；
- 失败保留最后一次成功快照；
- Provider 删除/凭据变更后的结果一致性。

### Cubit、Widget 与集成

- 启动加载缓存、手动刷新、增删改后的状态同步；
- 左下角摘要、Popover/Bottom Sheet、空状态、stale/error、刷新按钮；
- 新增 Provider → 测试查询 → 保存 → 重启后恢复缓存；
- 中英文文案和桌面/移动布局。

## 验收标准

用户可以在独立的 Managed Provider 页面配置一个余额或额度查询。查询成功后，桌面左下角能展示摘要，打开面板能看到标准化详情、更新时间和刷新状态。网络或认证失败时，界面保留最后成功值并显示错误状态，而不是显示 0。应用重启后能先显示持久化快照。整个流程不依赖当前使用哪个 CLI，也不会修改现有 CLI Provider 列表。

