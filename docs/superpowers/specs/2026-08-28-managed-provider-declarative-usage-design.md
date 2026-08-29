# Managed Provider 声明式用量查询设计

日期：2026-08-28

状态：已确认（预设只填值；查询只走 `http-json`；不做旧数据兼容）

## 背景

用量中心已有声明式 `http-json`（DeepSeek：填 URL、Header、JSONPath、API Key）和三套官方专用适配器（Codex / Claude / Cursor）。专用适配器把请求、凭据读取和响应解析写死在代码里，导致不选预设就无法查询官方用量。产品要求：**引擎具备查询能力，预设只预填配置。**

## 目标

1. 所有用量查询只走 `http-json`。
2. Codex / Claude Code / Cursor / DeepSeek 预设仅为填好的 `ManagedProvider` 模板。
3. 不选预设、在自定义 HTTP 中填相同字段，查询路径与预设完全相同。
4. 凭据来源、凭据拼接、静态/模板 Header、多窗口 JSONPath 都是可编辑配置。
5. CLI 登录 token 仍不写入 Managed Provider JSON。

## 非目标

- 旧 `official-*-subscription` Provider 的加载迁移或 adapter 别名。
- 按秒数动态起窗口名、从文案里抠百分比、对象动态扫键等专用解析。
- OAuth refresh、扫描全部 `AppProviderConfig` 做匹配。
- 把 Managed Provider 注入 CLI 启动配置。
- 任意脚本 / JMESPath 表达式求值。

## 架构

```text
编辑器 / 预设模板
  → ManagedProvider.endpointConfig（非敏感）
  → HttpJsonMappingAdapter
       ├─ CredentialSourceResolver（secret | cli:<id>）
       ├─ 模板展开（Header + 凭据值）
       ├─ ProviderUsageHttpClient
       └─ windows[] 或既有 measuresPath
  → ProviderUsageSnapshot
```

删除 `ClaudeSubscriptionAdapter`、`CodexSubscriptionAdapter`、`CursorSubscriptionAdapter` 及其 official client。CLI 文件读取保留为 `credentialSource: cli:<id>` 的实现，不再按 `adapterId` 分支。

## 配置模型

在现有 `ManagedProviderEndpointConfig` 上增加：

| 字段 | 类型 | 默认 | 含义 |
|------|------|------|------|
| `credentialSource` | string | `secret` | `secret`：SecretStore（`credentialField`）。`cli:<id>`：只读已知 CLI 登录文件。 |
| `credentialTemplate` | string? | null | 凭据值模板。null 时使用 scope 里 `credentialField` 的原值。 |
| `windows` | list | `[]` | 多窗口映射。空则沿用 `measuresPath` + `fieldMappings`。 |

`headers` 的值允许同一套占位符。展开后为空的 Header 不下发。

`windows[]` 每项：

| 字段 | 含义 |
|------|------|
| `label` | 固定展示名 |
| `used` / `total` / `remaining` | JSONPath，可省略 |
| `resetsAt` | JSONPath，可省略 |
| `unit` | 如 `%` |
| `kind` | 可选，默认 `quota`（有 windows 时）或沿用 mapping 默认 |

某窗口在 used/total/remaining 上都得不到数字则跳过。全部跳过 → `responseParseFailed`。

`unit` 为 `%` 且只有 `used`（0–100）时，补 `total=100`、`remaining=100-used`（与现有官方百分比窗口一致）。

路径仍是数据路径，不求值表达式。

## 模板展开

占位符：`{accessToken}`、`{accountId}`、`{jwt.sub}`。未知占位符视为空。

`{jwt.sub}`：把 `accessToken` 当 JWT，取 payload `sub`。若 `sub` 含 `|`，只用最后一段（`github|user_01…` → `user_01…`）。解析失败视为空。

展开凭据 scope 时：若 `accountId` 为空且能解析 `{jwt.sub}`，把该值写入 `accountId`。因此 Cursor 模板始终写 `{accountId}::{accessToken}`，不必在模板里写回退。

凭据模板在替换后：去掉首尾 `:`，连续 `:` 压成单个分隔。因此 `{accountId}::{accessToken}` 在 accountId 仍为空时等于 accessToken。

展开结果为空 → `missingCredential`。日志与 `toString` 不得包含 token。

`cli:<id>` 未知，或文件里没有 token → `missingCredential`。不扫 Provider 列表。

已知 `cli:<id>`（与现有登录文件约定一致）：

| id | 优先路径 | 回退 | scope |
|----|----------|------|--------|
| `claude-official` | `<teampilotRoot>/providers/claude/claude-official/.credentials.json` | `~/.claude/.credentials.json` | `accessToken` |
| `openai-official` | `<teampilotRoot>/providers/codex/openai-official/auth.json` | `~/.codex/auth.json` | `accessToken`，可选 `accountId`；`auth_mode` 存在且非 `chatgpt` 则跳过 |
| `cursor-account` | `<teampilotRoot>/providers/cursor/cursor-account/home` 下平台 `auth.json` | 本机 Cursor `auth.json` | `accessToken`；`userId` 来自 auth.json 或同 home 的 `cli-config.json` `authInfo.userId`，写入 `accountId` |

