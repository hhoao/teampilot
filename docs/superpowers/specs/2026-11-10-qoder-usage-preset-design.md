# Qoder 余额与用量查询预设 设计文档

日期：2026-11-10

## 目标

为 Managed Provider 增加内置的 Qoder 用量预设，让用户粘贴 Qoder Personal Access Token（PAT）后，在应用内查看套餐积分、加购积分、组织资源包以及套餐到期时间。支持 Qoder Global 与 Qoder CN 两个区域。

## 背景与已确认事实

- 现有内置预设（Codex、Claude Code、Cursor、CodeBuddy、DeepSeek、OpenCode Go）都通过 `ManagedProviderPreset` + `ManagedProviderUsageAdapter` 接入。`http-json` 适配器只能发一次请求，无法完成「PAT 换 job token，再查 usage」的两步流程。
- Qoder CLI 的登录态位于 `<QODER_CONFIG_DIR>/.auth/{user,machine_id}`，内容是加密的，TeamPilot 不能像读取 Codex/Claude/Cursor 凭据那样直接拿到 bearer token，因此不复用 `cli:qoder` 凭据源。
- Qoder 官方提供 PAT（`pt-...`，在 `qoder.com/account/integrations` 或 `qoder.com.cn/account/integrations` 生成）。PAT 不能直接调 usage 接口，必须先交换成短期 job token。
- 交换接口：

  ```
  POST {openapi}/api/v1/jobToken/exchange
  Content-Type: application/json
  Accept: application/json
  User-Agent: teampilot-qoder-usage/1.0
  Cosy-Version: 1.0.1
  Cosy-ClientType: 5

  {"personal_token": "pt-..."}
  ```

  响应：`{token, refresh_token?, expires_at?, expires_in?}`。`expires_at` 为 ISO 时间字符串，`expires_in` 为毫秒。

- 用量接口：

  ```
  GET {openapi}/api/v2/quota/usage
  Authorization: Bearer {jobToken}
  Accept: application/json
  User-Agent: teampilot-qoder-usage/1.0
  ```

- 两个区域的 openapi host 不同，PAT 也不通用：
  - Global：`https://openapi.qoder.sh`
  - CN：`https://openapi.qoder.com.cn`
- usage 响应中与本功能相关的字段：

  ```json
  {
    "totalUsagePercentage": 40,
    "isQuotaExceeded": false,
    "expiresAt": 1790000000000,
    "userQuota": { "total": 3000, "used": 1200, "remaining": 1800, "unit": "credits" },
    "addOnQuota": { "total": 50, "used": 50, "remaining": 0, "unit": "credits" },
    "orgResourcePackage": { "cap": 100, "used": 10, "remaining": 90, "unit": "credits" }
  }
  ```

## 需求（已确认）

1. 提供两个快速预设：`Qoder`（Global）与 `Qoder CN`。
2. 用户只需粘贴 PAT；PAT 存入现有 managed-provider secret store，字段为 `apiKey`。
3. 展示套餐积分、加购积分、组织资源包；响应中缺失的 bucket 不显示。
4. 三个 bucket 都缺失但存在 `totalUsagePercentage` 时，退化为一个百分比用量项。
5. 不改动 `http-json` 适配器的通用行为。
6. 任何失败都不能把 PAT、job token 或响应体带进错误信息。

## 方案

### 预设

在 `client/lib/services/provider_usage/managed_provider_presets.dart` 增加两个预设：

| id | 显示名 | endpoint URL |
|----|--------|--------------|
| `qoder` | Qoder | `https://openapi.qoder.sh/api/v2/quota/usage` |
| `qoder-cn` | Qoder CN | `https://openapi.qoder.com.cn/api/v2/quota/usage` |

两个预设的共同字段：

- `kind: ManagedProviderKind.subscriptionQuota`
- `adapterId: qoder-usage`
- `endpointConfig.method: GET`
- `endpointConfig.credentialField: apiKey`
- `displayConfig.unit: credits`，`displayConfig.decimalPlaces: 2`
- `enabled: true`

两个预设各带一份自定义 editor schema（默认 `name` / URL 不同）：

- `name`（text，必填）
- `kind`（readOnly）
- `adapterId`（readOnly）
- `endpointConfig.url`（url，必填，可编辑，保留区域或未来 host 变更的逃生口）
- `endpointConfig.method`（readOnly，`GET`）
- `apiKey`（secret，必填；内容为 PAT）
- `displayConfig.unit`、`displayConfig.decimalPlaces`、`displayConfig.showPercent`
- `enabled`
- `firstQuery: true`

schema 不暴露 `endpointConfig.windows`：该适配器的字段映射是固定的，允许编辑 windows 只会造成「改了但不生效」的误导。

