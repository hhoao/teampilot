# Grok 控制面凭证权威设计

- 日期：2026-11-14
- 状态：待审阅
- 来源：会话 `16a52ff1-d8a8-4c5a-9a04-ded18aff53ff` 中 grok 报「代理尚未登录」。根因是 xai provider 的 OAuth refresh token 被复制到每个隔离会话，其中一个会话刷新后 IdP 轮换 RT，其余会话拿到 `invalid_grant: Invalid or unknown refresh token`，grok 判定永久失败并清空 `auth.json`。用户要求按「最好的架构与可扩展性」根治，不考虑向下兼容。
- 范围：**只做 grok 的完整方案（本机 + SSH 远程）**；跨 CLI 公共层只预留接口，不实现其他 CLI 适配器。
- 关联现状：
  - `client/lib/services/cli/grok/provider/grok_auth_store.dart`：provider store ↔ 会话 home 的 `auth.json` 复制与 `.grok-provider` marker
  - `client/lib/services/cli/grok/capabilities/provider.dart:189`：`probe` 仅判断文件非空
  - `client/lib/services/cli/grok/capabilities/provider.dart:323`：`materializeSessionHome` 下发 `GROK_HOME` / `XAI_API_KEY`
  - `client/lib/services/cli/grok/capabilities/acp.dart:94`：`buildEnvironment` 注入 ACP 进程 env
  - `client/lib/services/cli/grok/provider/grok_login_dialog.dart`：隔离 `grok login --device-auth` 终端
  - `client/lib/services/cli/grok/grok_toml.dart:28`：`mergeGrokTomlSection`（可写 `[auth]` 表）
  - `client/lib/services/cli/grok/grok_constants.dart`：缺 auth provider 相关常量
  - `client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart:198`：`_onRequest` 显式路由链，loopback `:0`
  - `client/lib/services/catalog/catalog_mcp_transport.dart:32`：远程 `idleHttpTunnelPort` 反向隧道 + `X-Bus-Token`
  - `client/lib/services/chat/team_bus/remote/member_bus_mcp_config.dart:8`：`RemoteBusBinding`
  - `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart:620`：`auth_required` 直接 `_endWith` 终态
  - `client/lib/services/provider/credential_binding.dart:6`：Claude `linked` 绑定（本设计不采用，见「风险与取舍」）
  - `runtime/grok/docs/user-guide/02-authentication.md:106`：grok External Auth Provider 扩展点

## 结论

把 OAuth 凭证从「复制到每个会话的静态文件」升级为 **控制面单点持有的可刷新凭证 + 会话按需领取的短期 lease**：

1. **不变量**：每个 `(cli, providerId)` 有且仅有一个 refresh token 的所有者（`OAuthCredentialAuthority`）。会话永远拿不到 RT。
2. **会话只领 lease**：`CredentialLease { accessToken, expiresAt }`。grok 通过其官方 `GROK_AUTH_PROVIDER_COMMAND` 扩展点在缺凭证 / 临期 / 401 时回调 TeamPilot 的 shim，shim 向控制面 HTTP 端点取 lease。
3. **刷新只在控制面发生**：single-flight 锁 + generation 计数，串行化所有 refresh；`invalid_grant` 只在一个地方被判定。
4. **跨机复用既有隧道**：端点挂在 `TeammateBusMcpGateway` 上，远程经 `idleHttpTunnelPort` + `X-Bus-Token` 访问，不新建通道。
5. **`auth_required` 可恢复**：先强制刷新 lease 并重连，只有 Authority 判定 `RefreshTokenRejected` 才提示重新登录。
6. **不再有会话级 `auth.json` seed**：`GrokAuthStore.seedSessionAuth` 与 `.grok-provider` marker 整套退役；按 External Auth Provider 的 JSON 契约（`access_token` + `expires_in`，不含 `refresh_token`），grok 自己写入的 `auth.json` 只含 access token，不构成共享状态。

不保留 provider store 的 `auth.json` 双轨、不保留 marker 协调、不保留「会话刷新结果保留在会话内」的语义。

## 目标

- 任意数量并发会话（含同一 provider 的多个 seat）不再因 RT 轮换互相击穿。
- SSH / Android 远程会话与本机行为一致。
- 凭证健康状态（就绪 / 临期 / 已失效）在 UI 与启动期准确反映，而不是看文件是否存在。
- 新增一个需要可刷新凭证的 CLI 时，只需实现一个适配器 + 一个注入方式，不改动控制面、gateway、cubit。

