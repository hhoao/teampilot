# Grok / Cursor / X 用量查询预设 设计文档

日期：2026-11-10

## 目标

为 Managed Provider（用量与额度）增加一条内置预设，查询 The X Subscription 合一后的 grok.com dashboard：周额度已用百分比、下次重置时间、预付费余额。凭据复用该条目自己的 Cursor CLI 登录态。现有 Cursor 预设保持不变。

## 背景与已确认事实

- 现有内置预设（Codex、Claude Code、Cursor、CodeBuddy、DeepSeek、OpenCode Go）都通过 `ManagedProviderPreset` + `ManagedProviderUsageAdapter` 接入。Cursor 预设打 `https://cursor.com/api/usage-summary`，Cookie 为 `WorkosCursorSessionToken={accountId}::{accessToken}`，`credentialSource` 为 `cli:cursor`。
- The X Subscription 把 Grok、Cursor、X、Grok Bot 收成一个周额度池和一份预付费，用量台账在 `https://grok.com/dashboard`。官方 Usage 页展示周池已用比例、下次重置、预付费。
- 合一账号上旧 `usage-summary` 仍可能返回 200，但 `autoPercentUsed` / `apiPercentUsed` 经常是 0。因此新增预设，而不是改 Cursor 那一条。
- 公开捕获的额度接口（CharlesDardaman/grok_widget、QuotaBar、chenyme/grok2api）：

  ```
  GET https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user
  Accept: application/json
  Origin: https://grok.com
  Referer: https://grok.com/dashboard
  x-cursor-dashboard-surface: v2
  Cookie: WorkosCursorSessionToken={accountId}::{accessToken}
  ```

  周额度在 `weeklyIncludedUsage`：`usedCents`、`budgetCents`、`resetsAt`（ISO）。百分比是 `usedCents / budgetCents * 100`。`availability` 为 `available` 时才有有效周池。响应里没有 0–100 的现成百分比，也没有美元预付费。
- 预付费是另一次 POST（QuotaBar：`get-user-prepaid-billing`）。grok.com 同源路径为：

  ```
  POST https://grok.com/dashboard/api/dashboard/get-user-prepaid-billing
  Origin: https://grok.com
  Content-Type: application/json
  Cookie: 同上
  Body: {}
  ```

  字段：`billingMode == PREPAID_BILLING_MODE_PREPAID`、`eligible == true`、`availableCents`（分，可省略表示 0）。美元 = `availableCents / 100`。
- `http-json` 不能做除法。把 `usedCents` 配成 `unit: '%'` 会把分显示成百分比。因此需要专用适配器。
- `cli:cursor` 是 intent source，编辑器会扩成该条目自己的 `cli:cursor-mp-<id>`。
- grok.com 的 dashboard API 有 Cloudflare：无 `cf_clearance` 时返回 403 HTML（`Just a moment...`），Cursor CLI 的 `WorkosCursorSessionToken` 到不了接口。cursor.com 同源 dashboard（`/api/dashboard/v2/usage-status`）对无会话返回 401 JSON，接受 Cursor 登录态。适配器把预设里的 grok.com URL 改写到 cursor.com，Cookie 按 Cursor 用量页编成 `accountId%3A%3AaccessToken`。不伪装浏览器、不带 `cf_clearance`、不发 `WorkosCursorXaiOrigin`。usage-status 的 401/403 走 `authenticationFailed`。预付费或 sand 周额度失败则省略该 measure，不让另一项一起失败。

## 需求（已确认）

1. 新快速预设，id `grok-x`，显示名 `Grok / Cursor / X`，紧插在 `cursor` 项之后。不调整其他预设的相对顺序。
2. 不修改、不迁移已有 Cursor 预设或已保存的 Cursor 用量条目。
3. 凭据只复用 Cursor CLI 登录态（`cli:cursor` → 每条目 `cli:cursor-mp-<id>`）。用户不粘贴 grok.com Cookie。
4. 展示 Weekly（`usedCents/budgetCents` 得到的 0–100 % + `resetsAt`）。预付费在 `PREPAID` 且 eligible 时展示美元余额；缺失或请求失败则只显示 Weekly。
5. 新适配器 `grok-dashboard-usage`，在 `buildDefaultManagedProviderUsageRegistry` 中注册。不改 `http-json` 的通用行为。
6. 无自定义 editor schema（与 Cursor 预设相同）。适配器忽略 `windows`。
7. 分只在适配器内部换算；快照里的 Prepaid remaining 已经是美元字符串。
8. 任何失败都不能把 Cookie、token 或响应体带进错误信息。