`l10n_extensions.dart` 增加两个 id 的 label/hint 映射：

- `quickPresetQoder` / `quickPresetQoderHint`
- `quickPresetQoderCn` / `quickPresetQoderCnHint`

hint 文案需要写明 PAT 生成页：

- EN Global：`Query plan credits with a PAT from qoder.com/account/integrations.`
- ZH Global：`使用 qoder.com/account/integrations 生成的 PAT 查询套餐积分。`
- EN CN：`Query plan credits with a PAT from qoder.com.cn/account/integrations.`
- ZH CN：`使用 qoder.com.cn/account/integrations 生成的 PAT 查询套餐积分。`

### 适配器

新增 `client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart`，实现 `ManagedProviderUsageAdapter`，`id = 'qoder-usage'`。

`fetch` 流程：

1. 通过 `credentials.resolve(provider)` 读取 `apiKey`。为空或缺失则抛 `missingCredential`。
2. 解析并校验 `provider.endpointConfig.url`：
   - 必须为 `https`；
   - host 必须精确匹配 `openapi.qoder.sh` 或 `openapi.qoder.com.cn`；
   - path 必须为 `/api/v2/quota/usage`；
   - 不允许显式非 443 端口、userInfo、query、fragment。
   - 任一不满足则抛 `unsupported`，并且不发送任何网络请求。
3. 用同一 host 拼交换地址 `https://{host}/api/v1/jobToken/exchange`，按上文 header 与 body 发 POST。PAT 只出现在 JSON body 中。
4. 解析交换响应，`token` 必须是非空字符串；缺失则 `responseParseFailed`。不持久化、不缓存 job token；每次查询重新交换。
5. 用 `Authorization: Bearer {token}` 请求配置的 usage URL。
6. 按「数据映射」构造 measures；若没有任何 measure，则 `responseParseFailed`。
7. 返回 `ProviderUsageSnapshot(status: ready, fetchedAt: now, measures: ...)`。

交换与 usage 请求都通过注入的 `ProviderUsageHttpClient` 发送，保持现有适配器的可测试边界。

### 数据映射

| measure label | used | total | remaining | 出现条件 |
|---------------|------|-------|-----------|----------|
| `Plan` | `$.userQuota.used` | `$.userQuota.total` | `$.userQuota.remaining` | `userQuota` 存在且至少有一个有限非负数值 |
| `Add-on` | `$.addOnQuota.used` | `$.addOnQuota.total` | `$.addOnQuota.remaining` | `addOnQuota` 存在且至少有一个有限非负数值 |
| `Org` | `$.orgResourcePackage.used` | `$.orgResourcePackage.cap`（缺失时用 `.total`） | `$.orgResourcePackage.remaining` | `orgResourcePackage` 存在且至少有一个有限非负数值 |
| `Usage`（兜底） | `$.totalUsagePercentage`（夹到 0–100） | `100` | `100 - percentage` | 上述三个 bucket 都不存在，且百分比是有限数值 |

- 每个 measure 的 `kind` 为 `ProviderUsageMeasureKind.quota`。
- `resetsAt` 统一取顶层 `$.expiresAt`（Unix 毫秒）。使用现有的毫秒/秒自适应解析逻辑，缺失则不设置。
- `unit` 优先取 bucket 的 `unit`；为空时取 `provider.displayConfig.unit`；再为空则用 `credits`。
- 数值转十进制字符串时，整数值不带 `.0`；不做百分比推断、不做跨 bucket 推算。
- `isQuotaExceeded` 不额外造数据，只由返回的桶值体现。

### 错误处理

| 情况 | 错误码 |
|------|--------|
| `apiKey` 缺失或空白 | `missingCredential` |
| URL 非 https / host 不在白名单 / path 不符 / 带非 443 端口、userInfo、query、fragment | `unsupported` |
| 交换接口 400、401、403 | `authenticationFailed` |
| 交换接口其他非 2xx | `httpFailed` |
| 交换响应缺少 `token` | `responseParseFailed` |
| usage 接口 401、403 | `authenticationFailed` |
| usage 接口其他非 2xx | `httpFailed` |
| 交换或 usage 响应不是合法 JSON 对象 | `responseParseFailed` |
| 响应中没有任何可映射的 measure | `responseParseFailed` |
| 传输层异常 | `networkFailed` |

错误对象只包含 `ManagedProviderUsageQueryErrorCode`，不携带 URL、凭据或响应正文。

### 安全约束