## 非目标

- 不实现 claude / codex / cursor / opencode / qoder 等 CLI 的适配器；只定义接口。
- 不修改 grok CLI 本身，不 fork 其认证逻辑。
- 不改变 `XAI_API_KEY` 路径：API key 不轮换、无共享状态问题，维持 `provider.dart:357` 现有行为。
- 不引入新的持久化数据库；凭证仍以文件形式落在控制面 provider 目录。
- 不做向后兼容层；已有 provider store `auth.json` 通过一次性导入进入 Authority。

## 术语

| 术语 | 定义 |
|------|------|
| Authority | 控制面 `OAuthCredentialAuthority`，唯一持有 RT 的组件 |
| Lease | `{ accessToken, expiresAt, epoch }`，从 RT 派生、可短期复用、不轮换 |
| Shim | 落在会话工具目录的极小脚本，grok 通过 `sh -c` 调用，向端点取 lease 并输出到 stdout |
| Work plane | 会话实际运行的机器（本机 PTY 或 SSH 远端） |
| Control plane | TeamPilot 应用所在机器，持有 Authority 与 HTTP gateway |
| Generation / epoch | 每次成功刷新递增的单调计数，用于丢弃过期的并发刷新结果 |

## 架构

```
                      Control plane
  ┌──────────────────────────────────────────────────────────┐
  │  OAuthCredentialAuthority                                 │
  │   - providers/grok/<id>/credential.json  (RT, 0600)       │
  │   - single-flight refresh + epoch                         │
  │   - login / revoke / probe / refresh  ← 唯一入口           │
  └───────────────┬──────────────────────────────────────────┘
                  │ attach (like attachCatalogHandler)
  ┌───────────────▼──────────────────────────────────────────┐
  │  TeammateBusMcpGateway  (127.0.0.1:<port>)                │
  │   POST /credentials/lease   X-Session / X-Bus-Token       │
  └───────┬───────────────────────────────┬──────────────────┘
          │ loopback (local seat)          │ idleHttpTunnelPort (remote seat)
  ┌───────▼────────────┐         ┌────────▼──────────────────┐
  │ Work plane: local   │         │ Work plane: SSH / Android  │
  │  GROK_HOME/         │         │  GROK_HOME/                │
  │   credential-lease.json(0600)│         │   credential-lease.json(0600)│
  │   bin/teampilot-grok-auth    │         │   bin/teampilot-grok-auth    │
  │  env GROK_AUTH_PROVIDER_COMMAND       │  env GROK_AUTH_PROVIDER_COMMAND│
  │  grok agent stdio ──sh -c──> shim ──HTTP──> /credentials/lease │
  └────────────────────┘         └──────────────────────────┘
```

组件职责：

| 组件 | 路径 | 职责 |
|------|------|------|
| `SessionCredentialCapability`（接口，预留公共层） | `client/lib/services/cli/registry/capabilities/session_credential_capability.dart` | 声明 `leaseCredentials(SessionHomeContext)` / `onAuthRequired(sessionId)` / `credentialStatus(providerId)`；不含任何 CLI 分支 |
| `CredentialLease` / `CredentialHealth` 模型 | `client/lib/models/credential_lease.dart` | 不可变值对象 + JSON 序列化 |
| `OAuthCredentialAuthority` | `client/lib/services/provider/oauth_credential_authority.dart` | 控制面唯一 RT 持有者；登录/导入/撤销/探测/刷新；single-flight + epoch |
| `CredentialLeaseEndpoint` | `client/lib/services/provider/credential_lease_endpoint.dart` | HTTP handler：校验 `X-Session` / `X-Bus-Token`，调用 Authority，返回 lease JSON |
| `GrokCredentialAdapter` | `client/lib/services/cli/grok/provider/grok_credential_adapter.dart` | 实现 capability：写 shim + lease 配置、注入 env、拼接端点 URL |
| gateway 路由 | `client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart:198` | 在 `_onRequest` 的 `_delegates` bail-out **之前**增加 `/credentials/lease` 分支 |
| grok provider capability | `client/lib/services/cli/grok/capabilities/provider.dart` | `materializeSessionHome` 改为委托 adapter；`probe` 改为查 Authority |
| ACP chat runtime cubit | `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | `auth_required` 恢复路径 |
| 常量 | `client/lib/services/cli/grok/grok_constants.dart` | 新增 `authProviderCommandEnvKey`、`leaseConfigFileName`、`leaseEndpointPath` |

依赖方向：`cubit → capability(接口) → adapter → Authority/端口`。gateway 只依赖 `CredentialLeaseEndpoint` 接口，不反向依赖 catalog/team_bus 业务。

## 领域模型

```dart
class CredentialLease {
  final String accessToken;
  final DateTime expiresAt;
  final int epoch;          // Authority generation at mint time
}

