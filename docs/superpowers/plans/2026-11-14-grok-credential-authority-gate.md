# Grok External Auth Provider — ACP Risk Gate

- 日期：2026-11-14
- grok 版本：grok 1.0.77 (50ca579fa996)
- `grok -p` 回调次数：1
- `grok agent stdio` 裸 `session/new`（无 authenticate）回调次数：0，结果：auth-required
- `grok agent stdio`（initialize → authenticate → session/new）回调次数：1
- ACP authenticate 后 `auth.json` 的 auth_mode：external
- ACP authenticate 后 `session/new` 成功：yes
- **GROK_AUTH_PROVIDER_ACP_SUPPORTED=yes**

判定：`yes` → 执行 Task 2–7 主路径；`no` → 执行 Task 5 时改用附录 B 的降级适配器，
跳过 Task 5 中「注入 GROK_AUTH_PROVIDER_COMMAND」的步骤。

## 结论说明

ACP 下 External Auth Provider 可用：本次运行在 authenticate 步骤观察到 `auth_provider_command` 被调用（1 次），其 token 以 `auth_mode: "external"` 写入 ACP home 的 `auth.json`，随后 `session/new` 成功=yes。裸 `session/new`（无 authenticate）回调 0 次，本次返回 auth-required。对 Task 5 的要求：ACP 客户端必须在 initialize 后处理认证（发送 `authenticate {"methodId":"grok.com"}`，或预置带同一 token 的 `auth.json`），否则会话创建会停在 auth-required，provider 不会被调用。

另：`grok -p` 会把 provider 换来的 token 持久化到 `auth.json`；本脚本因此为每个
探针使用独立的 `GROK_HOME` 和独立的 call log，避免 cached-token 或跨探针重试污染判定。

<details><summary>grok agent stdio stderr（authenticate 流程）</summary>

```
2026-11-14T14:40:24.215574Z ERROR failed to decode None: Invalid params
2026-11-14T14:40:30.222059Z ERROR Failed to spawn MCP server 'dart': No such file or directory (os error 2)
```

</details>