## 方案

### 预设

在 `managed_provider_presets.dart` 的 Cursor 项之后插入：

| 字段 | 值 |
|------|-----|
| id | `grok-x` |
| name | `Grok / Cursor / X` |
| kind | `ManagedProviderKind.subscriptionQuota` |
| adapterId | `grok-dashboard-usage` |
| schema | 不设 |
| url | `https://grok.com/dashboard/api/dashboard/v2/usage-status?scope=user` |
| method | `GET` |
| credentialSource | `cli:cursor` |
| windows | 空（适配器固定映射） |
| displayConfig | 不设 `currency`、`decimalPlaces`、`showPercent` |

Cookie 由适配器从 CLI scope 组装：`WorkosCursorSessionToken={accountId}%3A%3A{accessToken}`（与 Cursor 用量页相同），`accountId` 缺失时用 `fillAccountIdFromJwt`，仍缺则不加 `::`。

`l10n_extensions.dart`：`quickPresetGrokX` / `quickPresetGrokXHint`。

- EN label / ZH label：`Grok / Cursor / X`
- EN hint：`Query the unified weekly pool and prepaid balance with your Cursor sign-in.`
- ZH hint：`使用 Cursor 登录态查询合一后的周额度和预付费。`

### 适配器

新增 `client/lib/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart`，`id = grok-dashboard-usage`。注入 `CliCredentialSourceResolver?`。

`fetch`：

1. `cliCredentials` 为空，或 `credentialSource` 读不到 `accessToken` → `missingCredential`。
2. 校验 `endpointConfig.url`：https；host 为 `grok.com`（path `/dashboard/api/dashboard/v2/usage-status`）或 `cursor.com`（path `/api/dashboard/v2/usage-status`）；query 只能是 `scope=user`；无 userInfo、无 fragment、无非 443 端口。否则 `unsupported`，不发请求。
3. 实际 GET `https://cursor.com/api/dashboard/v2/usage-status?scope=user`。401/403 → `authenticationFailed`。其他非 2xx → `httpFailed`。非法 JSON 对象 → `responseParseFailed`。
4. 映射 Weekly（见下）。usage-status 没有周池时，再 POST `https://cursor.com/api/dashboard/get-sand-usage-status`（`{}`），用 `usagePercent` / `nextResetTimestampUtc`。sand 失败则省略 Weekly。
5. POST `https://cursor.com/api/dashboard/get-user-prepaid-billing`（`{}`）。预付费的网络/HTTP/解析失败只省略 Prepaid，不抛。
6. 没有任何 measure → `responseParseFailed`。
7. 返回 `ProviderUsageSnapshot(status: ready, fetchedAt: now, measures: …)`。

请求都带：`Accept: application/json`、`Origin: https://cursor.com`、`Referer: https://cursor.com/dashboard`、`User-Agent: TeamPilot`、`x-cursor-dashboard-surface: v2`、`Cookie: WorkosCursorSessionToken=…`。POST 另加 `content-type: application/json`。

### 数据映射

Weekly（`kind: quota`，`unit: %`）：

- 条件：顶层 `availability == "available"`，`weeklyIncludedUsage` 为对象，`usedCents` 为有限且 ≥ 0 的数（或十进制字符串），`budgetCents` 为有限且 > 0 的数（或十进制字符串）。否则回退 sand：`includedLimitZero != true`、`hasNonZeroIncludedLimit != false`，`usagePercent` 为有限且 ≥ 0 的数。
- `used` = `formatOfficialPercent(clamp(usedCents / budgetCents * 100, 0, 100))`
- `total` = `100`
- `remaining` = `formatOfficialPercent(clamp(100 - percent, 0, 100))`
- `resetsAt` = `parseOfficialResetAt(weeklyIncludedUsage.resetsAt)`，缺失则不设

