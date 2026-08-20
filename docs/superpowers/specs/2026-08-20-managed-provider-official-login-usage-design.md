# Managed Provider 官方登录、卡片与用量查询设计

日期：2026-08-20

状态：已确认（延续 2026-08-18 用量中心，补齐官方 Codex / Claude 登录与查询）

## 背景

第一期建立了独立的 Managed Provider 领域，但官方 Codex / Claude 预设只能改名称，凭据提示去 Providers 设置登录，查询客户端是 fail-closed 占位。用户需要在本页完成与 CLI Provider 相同的登录/导入，列表卡片不能暴露内部 ID，查询应对齐 cc-switch / Orca 已验证的官方接口。

## 目标

1. 官方 Codex / Claude 编辑页复用现有 `ProviderCredentialActionBar`（登录、从全局导入、导入文件、退出）。
2. 列表卡片两行排版：名称 + 启用徽章；操作右对齐不换行；副标题为本地化 kind + 可读名称，不出现 adapter id。
3. 查询时按 cc-switch / Orca 调用官方用量 HTTP，映射到现有 `ProviderUsageSnapshot` 窗口。
4. 官方凭据不写入 Managed Provider JSON / SecretStore。

## 非目标

- Gemini、Copilot、自定义 usage_script、Token Plan 模板。
- 在查询路径扫描全部 `AppProviderConfig` 列表做匹配。
- OAuth refresh / keychain 专用读取（第一期只读登录/导入写入的凭据文件）。
- 修改 `/providers/:cli` 数据结构，或把 Managed Provider 自动注入 CLI。

## 官方登录

| Managed 预设 | 适配器 ID | CLI Provider 行 |
|---|---|---|
| Codex | `official-codex-subscription` | `CliTool.codex` / `openai-official` |
| Claude Code | `official-claude-subscription` | `CliTool.claude` / `claude-official` |

进入官方预设编辑页时：若对应官方 Provider 行不存在，用内置 preset 模板 `upsert` 创建，再展示 `ProviderCredentialActionBar`。登录/导入走现有 `AppProviderCubit.runProviderCredentialAction`。凭据仍写到 CLI 凭据文件（Claude `.credentials.json`、Codex `auth.json`），不复制进 Managed Provider。

DeepSeek / 自定义 HTTP 保持 API Key 表单，不变。

## 列表卡片

```text
[icon]  Name                    [Enabled]   [pause] [edit] [delete]
        本地化 kind · 可读名称
        用量行（现有 MeasureView）
```

- 标题行不换行：名称可 ellipsis；三个 IconButton 固定在右侧。
- 副标题禁止 `subscriptionQuota · official-codex-subscription` 这类内部值。
- kind 文案走 l10n：`apiBalance` / `subscriptionQuota` / `customHttp`。

## 官方查询

查询边界仍是 `OfficialSubscriptionAuthReader` + `OfficialSubscriptionClient`。生产环境替换 `_Unavailable*` 占位。

### 凭据读取（不扫 Provider 列表）

只读已知官方凭据文件，按顺序取第一个可用 access token：

| CLI | 优先（TeamPilot 隔离目录） | 回退（全局 CLI home） |
|---|---|---|
| Claude | `<teampilotRoot>/providers/claude/claude-official/.credentials.json` | `~/.claude/.credentials.json` |
| Codex | `<teampilotRoot>/providers/codex/openai-official/auth.json` | `~/.codex/auth.json` |

- Claude：`claudeAiOauth.accessToken` 非空。
- Codex：`tokens.access_token` 非空；可选 `tokens.account_id`。若存在 `auth_mode` 且不是 `chatgpt`，跳过该文件。
- 缺失 → `missingCredential`。错误与日志不得包含 token。

### HTTP（对齐 cc-switch / Orca）

**Claude**

- `GET https://api.anthropic.com/api/oauth/usage`
- `Authorization: Bearer <accessToken>`
- `anthropic-beta: oauth-2025-04-20`
- `Accept: application/json`
- `User-Agent: claude-code/2.1.0`

窗口：`five_hour` / `seven_day` / `seven_day_opus` / `seven_day_sonnet`（及同形未知窗口）。`utilization` 为 0–100 已用百分比。`resets_at` 转为毫秒。展示标签：`5h` / `Weekly` / `Weekly Opus` / `Weekly Sonnet`。

**Codex**

- `GET https://chatgpt.com/backend-api/wham/usage`
- `Authorization: Bearer <accessToken>`
- `User-Agent: codex-cli`
- `Accept: application/json`
- 有 account id 时加 `ChatGPT-Account-Id`

窗口：`rate_limit.primary_window` / `secondary_window` 的 `used_percent`。`limit_window_seconds`：18000→`5h`，604800→`Weekly`，2592000→`30d`。`reset_at` 为秒则转毫秒。

成功窗口写入 `ProviderUsageMeasure`：`kind=quota`，`used` 为百分比字符串，`total=100`，`unit=%`。空窗口 → `responseParseFailed`。401/403 → `authenticationFailed`。其它非 2xx → `httpFailed`。传输失败 → `networkFailed`。

DeepSeek HTTP JSON 余额查询不变。

## 测试

- 绑定：adapter → CLI Provider id / 模板；缺失时创建官方行。
- 编辑页：Codex/Claude 显示登录条，无 API Key；DeepSeek 仍为密钥字段。
- 卡片：副标题无 adapter id；操作行是不换行 Row。
- Auth reader：隔离文件优先于全局；缺 token / 非 chatgpt 模式失败且无密钥泄漏。
- Client：固定 JSON fixture 映射窗口；401/非法 JSON 为类型化错误。