HTTP 401/403 → `authenticationFailed`。其它非 2xx → `httpFailed`。

## 预设填值

全部 `adapterId: http-json`。kind：DeepSeek 仍为 `apiBalance`，其余为 `subscriptionQuota`。

### DeepSeek

不变：`GET https://api.deepseek.com/user/balance`，`measuresPath` + Bearer API Key，`credentialSource: secret`。

### Cursor

- URL：`https://cursor.com/api/usage-summary`，GET
- `credentialSource`: `cli:cursor-account`
- `credentialName`: `Cookie`
- `credentialTemplate`: `WorkosCursorSessionToken={accountId}::{accessToken}`（accountId 可由 CLI `userId` 或 JWT `sub` 填入）
- Header：`Accept: application/json`，`Origin: https://cursor.com`，`Referer: https://cursor.com/dashboard`
- windows（缺数跳过）：
  - Plan：`$.individualUsage.plan.totalPercentUsed`，`%`，`resetsAt` `$.billingCycleEnd`
  - Auto：`$.individualUsage.plan.autoPercentUsed`
  - API：`$.individualUsage.plan.apiPercentUsed`
  - On-demand：used `$.individualUsage.onDemand.used`，total `$.individualUsage.onDemand.limit`
  - Team：used `$.teamUsage.pooled.used`，total `$.teamUsage.pooled.limit`，`resetsAt` `$.billingCycleEnd`

### Claude Code

- URL：`https://api.anthropic.com/api/oauth/usage`
- `credentialSource`: `cli:claude-official`
- `credentialName`: `Authorization`，`credentialPrefix`: `Bearer `，`credentialField`: `accessToken`
- Header：`anthropic-beta: oauth-2025-04-20`，`Accept: application/json`，`User-Agent: claude-code/2.1.0`
- windows：`5h` ← `$.five_hour.utilization` / `$.five_hour.resets_at`；`Weekly` ← `seven_day`；`Weekly Opus` ← `seven_day_opus`；`Weekly Sonnet` ← `seven_day_sonnet`。unit `%`。

### Codex

- URL：`https://chatgpt.com/backend-api/wham/usage`
- `credentialSource`: `cli:openai-official`
- Bearer `accessToken`
- Header：`User-Agent: codex-cli`，`Accept: application/json`，`ChatGPT-Account-Id: {accountId}`（空则省略）
- windows：`5h` ← `$.rate_limit.primary_window.used_percent` / `reset_at`；`Weekly` ← `secondary_window`；`Monthly` ← `$.spend_control.individual_limit.used_percent` / `reset_at`。unit `%`。

## 编辑器与登录

预设与自定义 HTTP 使用同一套分区：basics、query、credentials、display、advanced。预设只提供 defaultValue。

`credentialSource` 以 `cli:` 开头时，凭据区展示现有 `ProviderCredentialActionBar`（登录 / 导入 / 退出）。进入编辑时若对应 CLI Provider 行不存在，用内置 CLI preset `upsert`。登录仍写 CLI 文件，不复制进 Managed Provider。

`secret` 来源继续用 API Key 字段。

品牌图标按 URL host 或名称解析（`cursor.com` → cursor，`anthropic.com` → claude，`chatgpt.com` / `openai` → openai，`api.deepseek.com` → deepseek），不再依赖 `official-*-subscription`。

## 不做兼容

删除 official 适配器、registry 注入、`OfficialManagedProviderBinding.forAdapter` 按 adapterId 的映射，以及相关测试。已保存的 `official-*-subscription` Provider 不会被迁移；用户删除后用新预设重建。

## 测试

- 模板：`{accountId}::{accessToken}` 在 accountId 空时等于 token；`{jwt.sub}` 截取 `|` 后段。
- Header `{accountId}` 为空则省略该 Header。
- `windows` 缺路径跳过；全部没有数字 → `responseParseFailed`。
- `%` 且仅 used → total 100。
- Cursor / Claude / Codex 预设配置经 `http-json` 得到与现网形状一致的窗口。
- 自定义 Provider 手填与 Cursor 预设相同的 endpoint 字段，请求与解析一致。
- `cli:` 来源未登录 → `missingCredential`，且诊断不含 secret。
- DeepSeek 行为不变。
- 编辑器：官方预设可见 query 字段；`cli:` 显示登录条，DeepSeek 仍是 API Key。

## 风险

- Cursor 无 `totalPercentUsed`、仅有 used/limit 美分时，Plan 窗口会被跳过；On-demand/Team 仍可显示。不为此加条件表达式。
- 粘贴整段 Cookie 时，把值放进密钥库并设 `credentialTemplate` 为 `{apiKey}`（或直接作 Cookie 值）即可，不必走 `cli:`。