Prepaid（`kind: balance`，`unit: USD`）：

- 条件：`billingMode == PREPAID_BILLING_MODE_PREPAID` 且 `eligible == true`。`availableCents` 缺失当 0。值为有限且 ≥ 0。
- `remaining` = 分/100 的美元字符串：整美元不带小数；否则两位小数。
- 不设 `resetsAt`

### 错误处理

| 情况 | 错误码 |
|------|--------|
| CLI 登录态 / accessToken 缺失 | `missingCredential` |
| URL 非 grok.com usage-status 白名单 | `unsupported` |
| usage-status 401、403 | `authenticationFailed` |
| usage-status 其他非 2xx | `httpFailed` |
| usage-status 传输失败 | `networkFailed` |
| usage-status 不是 JSON 对象，或 Weekly 与 Prepaid 都没有 | `responseParseFailed` |
| 预付费失败 | 省略 Prepaid |

### 安全约束

- Cookie 只出现在请求 header。
- 不把 Cookie、token、响应体写入日志、快照或错误信息。
- 不持久化 grok.com SSO / Cloudflare / `WorkosCursorXaiOrigin`。
- 测试夹具打码，数值用 4200/10000 分和 1250 分。

### 图标

`host == 'grok.com'` → bundled `grok`。

### 注册

`buildDefaultManagedProviderUsageRegistry` 增加 `GrokDashboardUsageAdapter(cliCredentials: cliCredentials)`，与 `HttpJsonMappingAdapter` 并列，不依赖 fs。

## 改动文件

- 新增：`client/lib/services/provider_usage/adapters/grok_dashboard_usage_adapter.dart`
- 新增：`client/test/services/provider_usage/grok_dashboard_usage_adapter_test.dart`
- 修改：`managed_provider_presets.dart`、`app_shell.dart`、`managed_provider_brand_icon.dart`、`l10n_extensions.dart`、i18n en/zh、slang 生成文件
- 修改测试：`managed_provider_presets_test.dart`、`app_shell_provider_usage_bootstrap_test.dart`、`managed_provider_brand_icon_test.dart`

## 测试

无真实网络。夹具用公开捕获的键，数值消毒。

适配器：Weekly 42% + Prepaid 12.50；请求打 cursor.com；grok.com 配置 URL 被改写；Cookie 为 `WorkosCursorSessionToken=user%3A%3Ajwt-token`；无预付费/预付费 401 只有 Weekly；usage 401 → `authenticationFailed` 且错误不含 token；非白名单 URL → `unsupported` 且无请求；budgetCents 0 且 sand/prepaid 皆空 → `responseParseFailed`；usage-status 无周池时回退 sand `usagePercent`。

预设：`grok-x` 紧跟 `cursor`，`adapterId == grok-dashboard-usage`，Cursor URL 不变。

注册：默认 registry 含 `grok-dashboard-usage`。

图标：`grok.com` → bundled `grok`。

完成前：`dart run slang`，`flutter analyze --no-fatal-infos --no-fatal-warnings`，先跑上述测试，全量套件最后后台跑。禁止直接 `flutter test`。

## 不做的事

- 不改现有 Cursor 预设。
- 不粘贴 grok.com Cookie，不发 `WorkosCursorXaiOrigin` / SSO / Cloudflare cookie。
- 不过 Cloudflare 盾。
- 不调 `query-billing-items`、`query-daily-usage`，不按产品拆分，不查 `scope=team`。
- 不改独立 Cursor 用量页。
- 不改 `http-json` 通用行为。
- 预付费失败不让 Weekly 失败。

## 风险

- grok.com Cloudflare 403 通过改写到 cursor.com 规避；不过盾、不带 `cf_clearance`。
- `usage-status` / sand / prepaid 未文档化，字段变更表现为解析失败或省略对应 measure。
- 用户若继续只用旧 Cursor 预设，合一账号仍可能看到假的 0% 月度池。
- Cookie 按 Cursor web 会话过期。