enum CredentialHealth { ready, expiring, rejected, missing }

class CredentialState {
  final String providerId;
  final String refreshToken;      // 仅控制面内存/文件，绝不序列化到 lease
  final String accessToken;
  final DateTime expiresAt;
  final int epoch;
  final CredentialHealth health;
}
```

`CredentialState` 只在 Authority 内部；跨边界只传 `CredentialLease` 与 `CredentialHealth`。

## 存储

控制面：`<basePath>/providers/grok/<providerId>/credential.json`（沿用 `GrokAuthStore.providerAuthDir` 的目录约定，文件名改为 `credential.json` 以明确语义），权限 0600，内容含 RT、当前 access token、`expiresAt`、`epoch`。

Work plane（每个会话工具目录，每次 connect 重写）：
- `credential-lease.json`：端点 URL + per-session token，0600，**不含 access token**。
- `bin/teampilot-grok-auth`：shim 脚本（POSIX sh；Windows 用 `.cmd`，由 `HostScriptDialect` 决定，与 `GrokHookWriter` 一致）。

两者都不跨 app 重启持久化 lease；进程重启后 grok 会重新回调 shim。

一次性迁移：首次启动时若 `providers/grok/<id>/auth.json` 存在且 `credential.json` 不存在，导入为 `CredentialState`，随后删除旧 `auth.json`。导入失败（格式不符 / 已过期）视为 `missing`，走登录流程，不猜测。

## 协议

`POST /credentials/lease`

请求头：`X-Session`（或远程 `X-Bus-Token`，复用 `_resolveSessionId` 已支持的 token→session 映射）、可选 `X-Member`。

请求体：`{"providerId":"xai","forceRefresh":false}`。`forceRefresh=true` 仅由 `auth_required` 恢复路径使用。

响应：
- `200`：`{"access_token":"...","expires_in":<seconds>,"epoch":<n>}`（字段名对齐 grok External Auth Provider 的 JSON 契约）
- `401`：token 无效 / session 未注册
- `409`：`{"health":"rejected"}` —— RT 被 IdP 拒绝，客户端应转登录
- `503`：刷新暂不可用，客户端可重试一次

shim 契约（对齐 grok 文档）：
- stdout **只**输出 `{"access_token":..., "expires_in":...}`，stderr 输出诊断。
- `GROK_AUTH_EXPIRED=1` 时静默、不阻塞、几秒内返回；失败即 `exit 1`，让 grok 转入 sign-in / `auth_required`。
- 不把 token 放进 argv（避免 `ps` 泄露）；从 `credential-lease.json` 读端点与身份。

grok 注入方式（`GrokCredentialAdapter`）：
- 在 `materializeSessionHome` 里用 `mergeGrokTomlSection(section: 'auth', values: {'auth_provider_command': shimPath})` 写 `[auth]` 表；**或**通过 `SessionHomeContribution.environment` 注入 `GROK_AUTH_PROVIDER_COMMAND`。选择 env：不落盘、每个 seat 可独立、避免 config.toml 被其他逻辑覆盖。保留 config.toml 方式作为 CLI 不支持 env 时的回退。
- `GrokAcpCapability.buildEnvironment` 不再为 OAuth 路径 seed `auth.json`；`XAI_API_KEY` 路径完全不变（`provider.dart:357`）。

## 生产与所有权

- **登录**：`GrokLoginDialog` 继续在隔离 login home 跑 `grok login --device-auth`。完成后不再 `writeProviderAuthFromLogin` 写 provider store，而是解析 `<loginConfigDir>/auth.json` 交给 `Authority.importFromLogin(providerId, ...)`。`importGlobal` 同理导入到 Authority。
- **撤销**：`Authority.revoke(providerId)` 删除 `credential.json`；不触碰任何会话文件。
- **刷新**：只有 Authority 发起。single-flight：同一 provider 的并发 `lease` 请求共享一个 in-flight future；成功后 `epoch++`，丢弃任何 `epoch < 当前` 的迟到结果。
- **探测**：`GrokProviderCapability.probe` 改为经 `SessionCredentialCapability.credentialStatus(providerId)` 查询 Authority，由 Authority 解析 `expiresAt`（按 `claude_provider_credentials_service.dart:96` 的 millis/seconds 归一化思路）并区分 `ready` / `expiring` / `rejected` / `missing`。UI 的「就绪」不再来自文件大小。
- **登录态变更通知**：Authority 暴露 `Listenable` / stream，provider 列表与启动前检查订阅它；`rejected` 时主动把对应 provider 标为需登录，不再等会话失败。

## 与现有组件的迁移

| 现有 | 处理 |
|------|------|
| `GrokAuthStore.seedSessionAuth` / `authSourcePath` / `.grok-provider` marker | 删除会话复制逻辑与调用；不再有会话级凭证复制 |
| `GrokAuthStore` 的 `loginHome` / `loginConfigDir` / `loginWorkspace` | 保留（或抽到 `grok_login_paths.dart`）供 `GrokLoginDialog` 使用；类不再持有 provider 凭证读写职责 |
| `GrokAuthStore.importMachineAuth` / `writeProviderAuthFromLogin` | 迁入 Authority 的导入入口，输入仍是 login dialog 产出的 `<loginConfigDir>/auth.json` |
| `GrokProviderCapability.probe` | 改为查 Authority |
| `GrokProviderCapability.materializeSessionHome` 的 OAuth 分支（`provider.dart:361`） | 改为 `adapter.leaseCredentials(ctx)`；API-key 分支不变 |
| `GrokAcpCapability.buildEnvironment` | OAuth 路径不注入 `XAI_API_KEY`（app-wide fallback 仅服务 API-key seat），避免 lease 失效时静默降级到部署 key 而掩盖 `rejected`；API-key seat 行为不变 |
| `CrossMachineCredentialBridge` | 无需新增 grok 分支（端点走 HTTP 隧道，不复制凭证文件） |
| `AcpChatErrorKind` | 新增 `authRequired`（区别于 `launchFailed`） |
| `acp_chat_runtime_cubit.dart:620` | 改为恢复分支，见下 |

## 故障语义

1. **会话回调 shim 时 lease 正常**：grok 拿 access token，正常跑。`expires_in` 让 grok 在临期前主动重跑 shim（`GROK_AUTH_EXPIRED=1`），全程无 RT 出现在 work plane。
2. **会话报 `auth_required` (-32000)**：cubit 不再 `_endWith(launchFailed, notLoggedIn)`。改为：
   - 调 `capability.onAuthRequired(sessionId)` → Authority `lease(forceRefresh: true)`；
   - 成功 → 重新注入 / 重新 spawn agent 并重放未完成的 prompt（复用现有 launch 路径，不新增 ACP `authenticate`，grok 的 `authenticateMethodId` 保持 `null`）；
   - `rejected` → 新增 `AcpChatErrorKind.authRequired` + 已有 `chatNotLoggedIn` 文案，落 `_endWith`。
   - 恢复只尝试一次，避免循环。
3. **Authority 刷新拿到 `invalid_grant`**：标 `rejected`、清 RT、通知 UI 重新登录。**绝不把空 / 失效凭证写回任何共享文件**（防御 grok 清空 `auth.json` 的行为扩散）。
4. **端点不可达 / 超时**：shim `exit 1`，grok 转 `auth_required`；cubit 走第 2 条。远程隧道未建立时，会话启动前即告警，不静默启动一个必然失败的 agent。
5. **并发刷新**：single-flight + epoch，迟到结果被丢弃，不产生「部分会话拿到新 RT」的中间态。

## 可扩展性

- `SessionCredentialCapability` 是唯一扩展点。新增 CLI = 新增 `services/cli/<cli>/provider/<cli>_credential_adapter.dart` + 在 `CliToolDefinition` 注册，控制面、gateway、cubit 零改动。
- 对没有「外部 provider 回调」机制的 CLI，适配器可采用 **connect 时下发 access-token-only 凭证 + `auth_required` 时重连** 的次优模式，仍满足「RT 不复制到会话」的不变量；该模式在 `writing-plans` 阶段为对应 CLI 单独定义，本设计不实现。
- `CredentialLeaseEndpoint` 与 `OAuthCredentialAuthority` 不感知 CLI 类型，按 `providerId` + `cli` 索引，天然支持多 CLI / 多账号。
- 不引入 `if (cli == …)` 分支到 pages/cubits，符合 `docs/cli-architecture.md` 硬规则。

## 安全与隐私

- RT 只存在于控制面 `credential.json`（0600），永不进入 env、argv、HTTP 响应、work plane 文件、日志。
- 端点仅 `InternetAddress.loopbackIPv4`（`teammate_bus_mcp_gateway.dart:51` 现状），远程只经已认证的 SSH 反向隧道暴露。
- 每请求校验 `X-Session` / `X-Bus-Token`（复用 `_resolveSessionId` + `_registry.sessionForToken`），并校验 `providerId` 属于该会话解析出的 provider，防止跨会话取用凭证。
- `credential-lease.json` 0600，仅含端点与 token，不含 access token。
- 诊断走 `AppLogger`，绝不记录 token 明文（沿用现有 `key_prefix` 式脱敏）；用户可见错误走 l10n。
- shim 由 TeamPilot 生成、路径固定在会话工具目录，不执行用户可控内容。

## 测试

- `oauth_credential_authority_test.dart`：并发 lease 只刷新一次；epoch 丢弃迟到结果；`invalid_grant` → `rejected` 且不写空凭证；过期 lease 触发刷新；导入旧 `auth.json` 成功/失败；revoke 后 status=missing；expiresAt 的秒/毫秒归一化。
- `grok_credential_adapter_test.dart`：假 `Filesystem` 断言 `GROK_AUTH_PROVIDER_COMMAND` env、shim 与 `credential-lease.json` 落盘与 0600；API-key seat 不注入 auth provider；`config.toml [auth]` 回退写法不破坏既有 `models` / `compat` 表。
- `credential_lease_endpoint_test.dart`：token 校验（缺失/错误/跨会话 providerId）、`forceRefresh`、`rejected`→409、Simple 会话（无 TeamBus register）可用。
- `acp_chat_runtime_cubit`：`auth_required` 恢复一次成功、`rejected` 落 `AcpChatErrorKind.authRequired`、不无限重试。
- `grok_provider_capability_test.dart`：`probe` 反映 `expiring` / `rejected`，不再因文件非空报 ready。
- 远程路径：新增 `@Tags(['integration'])` 用例，走 `idleHttpTunnelPort` 取 lease（参考 `test/integration/remote_acp_prompt_docker_test.dart`）。
- 遵循 `AGENTS.md`：用 `cd client && dart run tool/run_tests.dart <paths>`，不直接 `flutter test`；`flutter analyze` 作内层循环，不跑全量套件。

## 分阶段实施

**Stage 0 — 立即解锁（不改架构）**
在设置 → 服务商 → xai 重新登录（`grok login --device-auth`），或配置 `XAI_API_KEY`。仅用于解除当前阻塞。

**Stage 1 — 安全网（可独立交付，止血）**
1. `probe` 语义化：解析 `expires_at` 与凭证结构，区分 `ready` / `expiring` / `missing`（`missing` 含空文件、缺 `key`、缺 `refresh_token`）。此阶段没有 IdP 反馈通道，尚不产生 `rejected`。
2. 启动前若 provider 凭证已过期或 `missing`，直接提示重新登录，不再让会话带着死凭证启动。
3. 会话内 `auth.json` 被 grok 清空后不把它当作可复用的凭证来源；探测与下次 launch 一律以控制面 provider store 为准。这是一条防御性约束：当前代码没有反向回写，但 Stage 2 若引入任何同步路径，也绝不把空 / 失效凭证写回控制面。
4. `auth_required` 的文案与日志明确指向「重新登录」，并区分 `RefreshTokenRejected`。

此阶段不修复并发 RT 轮换，仅消除「过期两天仍显示就绪」「会话级凭证被清空后被误判」这类可观测性缺陷，并为 Stage 2 定下「控制面为准」的语义。

**Stage 2 — 根治（Authority + grok 适配器，覆盖本机与远程）**
1. 新增模型、`SessionCredentialCapability` 接口（仅接口，无其他 CLI 实现）。
2. 实现 `OAuthCredentialAuthority`（含一次性导入、single-flight、epoch、revoke、status）。
3. 实现 `CredentialLeaseEndpoint` 并挂到 `TeammateBusMcpGateway._onRequest`（放在 `_delegates` bail-out 之前，保证 Simple 会话可用）。
4. 实现 `GrokCredentialAdapter`：shim 生成、`credential-lease.json`、env 注入、本地/远程端点 URL 选择（复用 `resolveCatalogMcpTransportConfig` 的 `RemoteBusBinding` 判定模式）。
5. 改造登录/导入/撤销入口到 Authority；删除 `GrokAuthStore` 的 seed/marker 调用。
6. `auth_required` 恢复路径 + 新 `AcpChatErrorKind`。
7. 集成测试覆盖本地与 SSH 远程。

**Stage 3（后续，不在本次范围）**
按 CLI 逐个实现适配器；公共层接口已在 Stage 2 定型。

## 风险与取舍

- **关键假设：grok External Auth Provider 是否在 `grok agent stdio`（ACP/headless）模式生效。** 上游文档以 TUI / `grok -p` 举例，未明示 ACP。Stage 2 动工前必须用真实 CLI 验证一次；若不支持，降级为「connect 时下发 access-token-only `auth.json` + `auth_required` 重连」，仍满足不变量，但需要在 Authority 侧增加「按会话下发短期凭证」的生成逻辑。此为最大风险，需先验证再写实施计划细节。
- **`GROK_AUTH_EXPIRED=1` 的几秒超时 vs SSH 隧道延迟**：shim 必须设置短超时并在超时时 `exit 1`；远程高延迟场景可能频繁触发 `auth_required`，需在集成测试中量化。
- **不采用 `linked` 绑定作为过渡**（修正上一轮讨论中的 Stage 1 设想）：把会话 `auth.json` symlink 到共享文件并共享 `auth.json.lock` 确实能让本机刷新串行化，但它需要改造 `GrokAuthStore`，而 Stage 2 会整体退役该类的 seed 逻辑，属于重复劳动；且 symlink 无法跨 SSH 边界，对 Android 无帮助。Stage 1 因此改为零架构改动的安全网。
- **会话重连语义**：恢复路径是重新 spawn agent 而非 ACP `authenticate`（grok `authenticateMethodId` 为 `null`）。重放未完成 prompt 的边界需在实施计划中明确，避免重复发送。
- **不做向后兼容**：旧 provider store `auth.json` 一次性导入后删除；用户若在旧版本与新版本间来回切换，需重新登录。已与用户确认不考虑兼容。
- **API key 与 OAuth 并存**：`provider.dart:357` 已处理「API-key seat 不继承 stale OAuth token」；新设计中 API-key seat 完全不走 Authority，保持该行为不变。

## 验收标准

第 5 条为 Stage 1 验收，其余均为 Stage 2 完成后验收。

1. 同一 xai provider 同时启动 ≥3 个会话（含并发首启），全部可用，日志中无 `invalid_grant` / `RefreshTokenRejected`。
2. 会话 A 刷新 token 后，会话 B、C 不报未登录；provider 列表中状态保持 `ready`。
3. SSH 远程会话（`RemoteBusBinding` 生效）能取到 lease 并正常完成一轮 prompt。
4. 人为让 IdP 拒绝 RT：所有会话统一进入「需登录」，无会话把空凭证写回控制面；重新登录后新建会话恢复。
5. provider 凭证过期时在**启动前**即被提示，不再出现「UI 显示就绪但会话报未登录」。
6. `flutter analyze` 通过；上述定向测试通过；不引入任何 `if (cli == …)` 到 pages/cubits。

## 待确认

1. grok External Auth Provider 在 `grok agent stdio` 下是否生效（Stage 2 前置验证，见「风险与取舍」）。
2. 远程 work plane 上 shim 的可执行位与 POSIX/Windows 方言覆盖范围（是否首版只支持 POSIX 远端）。
3. `auth_required` 恢复时未完成的 prompt 是否重放、由谁持有待重放内容（实施计划中定）。