- PAT 只出现在交换请求的 JSON body；job token 只出现在 usage 请求的 `Authorization` header。
- 不把 PAT/job token 写入日志、URL、快照或错误信息。
- 交换和 usage 的 host 由预设 URL 推导并经过精确白名单校验，用户把 URL 改成任意 host 会被 `unsupported` 拒绝。
- 不在内存或磁盘缓存 job token；如果后续发现交换频率成为问题，再单独设计缓存，本次不做。

### 注册

在 `client/lib/app/app_shell.dart` 的 `buildDefaultManagedProviderUsageRegistry` 中注册 `QoderUsageAdapter()`，与现有 `HttpJsonMappingAdapter`、`CodebuddyCreditsUsageAdapter` 并列。

## 改动文件

- 新增：`client/lib/services/provider_usage/adapters/qoder_usage_adapter.dart`
- 修改：`client/lib/services/provider_usage/managed_provider_presets.dart`（两个预设 + schema）
- 修改：`client/lib/app/app_shell.dart`（注册适配器）
- 修改：`client/lib/l10n/l10n_extensions.dart`（两个预设 id 的 label/hint 映射）
- 修改：`client/lib/i18n/managedProviders_en.i18n.json`、`client/lib/i18n/managedProviders_zh.i18n.json`
- 生成：`client/lib/l10n/translations_en.g.dart`、`client/lib/l10n/translations_zh.g.dart`（`dart run slang`）
- 新增测试：`client/test/services/provider_usage/qoder_usage_adapter_test.dart`
- 修改测试：`client/test/services/provider_usage/managed_provider_presets_test.dart`

## 测试

### 适配器单测

使用记录请求的 fake `ProviderUsageHttpClient` 和返回 `{'apiKey': 'pt-test'}` 的 fake `ProviderCredentialResolver`：

1. Happy path：
   - 交换请求为 POST、Global 的正确 URL、body 为 `{"personal_token":"pt-test"}`，包含要求的 Cosy header；
   - usage 请求带 `Authorization: Bearer jt-test`，不带 Cosy header；
   - `Plan` / `Add-on` / `Org` 的 used/total/remaining、单位、`resetsAt` 正确。
2. CN 预设 URL 推导出 `openapi.qoder.com.cn` 的交换地址。
3. 非白名单 host、http、错误 path、带 query 或非 443 端口的 URL 都返回 `unsupported`，且 fake client 没有收到请求。
4. PAT 缺失 → `missingCredential`。
5. 交换接口 400/401 → `authenticationFailed`。
6. usage 接口 401 → `authenticationFailed`。
7. 交换响应缺 `token`、usage 响应非法 JSON、没有任何 bucket/百分比 → `responseParseFailed`。
8. 只剩部分 bucket 时只输出对应 measure；org 使用 `cap`。
9. 三个 bucket 都缺失但有 `totalUsagePercentage` → 输出 `Usage` 百分比 measure。
10. `expiresAt` 为毫秒数值时正确解析；缺失时不设置 `resetsAt`。
11. 错误信息不包含 `pt-test` 或 `jt-test`。

### 预设测试

扩展 `managed_provider_presets_test.dart`：

- `managedProviderPresetById('qoder')` 与 `('qoder-cn')` 存在；
- `adapterId == 'qoder-usage'`、`kind == subscriptionQuota`；
- URL 分别为两个区域的 usage 地址；
- `credentialField == 'apiKey'`；
- 快速预设选项包含两个新 id。

### 完成前验证

```bash
cd client
dart run slang
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart \
  test/services/provider_usage/qoder_usage_adapter_test.dart \
  test/services/provider_usage/managed_provider_presets_test.dart
# 最后在后台跑完整测试套件
dart run tool/run_tests.dart
```

## 不做的事

- 不复用 Qoder CLI 的加密登录态，也不解析 `~/.qoder/.auth/*`。
- 不实现 COSY 签名；usage 接口不需要。
- 不持久化或缓存 job token。
- 不支持 Organization API Key / 企业 usage API；本次只按个人 PAT 的 quota 接口实现。
- 不在预设里暴露可编辑的 windows JSON。
- 不做区域自动探测；区域由用户选择的预设决定。

## 风险

- Qoder 的交换或 usage 接口可能变更。适配器与预设隔离在独立文件中，URL 可编辑，接口变更时只需改一个适配器。
- PAT 有区域归属，用错区域的 PAT 会得到 `authenticationFailed`。两个预设的 hint 分别指向正确的生成页。
- 每次查询都做一次 PAT 交换，理论上增加一次请求。当前用量刷新频率低，先接受；若观察到限流，再设计按 host+PAT 的内存缓存。
- usage 响应可能返回 200 但带错误 envelope。未观察到该形态；当前把「无 bucket 且无百分比」视为 `responseParseFailed`，不会展示假数据。
