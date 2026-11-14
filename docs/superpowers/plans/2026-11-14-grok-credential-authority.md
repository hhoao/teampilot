# Grok 控制面凭证权威实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 grok 的 OAuth refresh token 收敛到控制面单点持有，会话只领取短期 access-token lease，彻底消除多会话 RT 轮换互相击穿与「代理尚未登录」。

**Architecture:** `OAuthCredentialAuthority` 在控制面独占 RT 并串行化刷新；`CredentialLeaseEndpoint` 挂在已有 `TeammateBusMcpGateway` 上，本地走 loopback、远程走 `idleHttpTunnelPort` + `X-Bus-Token`；`GrokCredentialAdapter` 生成 shim 并通过 `GROK_AUTH_PROVIDER_COMMAND` 让 grok 在缺凭证/临期/401 时回调取 lease；`auth_required` 从终态改为一次可恢复事件。

**Tech Stack:** Dart 3 / Flutter、`Filesystem` 抽象（`InMemoryFilesystem` 测试）、`dart:io HttpRequest`、`toml`、`CliBootstrap` 注入、`dart run tool/run_tests.dart`。

**Spec:** `docs/superpowers/specs/2026-11-14-grok-credential-authority-design.md`

## Global Constraints

- 不变量：每个 `(cli, providerId)` 有且仅有一个 refresh token 的所有者（`OAuthCredentialAuthority`）；会话永远拿不到 RT。
- RT 只存在于控制面 `credential.json`（0600），永不进入 env、argv、HTTP 响应、work plane 文件、日志。
- 绝不把空 / 失效凭证写回控制面；绝不把会话内被清空的 `auth.json` 当作可复用凭证来源。
- 不做向后兼容：旧 `providers/grok/<id>/auth.json` 一次性导入后删除；不做双轨共存。
- 所有路径经注入的 `HomeStorage` / `ConfigProfilePaths`，禁止 `Directory.current`。
- 纯 Dart 测试一律 `cd client && dart run tool/run_tests.dart <paths>`；**禁止直接 `flutter test`**。
- 内层循环用 `flutter analyze`；本计划不跑全量套件。新集成测试用 `@Tags(['integration'])`。
- 诊断走 `AppLogger`，禁止 `print`；用户可见文案复用现有 `acp.chatNotLoggedIn`，本计划不新增 l10n 文案（无需 `dart run slang`）。
- 不在 pages/cubits 里散落 `if (cli == …)`；新增能力走 `CliToolDefinition` + capability。
- 只改本计划列出的文件；**不要动工作区里无关的未提交修改**。
- 每个任务结束单独 commit，只 `git add` 该任务列出的文件。

## Ordering Note

spec 把「Stage 1 安全网」与「Stage 2 根治」分开描述。为遵守 DRY、避免把 `probe` 改两次，本计划把 Stage 1 的三项语义一次性并入 Authority 与 adapter：

- `probe` 语义化 → Task 6 直接改为查 `Authority.status()`（不再先做一版文件解析）。
- 启动前拦截 → Task 5/6 在 `leaseCredentials` 中抛出 `CredentialUnavailableException`，launch 前即失败。
- 不写回空凭证 → Task 3 的 `_markRejected` / `_persist` 保证。
- `auth_required` 文案与 `RefreshTokenRejected` 区分 → Task 7。

因此 Stage 0（重新登录 / 配 `XAI_API_KEY`）只是操作，无代码任务；Stage 1 不再有独立 commit。

---

## File Structure

### New files

| 文件 | 职责 |
|---|---|
| `client/lib/models/credential_lease.dart` | `CredentialLease`、`CredentialHealth`、`CredentialUnavailableException` |
| `client/lib/services/cli/registry/capabilities/session_credential_capability.dart` | 公共层接口（本次只定义，grok 实现） |
| `client/lib/services/provider/oauth_credential_authority.dart` | 控制面唯一 RT 持有者：导入/登录/刷新/probe/撤销 |
| `client/lib/services/provider/credential_lease_endpoint.dart` | 纯 Dart HTTP 语义 handler + 路径常量 |
| `client/lib/services/cli/grok/provider/grok_credential_adapter.dart` | grok 适配器：shim 生成、lease 配置、env 注入、端点解析 |
| `client/tool/verify_grok_auth_provider.sh` | Risk Gate 验证脚本（Task 1） |
| `docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md` | Risk Gate 结论（由脚本生成） |
| `client/test/models/credential_lease_test.dart` | 模型测试 |
| `client/test/services/provider/oauth_credential_authority_test.dart` | Authority 测试 |
| `client/test/services/provider/credential_lease_endpoint_test.dart` | Endpoint 测试 |
| `client/test/services/cli/grok/grok_credential_adapter_test.dart` | Adapter 测试 |
| `client/test/integration/grok_credential_lease_remote_test.dart` | 远程集成测试 |

### Modified files

| 文件 | 改动 |
|---|---|
| `client/lib/services/cli/grok/grok_constants.dart` | 新增 `authProviderCommandEnvKey`、`leaseConfigFileName`、`leaseShimFileName` |
| `client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart` | `_onRequest` 加 `/credentials/lease` 路由；`attachCredentialLeaseEndpoint` |
| `client/lib/app/app_shell.dart:1273` | attach endpoint 到 gateway |
| `client/lib/services/cli/grok/grok_bootstrap_entry.dart` | 新增 `authority` 字段 |
| `client/lib/app/bootstrap/cli_bootstrap_wiring.dart:125` | 构造 Authority 并放进 `GrokBootstrapEntry` |
| `client/lib/services/cli/registry/built_in_cli_tools.dart:148` | 把 Authority 传给 `GrokProviderCapability` |
| `client/lib/services/cli/grok/grok_tool.dart` | `GrokCliTool` 增加 `provider` 构造参数透传（已存在，确认 capability 列表包含新接口） |
| `client/lib/services/cli/grok/capabilities/provider.dart` | `probe` / `materializeSessionHome` / `execute` 改造 |
| `client/lib/services/cli/grok/provider/grok_auth_store.dart` | 删除 `seedSessionAuth` / `authSourcePath` / marker 逻辑 |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | 新增 `AcpChatErrorKind.authRequired` + 恢复分支 + `authRecovery` 注入 |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart:608` | 构造 cubit 时注入 `authRecovery` |
| `client/test/services/cli/grok/grok_provider_materialize_test.dart` | 断言改为 env 注入、不再 seed `auth.json` |
| `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` | `auth_required` 恢复/终态用例 |

---

## Task 1: Risk Gate — 验证 External Auth Provider 在 ACP 模式下生效

**Files:**
- Create: `client/tool/verify_grok_auth_provider.sh`
- Create: `docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md`

**Interfaces:**
- Consumes: 无
- Produces: `GROK_AUTH_PROVIDER_ACP_SUPPORTED`（`yes` / `no`），决定 Task 5 走主路径还是附录 B。

这是 spec 明确列出的最大风险：上游文档只以 TUI / `grok -p` 举例，未明示 `grok agent stdio`（ACP/headless）会回调 `auth_provider_command`。必须先验证再写实现代码。

- [ ] **Step 1: 写验证脚本**

`client/tool/verify_grok_auth_provider.sh`：

```sh
#!/bin/sh
# Verifies that grok's External Auth Provider is invoked by `grok agent stdio`
# (ACP/headless), not just by the TUI / `grok -p`.
# Usage: sh client/tool/verify_grok_auth_provider.sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT="$ROOT/docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

SHIM="$TMP/auth-provider.sh"
CALLS="$TMP/calls.log"
cat > "$SHIM" <<'EOS'
#!/bin/sh
echo "called GROK_AUTH_EXPIRED=${GROK_AUTH_EXPIRED:-unset}" >> "$CALLS"
# stdout MUST contain only the token JSON
echo '{"access_token":"probe-token","expires_in":3600}'
EOS
chmod +x "$SHIM"

cat > "$TMP/config.toml" <<EOT
[auth]
auth_provider_command = "$SHIM"
EOT

# 1) Headless one-shot: must invoke the provider.
GROK_HOME="$TMP" grok -p "say hi" >"$TMP/oneshot.out" 2>"$TMP/oneshot.err" || true

# 2) ACP stdio: send initialize + session/new, then close stdin.
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"'"$TMP"'","mcpServers":[]}}' \
  | GROK_HOME="$TMP" timeout 25 grok agent stdio >"$TMP/acp.out" 2>"$TMP/acp.err" || true

ONESHOT=$(grep -c 'called' "$CALLS" 2>/dev/null || echo 0)
# Re-run ACP alone with a fresh call log to attribute calls unambiguously.
: > "$CALLS"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"probe","version":"1"}}}' \
  | GROK_HOME="$TMP" timeout 25 grok agent stdio >"$TMP/acp2.out" 2>"$TMP/acp2.err" || true
ACP=$(grep -c 'called' "$CALLS" 2>/dev/null || echo 0)

if [ "$ACP" -gt 0 ]; then
  RESULT=yes
else
  RESULT=no
fi

cat > "$OUT" <<EOM
# Grok External Auth Provider — ACP Risk Gate

- 日期：2026-11-14
- \`grok -p\` 回调次数：$ONESHOT
- \`grok agent stdio\` 回调次数：$ACP
- **GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT**

判定：\`yes\` → 执行 Task 2–7 主路径；\`no\` → 执行 Task 5 时改用附录 B 的降级适配器，
跳过 Task 5 中「注入 GROK_AUTH_PROVIDER_COMMAND」的步骤。

<details><summary>grok agent stdio stderr</summary>

\`\`\`
$(head -40 "$TMP/acp2.err" 2>/dev/null)
\`\`\`

</details>
EOM

echo "GROK_AUTH_PROVIDER_ACP_SUPPORTED=$RESULT (wrote $OUT)"
```

- [ ] **Step 2: 运行验证**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot && sh client/tool/verify_grok_auth_provider.sh
```
Expected: 输出 `GROK_AUTH_PROVIDER_ACP_SUPPORTED=yes`（或 `no`），并生成 gate 文件。`grok` 需在 PATH 中。

- [ ] **Step 3: 记录结论并 commit**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot && grep GROK_AUTH_PROVIDER_ACP_SUPPORTED docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md
```
Expected: 一行 `yes` 或 `no`。

```bash
git add client/tool/verify_grok_auth_provider.sh docs/superpowers/plans/2026-11-14-grok-credential-authority-gate.md
git commit -m "test(grok): verify external auth provider under ACP stdio"
```

> 若结果为 `no`：不要停止整个计划。Task 5 改用附录 B（完整实现已在本计划末尾），其余任务不变。

---

## Task 2: 领域模型、公共层接口、grok 常量

**Files:**
- Create: `client/lib/models/credential_lease.dart`
- Create: `client/lib/services/cli/registry/capabilities/session_credential_capability.dart`
- Modify: `client/lib/services/cli/grok/grok_constants.dart:22-31`
- Test: `client/test/models/credential_lease_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum CredentialHealth { ready, expiring, rejected, missing }`
  - `class CredentialLease { String accessToken; DateTime expiresAt; int epoch; bool isUsable(DateTime now); int expiresInSeconds(DateTime now); String toProviderJson(DateTime now); }`
  - `class CredentialUnavailableException implements Exception { CredentialHealth health; }`
  - `abstract interface class SessionCredentialCapability implements CliCapability` 含 `leaseCredentials`、`credentialStatus`、`onAuthRequired`（签名见下）
  - `GrokConstants.authProviderCommandEnvKey = 'GROK_AUTH_PROVIDER_COMMAND'`
  - `GrokConstants.leaseConfigFileName = 'credential-lease.json'`
  - `GrokConstants.leaseShimFileName = 'teampilot-grok-auth'`

- [ ] **Step 1: 写失败测试**

`client/test/models/credential_lease_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  test('lease is usable only with a token and a future expiry', () {
    final usable = CredentialLease(
      accessToken: 'tok',
      expiresAt: now.add(const Duration(minutes: 30)),
      epoch: 3,
    );
    expect(usable.isUsable(now), isTrue);
    expect(usable.isUsable(now.add(const Duration(hours: 1))), isFalse);
    expect(
      CredentialLease(
        accessToken: '',
        expiresAt: now.add(const Duration(minutes: 30)),
        epoch: 0,
      ).isUsable(now),
      isFalse,
    );
  });

  test('toProviderJson matches grok external auth provider stdout contract', () {
    final lease = CredentialLease(
      accessToken: 'tok',
      expiresAt: now.add(const Duration(seconds: 1800)),
      epoch: 7,
    );
    expect(lease.expiresInSeconds(now), 1800);
    expect(lease.toProviderJson(now),
        '{"access_token":"tok","expires_in":1800}');
  });

  test('grok constants expose the new env key and file names', () {
    expect(GrokConstants.authProviderCommandEnvKey,
        'GROK_AUTH_PROVIDER_COMMAND');
    expect(GrokConstants.leaseConfigFileName, 'credential-lease.json');
    expect(GrokConstants.leaseShimFileName, 'teampilot-grok-auth');
  });

  test('CredentialUnavailableException carries the health', () {
    expect(
      const CredentialUnavailableException(CredentialHealth.rejected).health,
      CredentialHealth.rejected,
    );
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/credential_lease_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/models/credential_lease.dart'`。

- [ ] **Step 3: 实现模型**

`client/lib/models/credential_lease.dart`：

```dart
import 'dart:convert';

/// Fine-grained credential health. Crosses the control-plane boundary;
/// `CredentialProbe`'s binary `CredentialStatus` is derived from this.
enum CredentialHealth { ready, expiring, rejected, missing }

/// Short-lived, non-rotating credential minted for one session.
/// Contains NO refresh token.
class CredentialLease {
  const CredentialLease({
    required this.accessToken,
    required this.expiresAt,
    required this.epoch,
  });

  final String accessToken;
  final DateTime expiresAt;

  /// Authority generation at mint time; late concurrent refreshes with a
  /// lower epoch are discarded.
  final int epoch;

  bool isUsable(DateTime now) =>
      accessToken.isNotEmpty && expiresAt.isAfter(now);

  int expiresInSeconds(DateTime now) => expiresAt.difference(now).inSeconds;

  /// stdout contract for grok's external auth provider:
  /// `{"access_token": "...", "expires_in": <seconds>}`.
  String toProviderJson(DateTime now) => jsonEncode({
        'access_token': accessToken,
        'expires_in': expiresInSeconds(now),
      });
}

/// Thrown when no lease can be minted; `health` tells the caller whether to
/// prompt for a fresh login (`rejected` / `missing`) or retry.
class CredentialUnavailableException implements Exception {
  const CredentialUnavailableException(this.health);

  final CredentialHealth health;

  @override
  String toString() => 'CredentialUnavailableException($health)';
}
```

`client/lib/services/cli/registry/capabilities/session_credential_capability.dart`：

```dart
import '../../../../models/credential_lease.dart';
import '../cli_capability.dart';

/// Credential boundary for a CLI whose account token can be refreshed.
///
/// Implementations own ONLY the injection into a session; the refresh token
/// itself stays on the control plane (`OAuthCredentialAuthority`). This is the
/// extension point for future CLIs — no `if (cli == …)` in pages/cubits.
abstract interface class SessionCredentialCapability implements CliCapability {
  /// Mint (or reuse) a lease for [sessionId]. Throws
  /// [CredentialUnavailableException] when the provider needs a login.
  Future<CredentialLease> leaseCredentials({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  });

  /// Fine-grained health for provider UI and pre-launch gating.
  Future<CredentialHealth> credentialStatus(String providerId);

  /// Called on ACP `auth_required`. Returns true when a fresh lease was
  /// produced and the caller may retry the launch once.
  Future<bool> onAuthRequired({
    required String providerId,
    required String sessionId,
  });
}
```

- [ ] **Step 4: 补常量**

`client/lib/services/cli/grok/grok_constants.dart`，在 `authMarkerFileName` 后插入：

```dart
  /// grok External Auth Provider command (injected into the agent env).
  static const authProviderCommandEnvKey = 'GROK_AUTH_PROVIDER_COMMAND';

  /// Per-seat shim configuration (endpoint + token, 0600, no access token).
  static const leaseConfigFileName = 'credential-lease.json';

  /// Shim written into `<GROK_HOME>/bin/`.
  static const leaseShimFileName = 'teampilot-grok-auth';
```

- [ ] **Step 5: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/models/credential_lease_test.dart`
Expected: PASS（4 tests）。

Run: `cd client && flutter analyze lib/models/credential_lease.dart lib/services/cli/registry/capabilities/session_credential_capability.dart lib/services/cli/grok/grok_constants.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add client/lib/models/credential_lease.dart \
  client/lib/services/cli/registry/capabilities/session_credential_capability.dart \
  client/lib/services/cli/grok/grok_constants.dart \
  client/test/models/credential_lease_test.dart
git commit -m "feat(grok): add credential lease model and session credential capability"
```

---

## Task 3: OAuthCredentialAuthority（控制面唯一 RT 持有者）

**Files:**
- Create: `client/lib/services/provider/oauth_credential_authority.dart`
- Test: `client/test/services/provider/oauth_credential_authority_test.dart`

**Interfaces:**
- Consumes: `CredentialLease`, `CredentialHealth`, `CredentialUnavailableException`（Task 2）
- Produces:
  - `abstract interface class CredentialRefresher { Future<CredentialRefreshOutcome> refresh(String refreshToken); }`
  - `sealed class CredentialRefreshOutcome`；`RefreshSucceeded(accessToken, refreshToken, expiresAt)`；`RefreshRejected()`
  - `class OAuthCredentialAuthority({required Filesystem fs, required String basePath, required String cliNamespace, required CredentialRefresher refresher, DateTime Function()? now})`
  - `Future<CredentialLease> lease({required String providerId, required String sessionId, bool forceRefresh = false})`
  - `Future<CredentialHealth> status(String providerId)`
  - `Future<bool> importFromLogin(String providerId, List<int> authJsonBytes)`
  - `Future<bool> importLegacyAuthJson(String providerId)`
  - `Future<void> revoke(String providerId)`
  - `ValueListenable<Map<String, CredentialHealth>> get healthChanges`
  - `String credentialPath(String providerId)` → `<basePath>/providers/<cliNamespace>/<providerId>/credential.json`

- [ ] **Step 1: 写失败测试**

`client/test/services/provider/oauth_credential_authority_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../support/in_memory_filesystem.dart';

final class _FakeRefresher implements CredentialRefresher {
  _FakeRefresher({this.outcome, this.delay = Duration.zero});

  CredentialRefreshOutcome? outcome;
  Duration delay;
  int calls = 0;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return outcome ??
        RefreshSucceeded(
          accessToken: 'fresh-$calls',
          refreshToken: 'rt-$calls',
          expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
        );
  }
}

String _authJson({
  String key = 'access-old',
  String refreshToken = 'rt-old',
  String expiresAt = '2026-11-14T11:30:00Z',
}) =>
    jsonEncode({
      'https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828': {
        'key': key,
        'refresh_token': refreshToken,
        'expires_at': expiresAt,
        'auth_mode': 'Oidc',
      },
    });

void main() {
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  OAuthCredentialAuthority build(
    InMemoryFilesystem fs,
    _FakeRefresher refresher,
  ) =>
      OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: refresher,
        now: () => now,
      );

  test('importFromLogin parses grok auth.json and persists RT on control plane',
      () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());

    final ok = await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson()),
    );

    expect(ok, isTrue);
    final raw = await fs.readString('/tp/providers/grok/xai/credential.json');
    expect(raw, isNotNull);
    expect(raw, contains('rt-old'));
    expect(await authority.status('xai'), CredentialHealth.ready);
  });

  test('importFromLogin rejects an empty / malformed credential', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());

    expect(await authority.importFromLogin('xai', utf8.encode('{}')), isFalse);
    expect(await authority.importFromLogin('xai', utf8.encode('not json')),
        isFalse);
    expect(await authority.status('xai'), CredentialHealth.missing);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
  });

  test('concurrent leases share a single refresh (single-flight)', () async {
    final fs = InMemoryFilesystem();
    final refresher = _FakeRefresher(
      delay: const Duration(milliseconds: 20),
    );
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    final results = await Future.wait([
      authority.lease(providerId: 'xai', sessionId: 's1'),
      authority.lease(providerId: 'xai', sessionId: 's2'),
      authority.lease(providerId: 'xai', sessionId: 's3'),
    ]);

    expect(refresher.calls, 1);
    expect(results.map((e) => e.accessToken).toSet(), {'fresh-1'});
    expect(results.map((e) => e.epoch).toSet(), {1});
  });

  test('invalid_grant marks rejected, deletes RT, never writes an empty store',
      () async {
    final fs = InMemoryFilesystem();
    final refresher = _FakeRefresher(outcome: RefreshRejected());
    final authority = build(fs, refresher);
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    await expectLater(
      authority.lease(providerId: 'xai', sessionId: 's1'),
      throwsA(
        isA<CredentialUnavailableException>().having(
          (e) => e.health,
          'health',
          CredentialHealth.rejected,
        ),
      ),
    );

    expect(await authority.status('xai'), CredentialHealth.rejected);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
    expect(authority.healthChanges.value['xai'], CredentialHealth.rejected);
  });

  test('forceRefresh mints a new lease and bumps epoch', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin('xai', utf8.encode(_authJson()));

    final first = await authority.lease(providerId: 'xai', sessionId: 's1');
    final forced = await authority.lease(
      providerId: 'xai',
      sessionId: 's1',
      forceRefresh: true,
    );

    expect(first.epoch, 0);
    expect(forced.epoch, 1);
    expect(forced.accessToken, 'fresh-1');
  });

  test('importLegacyAuthJson migrates once then deletes the old file',
      () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/tp/providers/grok/xai');
    await fs.atomicWrite('/tp/providers/grok/xai/auth.json', _authJson());
    final authority = build(fs, _FakeRefresher());

    expect(await authority.importLegacyAuthJson('xai'), isTrue);
    expect(await authority.status('xai'), CredentialHealth.ready);
    expect(await fs.readString('/tp/providers/grok/xai/auth.json'), isNull);

    expect(await authority.importLegacyAuthJson('xai'), isFalse);
  });

  test('revoke removes the credential and clears rejected state', () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin('xai', utf8.encode(_authJson()));

    await authority.revoke('xai');

    expect(await authority.status('xai'), CredentialHealth.missing);
    expect(await fs.readString('/tp/providers/grok/xai/credential.json'),
        isNull);
  });

  test('expired access token with a live RT reports expiring, not missing',
      () async {
    final fs = InMemoryFilesystem();
    final authority = build(fs, _FakeRefresher());
    await authority.importFromLogin(
      'xai',
      utf8.encode(_authJson(expiresAt: '2026-11-14T10:00:00Z')),
    );

    expect(await authority.status('xai'), CredentialHealth.expiring);
  });
}
```

> 注：`InMemoryFilesystem` 的 `atomicWrite` 在文件已存在时覆盖；`revoke` 用 `fs.removeRecursive`。若 `InMemoryFilesystem.readString` 对不存在文件返回 `null`，以上断言成立（与 `grok_provider_materialize_test.dart` 用法一致）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/oauth_credential_authority_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/services/provider/oauth_credential_authority.dart'`。

- [ ] **Step 3: 实现 Authority**

`client/lib/services/provider/oauth_credential_authority.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/credential_lease.dart';
import '../io/filesystem.dart';

/// Injected IdP refresh call. Production implementation posts to
/// `https://auth.x.ai` with the stored refresh token; tests use a fake.
abstract interface class CredentialRefresher {
  Future<CredentialRefreshOutcome> refresh(String refreshToken);
}

sealed class CredentialRefreshOutcome {
  const CredentialRefreshOutcome();
}

final class RefreshSucceeded extends CredentialRefreshOutcome {
  const RefreshSucceeded({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

final class RefreshRejected extends CredentialRefreshOutcome {
  const RefreshRejected();
}

/// Control-plane single owner of refresh tokens for one CLI namespace.
///
/// INVARIANT: refresh tokens never leave this class's on-disk store. Sessions
/// receive only [CredentialLease] values. All refreshes for a provider are
/// serialized through [_inFlight] and guarded by a monotonic [epoch].
final class OAuthCredentialAuthority {
  OAuthCredentialAuthority({
    required this.fs,
    required this.basePath,
    required this.cliNamespace,
    required this.refresher,
    DateTime Function()? now,
  }) : _now = now ?? () => DateTime.now().toUtc();

  final Filesystem fs;
  final String basePath;
  final String cliNamespace;
  final CredentialRefresher refresher;
  final DateTime Function() _now;

  final Map<String, Future<CredentialLease>> _inFlight = {};
  final Set<String> _rejected = {};
  final ValueNotifier<Map<String, CredentialHealth>> _healthChanges =
      ValueNotifier<Map<String, CredentialHealth>>(const {});

  ValueListenable<Map<String, CredentialHealth>> get healthChanges =>
      _healthChanges;

  String providerDir(String providerId) => fs.pathContext.join(
        basePath,
        'providers',
        cliNamespace,
        _safe(providerId),
      );

  String credentialPath(String providerId) =>
      fs.pathContext.join(providerDir(providerId), 'credential.json');

  String legacyAuthPath(String providerId) =>
      fs.pathContext.join(providerDir(providerId), 'auth.json');

  /// Imports the `auth.json` produced by an isolated `grok login` /
  /// `importGlobal`. Returns false when it contains no usable tokens.
  Future<bool> importFromLogin(String providerId, List<int> bytes) async {
    _CredentialState? state;
    try {
      state = _parseAuthJson(providerId, utf8.decode(bytes));
    } on Object {
      return false;
    }
    if (state == null) return false;
    await _persist(providerId, state);
    _rejected.remove(providerId);
    _emitHealth(providerId, _healthOf(state, _now()));
    return true;
  }

  /// One-time migration from the pre-Authority provider store. Deletes the
  /// old file only after a successful import.
  Future<bool> importLegacyAuthJson(String providerId) async {
    final current = await fs.readString(credentialPath(providerId));
    if (current != null && current.trim().isNotEmpty) return false;
    final bytes = await fs.readBytes(legacyAuthPath(providerId));
    if (bytes == null || bytes.isEmpty) return false;
    final ok = await importFromLogin(providerId, bytes);
    if (!ok) return false;
    await fs.removeRecursive(legacyAuthPath(providerId));
    return true;
  }

  /// Throws [CredentialUnavailableException] when no lease can be minted.
  Future<CredentialLease> lease({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  }) async {
    final state = await _load(providerId);
    if (state == null) {
      throw CredentialUnavailableException(
        _rejected.contains(providerId)
            ? CredentialHealth.rejected
            : CredentialHealth.missing,
      );
    }
    if (!forceRefresh && _isUsable(state, _now())) {
      return _leaseFrom(state);
    }
    return _refreshSingleFlight(providerId, state);
  }

  Future<CredentialHealth> status(String providerId) async {
    if (_rejected.contains(providerId)) return CredentialHealth.rejected;
    final state = await _load(providerId);
    if (state == null) return CredentialHealth.missing;
    return _healthOf(state, _now());
  }

  /// Re-mints after ACP `auth_required`. Returns false when a login is needed.
  Future<bool> recover(String providerId, String sessionId) async {
    try {
      await lease(
        providerId: providerId,
        sessionId: sessionId,
        forceRefresh: true,
      );
      return true;
    } on CredentialUnavailableException {
      return false;
    }
  }

  Future<void> revoke(String providerId) async {
    _rejected.remove(providerId);
    _inFlight.remove(providerId);
    final path = credentialPath(providerId);
    if ((await fs.stat(path)).exists) await fs.removeRecursive(path);
    _emitHealth(providerId, CredentialHealth.missing);
  }

  Future<CredentialLease> _refreshSingleFlight(
    String providerId,
    _CredentialState state,
  ) {
    final existing = _inFlight[providerId];
    if (existing != null) return existing;
    final future = _doRefresh(providerId, state).whenComplete(() {
      _inFlight.remove(providerId);
    });
    _inFlight[providerId] = future;
    return future;
  }

  Future<CredentialLease> _doRefresh(
    String providerId,
    _CredentialState state,
  ) async {
    final outcome = await refresher.refresh(state.refreshToken);
    switch (outcome) {
      case RefreshRejected():
        await _markRejected(providerId);
        throw const CredentialUnavailableException(CredentialHealth.rejected);

      case RefreshSucceeded(
          :final accessToken,
          :final refreshToken,
          :final expiresAt,
        ):
        // A newer refresh already won: discard this late result.
        final current = await _load(providerId);
        if (current != null && current.epoch > state.epoch) {
          return _leaseFrom(current);
        }
        final next = _CredentialState(
          providerId: providerId,
          refreshToken: refreshToken,
          accessToken: accessToken,
          expiresAt: expiresAt,
          epoch: state.epoch + 1,
        );
        await _persist(providerId, next);
        _rejected.remove(providerId);
        _emitHealth(providerId, _healthOf(next, _now()));
        return _leaseFrom(next);
    }
  }

  /// RT was rejected by the IdP. Delete it; NEVER write an empty credential
  /// back (grok wipes its own auth.json on permanent failure).
  Future<void> _markRejected(String providerId) async {
    _rejected.add(providerId);
    final path = credentialPath(providerId);
    if ((await fs.stat(path)).exists) await fs.removeRecursive(path);
    _emitHealth(providerId, CredentialHealth.rejected);
  }

  Future<_CredentialState?> _load(String providerId) async {
    final raw = await fs.readString(credentialPath(providerId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return _CredentialState.fromDiskJson(
        providerId,
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _persist(String providerId, _CredentialState state) async {
    await fs.ensureDir(providerDir(providerId));
    await fs.atomicWrite(
      credentialPath(providerId),
      jsonEncode(state.toDiskJson()),
    );
  }

  CredentialLease _leaseFrom(_CredentialState state) => CredentialLease(
        accessToken: state.accessToken,
        expiresAt: state.expiresAt,
        epoch: state.epoch,
      );

  bool _isUsable(_CredentialState state, DateTime now) =>
      state.accessToken.isNotEmpty &&
      state.expiresAt.isAfter(now.add(const Duration(seconds: 60)));

  CredentialHealth _healthOf(_CredentialState state, DateTime now) =>
      _isUsable(state, now)
          ? CredentialHealth.ready
          : CredentialHealth.expiring;

  void _emitHealth(String providerId, CredentialHealth health) {
    _healthChanges.value = {
      ..._healthChanges.value,
      providerId: health,
    };
  }

  static _CredentialState? _parseAuthJson(String providerId, String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    for (final entry in decoded.values) {
      if (entry is! Map) continue;
      final access = entry['key']?.toString() ?? '';
      final refresh = entry['refresh_token']?.toString() ?? '';
      final expiresRaw = entry['expires_at']?.toString() ?? '';
      if (access.isEmpty || refresh.isEmpty) continue;
      final expiresAt = DateTime.tryParse(expiresRaw)?.toUtc();
      if (expiresAt == null) continue;
      return _CredentialState(
        providerId: providerId,
        refreshToken: refresh,
        accessToken: access,
        expiresAt: expiresAt,
        epoch: 0,
      );
    }
    return null;
  }

  static String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty || safe == '.' || safe == '..' ? 'provider' : safe;
  }
}

/// Private on-disk state. Never serialized across the session boundary.
final class _CredentialState {
  const _CredentialState({
    required this.providerId,
    required this.refreshToken,
    required this.accessToken,
    required this.expiresAt,
    required this.epoch,
  });

  final String providerId;
  final String refreshToken;
  final String accessToken;
  final DateTime expiresAt;
  final int epoch;

  Map<String, Object?> toDiskJson() => {
        'provider_id': providerId,
        'refresh_token': refreshToken,
        'access_token': accessToken,
        'expires_at': expiresAt.toIso8601String(),
        'epoch': epoch,
      };

  static _CredentialState? fromDiskJson(
    String providerId,
    Map<String, Object?> json,
  ) {
    final refresh = json['refresh_token']?.toString() ?? '';
    final access = json['access_token']?.toString() ?? '';
    final expiresAt =
        DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toUtc();
    if (refresh.isEmpty || access.isEmpty || expiresAt == null) return null;
    return _CredentialState(
      providerId: providerId,
      refreshToken: refresh,
      accessToken: access,
      expiresAt: expiresAt,
      epoch: (json['epoch'] as num?)?.toInt() ?? 0,
    );
  }
}
```

> 生产 `CredentialRefresher` 实现（HTTP POST 到 `https://auth.x.ai`，把 `invalid_grant` 映射为 `RefreshRejected()`）在 Task 6 的 `cli_bootstrap_wiring.dart` 中以 `_XaiCredentialRefresher` 形式给出，避免本任务依赖 `dart:io` 网络，保持纯 Dart 可测。

- [ ] **Step 4: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/oauth_credential_authority_test.dart`
Expected: PASS（8 tests）。若 `InMemoryFilesystem.atomicWrite` 对不存在父目录报错，先确认 Step 1 的 `ensureDir` 断言；`_persist` 已 `ensureDir`。

Run: `cd client && flutter analyze lib/services/provider/oauth_credential_authority.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/provider/oauth_credential_authority.dart \
  client/test/services/provider/oauth_credential_authority_test.dart
git commit -m "feat(grok): add control-plane OAuth credential authority"
```

---

## Task 4: CredentialLeaseEndpoint + gateway 路由

**Files:**
- Create: `client/lib/services/provider/credential_lease_endpoint.dart`
- Modify: `client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart:198`
- Test: `client/test/services/provider/credential_lease_endpoint_test.dart`

**Interfaces:**
- Consumes: `OAuthCredentialAuthority.lease/status/recover`（Task 3）、`CredentialLease.toProviderJson`（Task 2）
- Produces:
  - `class CredentialLeaseEndpoint { static const path = '/credentials/lease'; CredentialLeaseEndpoint({required OAuthCredentialAuthority authority, required String? Function(String sessionId) sessionProviderId, DateTime Function()? now}); Future<LeaseHttpResponse> serve({required String sessionId, required String? busToken, required String providerId, required bool forceRefresh}); }`
  - `class LeaseHttpResponse { int statusCode; Map<String, Object?> body; }`
  - `TeammateBusMcpGateway.attachCredentialLeaseEndpoint(CredentialLeaseEndpoint endpoint)` + getter

> `app_shell.dart` 的 attach 归入 Task 6（那里同时构造 endpoint 实例），本任务不碰 app_shell，保证 Task 4 可独立编译、独立 commit。

- [ ] **Step 1: 写失败测试**

`client/test/services/provider/credential_lease_endpoint_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../support/in_memory_filesystem.dart';

final class _OkRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'fresh',
        refreshToken: 'rt-fresh',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
}

void main() {
  final now = DateTime.utc(2026, 11, 14, 11, 0, 0);

  Future<CredentialLeaseEndpoint> build() async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => now,
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'access-old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T11:30:00Z',
        }
      })),
    );
    return CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (sessionId) => 'xai',
      now: () => now,
    );
  }

  test('serves a lease with access_token and expires_in, never a refresh token',
      () async {
    final endpoint = await build();
    final response = await endpoint.serve(
      sessionId: 's1',
      busToken: 'bus-token',
      providerId: 'xai',
      forceRefresh: false,
    );

    expect(response.statusCode, 200);
    expect(response.body['access_token'], 'access-old');
    expect(response.body['expires_in'], 1800);
    expect(jsonEncode(response.body), isNot(contains('refresh_token')));
  });

  test('rejects a missing session or bus token', () async {
    final endpoint = await build();
    expect(
      (await endpoint.serve(
        sessionId: '',
        busToken: null,
        providerId: 'xai',
        forceRefresh: false,
      )).statusCode,
      401,
    );
  });

  test('rejects a providerId that does not belong to the session', () async {
    final endpoint = await build();
    expect(
      (await endpoint.serve(
        sessionId: 's1',
        busToken: 'bus-token',
        providerId: 'other',
        forceRefresh: false,
      )).statusCode,
      401,
    );
  });

  test('forceRefresh returns 409 with rejected health when RT is refused',
      () async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _RejectRefresher(),
      now: () => now,
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'access-old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T11:30:00Z',
        }
      })),
    );
    final endpoint = CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => now,
    );

    final response = await endpoint.serve(
      sessionId: 's1',
      busToken: 'bus-token',
      providerId: 'xai',
      forceRefresh: true,
    );
    expect(response.statusCode, 409);
    expect(response.body['health'], 'rejected');
  });
}

final class _RejectRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      const RefreshRejected();
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/credential_lease_endpoint_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/services/provider/credential_lease_endpoint.dart'`。

- [ ] **Step 3: 实现 endpoint**

`client/lib/services/provider/credential_lease_endpoint.dart`：

```dart
import '../../models/credential_lease.dart';
import 'oauth_credential_authority.dart';

class LeaseHttpResponse {
  const LeaseHttpResponse(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

/// Pure-Dart HTTP semantics for the credential lease route. The gateway owns
/// JSON decoding/encoding so this class is testable without an HttpServer.
final class CredentialLeaseEndpoint {
  CredentialLeaseEndpoint({
    required this.authority,
    required this.sessionProviderId,
    DateTime Function()? now,
  }) : _now = now ?? () => DateTime.now().toUtc();

  static const path = '/credentials/lease';

  final OAuthCredentialAuthority authority;

  /// Maps a session id to the provider id it is allowed to request. Returns
  /// null when the session is unknown.
  final String? Function(String sessionId) sessionProviderId;
  final DateTime Function() _now;

  Future<LeaseHttpResponse> serve({
    required String sessionId,
    required String? busToken,
    required String providerId,
    required bool forceRefresh,
  }) async {
    if (sessionId.trim().isEmpty ||
        (busToken ?? '').trim().isEmpty ||
        providerId.trim().isEmpty) {
      return const LeaseHttpResponse(401, {'error': 'unauthorized'});
    }
    final allowed = sessionProviderId(sessionId);
    if (allowed == null || allowed != providerId) {
      return const LeaseHttpResponse(401, {'error': 'unauthorized'});
    }

    try {
      final lease = await authority.lease(
        providerId: providerId,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
      );
      return LeaseHttpResponse(200, {
        'access_token': lease.accessToken,
        'expires_in': lease.expiresInSeconds(_now()),
        'epoch': lease.epoch,
      });
    } on CredentialUnavailableException catch (error) {
      return LeaseHttpResponse(409, {'health': error.health.name});
    }
  }
}
```

> **协议取舍（spec「协议」的 503）**：首版不产生 503。`CredentialRefresher` 只有 `RefreshSucceeded` / `RefreshRejected` 两种结果，网络瞬态失败由 `_XaiCredentialRefresher` 统一映射为 `RefreshRejected()` → 409；grok 的 headless refresh 在 `GROK_AUTH_EXPIRED=1` 下本就要求「失败即快速转 sign-in」，因此不为瞬态重试引入第三种结果与额外重试状态机。shim 收到非 200 时 `exit 1`，会话经 Task 7 的恢复路径重连一次。

- [ ] **Step 4: gateway 加路由**

`client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart`：

在字段区（`_catalogHandler` 附近，约 `:40`）加：

```dart
  CredentialLeaseEndpoint? _credentialLeaseEndpoint;
```

在 `attachCatalogHandler`（约 `:119`）后加：

```dart
  void attachCredentialLeaseEndpoint(CredentialLeaseEndpoint endpoint) {
    _credentialLeaseEndpoint = endpoint;
  }

  CredentialLeaseEndpoint? get credentialLeaseEndpoint =>
      _credentialLeaseEndpoint;
```

在 `_onRequest` 中，紧跟 `catalogMcpPath` 分支之后（约 `:238`，**必须在 `_delegates` bail-out 之前**，保证 Simple 会话可用）插入：

```dart
      // Credential lease is available for every session, including Simple
      // (no TeamBus register). Route before the `_delegates` bail-out.
      if (request.method == 'POST' &&
          request.uri.path == CredentialLeaseEndpoint.path) {
        await _handleCredentialLease(request);
        return;
      }
```

新增私有方法（放在 `_handleCatalogMcp` 附近）：

```dart
  Future<void> _handleCredentialLease(HttpRequest request) async {
    final endpoint = _credentialLeaseEndpoint;
    if (endpoint == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final sessionId = _resolveSessionId(request) ?? '';
    final busToken = _headerValue(request.headers, teammateBusTokenHeader);
    // Remote seats must present a bus token registered for that same session.
    final tokenSession = busToken.isNotEmpty
        ? _registry.sessionForToken(busToken)
        : null;
    if (tokenSession != null && tokenSession != sessionId) {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
      return;
    }
    Map<String, Object?> body;
    try {
      final raw = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(raw);
      body = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } on Object {
      body = <String, Object?>{};
    }
    final result = await endpoint.serve(
      sessionId: sessionId,
      // Local seats have no bus token; the session header is authoritative.
      busToken: busToken.isNotEmpty ? busToken : sessionId,
      providerId: body['providerId']?.toString() ?? '',
      forceRefresh: body['forceRefresh'] == true,
    );
    request.response.statusCode = result.statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result.body));
    await request.response.close();
  }
```

在该文件 import 区补**一条**（该文件已有 `dart:convert`、`dart:io`，无需重复）：

```dart
import '../../../provider/credential_lease_endpoint.dart';
```

- [ ] **Step 5: 确认 gateway 独立可编译**

gateway 新增的 `attachCredentialLeaseEndpoint` 此时还没有调用方，这是允许的（attach 由 Task 6 完成）。本任务结束时 `flutter analyze` 必须仍然通过。

- [ ] **Step 6: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/provider/credential_lease_endpoint_test.dart`
Expected: PASS（4 tests）。

Run: `cd client && flutter analyze lib/services/provider/credential_lease_endpoint.dart`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/provider/credential_lease_endpoint.dart \
  client/lib/services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart \
  client/test/services/provider/credential_lease_endpoint_test.dart
git commit -m "feat(grok): expose credential lease endpoint on the bus gateway"
```

> Task 4 的改动自洽：endpoint 类 + gateway 路由 + 测试，无外部未解析引用。Task 6 只负责构造实例并 attach。

---

## Task 5: GrokCredentialAdapter + shim

**Files:**
- Create: `client/lib/services/cli/grok/provider/grok_credential_adapter.dart`
- Test: `client/test/services/cli/grok/grok_credential_adapter_test.dart`

**Interfaces:**
- Consumes: `SessionCredentialCapability`（Task 2）、`OAuthCredentialAuthority`（Task 3）、`CredentialLeaseEndpoint.path`（Task 4）、`GrokConstants`（Task 2）、`SessionHomeContext.busIdle` / `sessionId` / `memberId` / `crossMachine`
- Produces:
  - `class GrokCredentialAdapter implements SessionCredentialCapability { GrokCredentialAdapter({required OAuthCredentialAuthority authority, required String? Function(String sessionId) sessionProviderId, DateTime Function()? now}); Future<SessionHomeContribution> materialize(SessionHomeContext ctx, {required String providerId}); }`

> 端点 URL 完全从 `SessionHomeContext.busIdle.url` 派生（`MemberBusIdleEndpoint.local` 给本地 loopback，`.remote` 给 SSH 反向隧道），无需 gateway port 注入，因此 `wireCliBootstrap` 可在 gateway 创建之前完成全部构造。
  - `onAuthRequired` → `authority.recover(providerId, sessionId)`

> 若 Task 1 结论为 `no`，本任务改用**附录 B** 的降级适配器（完整实现见文末），跳过本任务 Step 3 中 `GROK_AUTH_PROVIDER_COMMAND` 的注入。

- [ ] **Step 1: 写失败测试**

`client/test/services/cli/grok/grok_credential_adapter_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_filesystem.dart';
import 'package:teampilot/services/chat/team_bus/member_bus_idle_endpoint.dart';
import 'package:teampilot/services/cli/grok/grok_constants.dart';
import 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

final class _OkRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'fresh',
        refreshToken: 'rt-fresh',
        expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
      );
}

void main() {
  const localBusIdle = MemberBusIdleEndpoint(
    url: 'http://127.0.0.1:35297/idle',
  );

  SessionHomeContext context(
    ConfigProfileService service, {
    MemberBusIdleEndpoint? busIdle,
    bool crossMachine = false,
    bool withoutBusIdle = false,
  }) =>
      sessionHomeContextFromLaunch(
        ConfigProfileLaunchContext(
          workspaceId: 'workspace-1',
          teamId: 'team-a',
          sessionId: 'session-1',
          scope: resolveLaunchProfileScope(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            appSessionId: 'session-1',
            cliTeamName: 'session-1',
          ),
          member: const TeamMemberConfig(
            id: 'm1',
            name: 'Member',
            provider: 'xai',
            model: 'grok-4.7',
          ),
          members: const [
            TeamMemberConfig(
              id: 'm1',
              name: 'Member',
              provider: 'xai',
              model: 'grok-4.7',
            ),
          ],
          workingDirectory: '/workspace/workspace',
          paths: service,
          catalog: service,
          busIdle: withoutBusIdle ? null : (busIdle ?? localBusIdle),
          crossMachine: crossMachine,
        ),
        CliTool.grok,
      );

  Future<({GrokCredentialAdapter adapter, InMemoryFilesystem fs})> build() async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'access-old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T11:30:00Z',
        }
      })),
    );
    return (
      adapter: GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      ),
      fs: fs,
    );
  }

  test('injects GROK_AUTH_PROVIDER_COMMAND and writes shim + lease config',
      () async {
    final built = await build();
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );

    final contribution =
        await built.adapter.materialize(context(service), providerId: 'xai');

    final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
    expect(
      contribution.environment[GrokConstants.authProviderCommandEnvKey],
      p.posix.join(configDir, 'bin', GrokConstants.leaseShimFileName),
    );
    expect(contribution.environment,
        isNot(contains(GrokConstants.apiKeyEnvKey)));
    expect(contribution.warnings, isEmpty);

    final shim =
        await fs.readString(p.posix.join(configDir, 'bin', 'teampilot-grok-auth'));
    expect(shim, contains('/credentials/lease'));
    expect(shim, contains('GROK_AUTH_EXPIRED'));

    final leaseConfig = jsonDecode(
      (await fs.readString(
        p.posix.join(configDir, GrokConstants.leaseConfigFileName),
      ))!,
    ) as Map<String, Object?>;
    expect(leaseConfig['providerId'], 'xai');
    expect(leaseConfig['endpoint'], 'http://127.0.0.1:35297/credentials/lease');
    expect(jsonEncode(leaseConfig), isNot(contains('access-old')));
    expect(jsonEncode(leaseConfig), isNot(contains('rt-old')));
  });

  test('no auth.json is seeded into the session home', () async {
    final built = await build();
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );

    final contribution =
        await built.adapter.materialize(context(service), providerId: 'xai');
    final configDir = contribution.environment[GrokConstants.homeEnvKey]!;

    expect(await fs.readString(p.posix.join(configDir, 'auth.json')), isNull);
  });

  test('remote seat uses the idle HTTP tunnel endpoint and bus token',
      () async {
    final built = await build();
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );
    final busIdle = const MemberBusIdleEndpoint(
      url: 'http://127.0.0.1:41001/idle',
      token: 'bus-secret',
    );

    final contribution = await built.adapter.materialize(
      context(service, busIdle: busIdle, crossMachine: true),
      providerId: 'xai',
    );
    final configDir = contribution.environment[GrokConstants.homeEnvKey]!;
    final leaseConfig = jsonDecode(
      (await fs.readString(
        p.posix.join(configDir, GrokConstants.leaseConfigFileName),
      ))!,
    ) as Map<String, Object?>;

    expect(leaseConfig['endpoint'], 'http://127.0.0.1:41001/credentials/lease');
    expect(leaseConfig['sessionId'], 'session-1');
    expect(leaseConfig['memberId'], 'm1');
  });

  test('expired/rejected credential fails before launch with a warning',
      () async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _OkRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    final adapter = GrokCredentialAdapter(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );

    expect(
      () => adapter.materialize(context(service), providerId: 'xai'),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });

  test('onAuthRequired recovers once and credentialStatus reflects health',
      () async {
    final built = await build();

    expect(await built.adapter.credentialStatus('xai'),
        CredentialHealth.ready);
    expect(
      await built.adapter.onAuthRequired(
        providerId: 'xai',
        sessionId: 'session-1',
      ),
      isTrue,
    );
  });

  test('no reachable lease endpoint fails before launch', () async {
    final built = await build();
    final fs = InMemoryFilesystem();
    final service = ConfigProfileService(
      basePath: '/tp',
      fs: fs,
      layout: RuntimeLayout(teampilotRoot: '/tp', fs: fs),
      storage: fakeHomeStorage(filesystem: fs),
    );

    expect(
      () => built.adapter.materialize(
        context(service, withoutBusIdle: true),
        providerId: 'xai',
      ),
      throwsA(isA<CredentialUnavailableException>()),
    );
  });
}
```

> `fakeHomeStorage` 定义在 `client/test/support/in_memory_filesystem.dart:14`，`resolveLaunchProfileScope` 在 `config_profile_service.dart`，用法与 `grok_provider_materialize_test.dart:1-12` 一致。`ctx.memberId` 为空时 adapter 回落到 `ctx.member.id`（本用例为 `'m1'`），故 `leaseConfig['memberId'] == 'm1'` 成立。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/grok/grok_credential_adapter_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart'`。

- [ ] **Step 3: 实现 adapter（含完整 shim）**

`client/lib/services/cli/grok/provider/grok_credential_adapter.dart`：

```dart
import 'dart:convert';
import 'dart:io' show File, Platform, Process;

import '../../../../models/credential_lease.dart';
import '../../../../services/cli/registry/capabilities/provider_capability.dart';
import '../../../../services/cli/registry/capabilities/session_credential_capability.dart';
import '../../../../services/io/filesystem.dart';
import '../../../../services/provider/credential_lease_endpoint.dart';
import '../../../../services/provider/oauth_credential_authority.dart';
import '../grok_constants.dart';

/// Grok implementation of [SessionCredentialCapability].
///
/// Injects grok's official External Auth Provider command into the isolated
/// `GROK_HOME`. The shim POSTs to the control-plane lease endpoint; grok
/// re-runs it on missing credential, near-expiry rotation, and 401.
final class GrokCredentialAdapter implements SessionCredentialCapability {
  GrokCredentialAdapter({
    required this.authority,
    required this.sessionProviderId,
    DateTime Function()? now,
  }) : _now = now ?? () => DateTime.now().toUtc();

  final OAuthCredentialAuthority authority;
  final String? Function(String sessionId) sessionProviderId;
  final DateTime Function() _now;

  @override
  Future<CredentialLease> leaseCredentials({
    required String providerId,
    required String sessionId,
    bool forceRefresh = false,
  }) =>
      authority.lease(
        providerId: providerId,
        sessionId: sessionId,
        forceRefresh: forceRefresh,
      );

  @override
  Future<CredentialHealth> credentialStatus(String providerId) =>
      authority.status(providerId);

  @override
  Future<bool> onAuthRequired({
    required String providerId,
    required String sessionId,
  }) =>
      authority.recover(providerId, sessionId);

  /// Launch-time materialization. Fails before the agent is spawned when the
  /// provider needs a login (Stage 1 pre-launch gate).
  Future<SessionHomeContribution> materialize(
    SessionHomeContext ctx, {
    required String providerId,
  }) async {
    // A seat may only request the provider it was launched with.
    final allowed = sessionProviderId(ctx.sessionId);
    if (allowed != null && allowed != providerId) {
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }
    // Force one lease up front so a dead credential surfaces here, not as a
    // confusing mid-session "not logged in".
    await leaseCredentials(
      providerId: providerId,
      sessionId: ctx.sessionId,
    );

    final configDir = ctx.paths.sessionToolDir(
      ctx.scope.workspaceId,
      ctx.scope.sessionId,
      'grok',
      memberId: ctx.memberId,
    );
    final fs = ctx.paths.fs;
    await fs.ensureDir(configDir);

    final binDir = fs.pathContext.join(configDir, 'bin');
    await fs.ensureDir(binDir);
    final shimPath = fs.pathContext.join(binDir, GrokConstants.leaseShimFileName);
    await fs.atomicWrite(shimPath, _shimScript);
    // grok runs the command via `sh -c`, so the shim needs the executable bit.
    _restrict(fs, shimPath, executable: true);

    final leaseConfigPath =
        fs.pathContext.join(configDir, GrokConstants.leaseConfigFileName);
    final endpoint = _endpointFor(ctx);
    if (endpoint.isEmpty) {
      // No reachable lease endpoint (e.g. Windows remote / missing tunnel):
      // fail before spawning an agent that could never authenticate.
      throw const CredentialUnavailableException(CredentialHealth.missing);
    }
    final busIdle = ctx.busIdle;
    final memberId = ctx.memberId ?? ctx.member?.id ?? 'acp';
    final body = <String, Object?>{
      'providerId': providerId,
      'endpoint': endpoint,
      'sessionId': ctx.sessionId,
      'memberId': memberId,
      'busToken': busIdle?.token ?? ctx.sessionId,
    };
    await fs.atomicWrite(leaseConfigPath, jsonEncode(body));
    _restrict(fs, leaseConfigPath);

    return SessionHomeContribution(
      environment: {
        GrokConstants.homeEnvKey: configDir,
        GrokConstants.authProviderCommandEnvKey: shimPath,
      },
    );
  }

  /// Local seats use the in-process gateway loopback (`MemberBusIdleEndpoint
  /// .local`); remote seats reuse the already-provisioned idle HTTP tunnel
  /// port (`.remote`). No gateway port needs to be injected at construction.
  String _endpointFor(SessionHomeContext ctx) {
    final url = ctx.busIdle?.url ?? '';
    if (url.isEmpty) return '';
    final base = _baseOf(url);
    if (base.isEmpty) return '';
    return '$base${CredentialLeaseEndpoint.path}';
  }

  static String _baseOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return '';
    return '${uri.scheme}://${uri.host}:${uri.port}';
  }

  static void _restrict(
    Filesystem fs,
    String path, {
    bool executable = false,
  }) {
    if (Platform.isWindows) return;
    try {
      if (!File(path).existsSync()) return;
      Process.runSync('chmod', [executable ? '700' : '600', path]);
    } on Object {
      // Best effort: OverlayFilesystem / InMemoryFilesystem have no real
      // POSIX path. Tests exercise content, not permissions.
    }
  }
}

/// POSIX sh shim. stdout carries ONLY the token JSON (grok contract);
/// `GROK_AUTH_EXPIRED=1` means a silent headless refresh — fail fast.
const String _shimScript = r'''#!/bin/sh
# Generated by TeamPilot. Do not edit.
set -u
CFG="$(dirname "$0")/../credential-lease.json"
[ -f "$CFG" ] || { echo "missing lease config" >&2; exit 1; }

ENDPOINT=$(sed -n 's/.*"endpoint"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
PROVIDER=$(sed -n 's/.*"providerId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
SESSION=$(sed -n 's/.*"sessionId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)
TOKEN=$(sed -n 's/.*"busToken"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CFG" | head -1)

[ -n "$ENDPOINT" ] || { echo "missing endpoint" >&2; exit 1; }

if [ "${GROK_AUTH_EXPIRED:-}" = "1" ]; then
  TIMEOUT=3
else
  TIMEOUT=10
fi

BODY="{\"providerId\":\"$PROVIDER\",\"forceRefresh\":false}"
RESP=$(curl -sS --max-time "$TIMEOUT" \
  -H "Content-Type: application/json" \
  -H "X-Session: $SESSION" \
  -H "X-Bus-Token: $TOKEN" \
  -X POST -d "$BODY" "$ENDPOINT") || { echo "lease request failed" >&2; exit 1; }

case "$RESP" in
  *'"access_token"'*) printf '%s\n' "$RESP" ;;
  *) echo "lease rejected: $RESP" >&2; exit 1 ;;
esac
''';
```

> Windows 远端首版不支持（spec「待确认」第 2 条）：`_shimScript` 仅 POSIX sh。若 `ctx.crossMachine` 且目标为 Windows，`_endpointFor` 返回 `''`，`materialize` 产出 `grok_credential_endpoint_unavailable` warning，launch 前拦截生效，不静默启动失败 agent。

- [ ] **Step 4: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/grok/grok_credential_adapter_test.dart`
Expected: PASS（6 tests）。

Run: `cd client && flutter analyze lib/services/cli/grok/provider/grok_credential_adapter.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/grok/provider/grok_credential_adapter.dart \
  client/test/services/cli/grok/grok_credential_adapter_test.dart
git commit -m "feat(grok): add external auth provider adapter and lease shim"
```

---

## Task 6: DI 链路、provider capability 改造、退役 seed/marker

**Files:**
- Modify: `client/lib/services/cli/grok/grok_bootstrap_entry.dart`
- Modify: `client/lib/app/bootstrap/cli_bootstrap_wiring.dart:125`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart:148`
- Modify: `client/lib/app/app_shell.dart:1273`
- Modify: `client/lib/services/cli/grok/capabilities/provider.dart`
- Modify: `client/lib/services/cli/grok/provider/grok_auth_store.dart`
- Modify: `client/test/services/cli/grok/grok_provider_materialize_test.dart`

**Interfaces:**
- Consumes: Task 2–5 的全部类型
- Produces:
  - `GrokBootstrapEntry({required String? Function() credentialSource, required OAuthCredentialAuthority authority, required GrokCredentialAdapter adapter, required CredentialLeaseEndpoint leaseEndpoint})`
  - `GrokProviderCapability({HomeStorage? storage, AcpCredentialSource? fallbackCredentialSource, OAuthCredentialAuthority? authority, GrokCredentialAdapter? adapter})`
  - `_XaiCredentialRefresher`（生产刷新器）

- [ ] **Step 1: 改现有测试，先让它失败**

`client/test/services/cli/grok/grok_provider_materialize_test.dart`：

把第一个测试的断言（约 `:70-90`）从
```dart
      expect(
        await fs.readString(p.posix.join(configDir, 'auth.json')),
        '{"access_token":"provider"}',
      );
```
改为
```dart
      expect(await fs.readString(p.posix.join(configDir, 'auth.json')), isNull);
      expect(
        contribution.environment[GrokConstants.authProviderCommandEnvKey],
        isNotNull,
      );
```
并删除该测试中 `fs.atomicWrite('/tp/providers/grok/xai/auth.json', ...)` 的 seed 布置，改为配置 Authority。在该测试 `final capability = GrokProviderCapability(storage: storage);` 处改为注入：

```dart
      final authority = OAuthCredentialAuthority(
        fs: fs,
        basePath: '/tp',
        cliNamespace: 'grok',
        refresher: _TestRefresher(),
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      await authority.importFromLogin(
        'xai',
        utf8.encode('{"scope":{"key":"provider","refresh_token":"rt",'
            '"expires_at":"2026-11-14T11:30:00Z"}}'),
      );
      final adapter = GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      );
      final capability = GrokProviderCapability(
        storage: storage,
        authority: authority,
        adapter: adapter,
      );
```

文件顶部补 import 与 fake：

```dart
import 'package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

final class _TestRefresher implements CredentialRefresher {
  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async =>
      RefreshSucceeded(
        accessToken: 'provider',
        refreshToken: 'rt',
        expiresAt: DateTime.utc(2026, 11, 14, 11, 30, 0),
      );
}
```

在 `main()` 末尾新增 probe 测试：

```dart
  test('probe reflects Authority health instead of file size', () async {
    final fs = InMemoryFilesystem();
    final storage = fakeHomeStorage(filesystem: fs);
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _TestRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await fs.ensureDir('/tp/providers/grok/xai');
    await fs.atomicWrite(
      '/tp/providers/grok/xai/auth.json',
      '{"scope":{"key":"x","refresh_token":"y",'
          '"expires_at":"2026-11-14T11:30:00Z"}}',
    );
    final capability = GrokProviderCapability(
      storage: storage,
      authority: authority,
      adapter: GrokCredentialAdapter(
        authority: authority,
        sessionProviderId: (_) => 'xai',
        now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
      ),
    );

    // A non-empty legacy auth.json alone must NOT count as ready.
    final probe = await capability.probe(
      const AppProviderConfig(
        id: 'xai',
        cli: CliTool.grok,
        name: 'xAI',
        isOfficial: true,
        apiKey: '',
        apiKeyField: 'api_key',
        baseUrl: '',
        defaultModel: 'grok-4.7',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
    expect(probe.isReady, isFalse);
  });
```

在文件顶部补一条 import（`CliTool` 已由 `team_config.dart` 提供）：

```dart
import 'package:teampilot/models/app_provider_config.dart';
```

> `AppProviderConfig` 的构造签名已核对（`client/lib/models/app_provider_config.dart:32`，全部为命名可选参数 + `id/cli/name` required）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/grok/grok_provider_materialize_test.dart`
Expected: FAIL — `GrokProviderCapability` 没有 `authority` / `adapter` 命名参数。

- [ ] **Step 3: Bootstrap entry + wiring**

`client/lib/services/cli/grok/grok_bootstrap_entry.dart` 整体替换为：

```dart
import '../../models/team_config.dart';
import '../registry/cli_bootstrap.dart';
import '../../services/provider/credential_lease_endpoint.dart';
import '../../services/provider/oauth_credential_authority.dart';
import 'provider/grok_credential_adapter.dart';

/// Grok runtime services injected after home storage is ready.
final class GrokBootstrapEntry implements CliBootstrapEntry {
  const GrokBootstrapEntry({
    required this.credentialSource,
    required this.authority,
    required this.adapter,
    required this.leaseEndpoint,
  });

  /// Returns the stored xAI API key, or null when unset (API-key seats only).
  final String? Function() credentialSource;

  /// Control-plane single owner of the xAI refresh token.
  final OAuthCredentialAuthority authority;

  /// Session-home credential injection.
  final GrokCredentialAdapter adapter;

  /// HTTP handler attached to the bus gateway.
  final CredentialLeaseEndpoint leaseEndpoint;
}
```

`client/lib/app/bootstrap/cli_bootstrap_wiring.dart`，在 `wireCliBootstrap` 内（`CliTool.grok:` 之前）加入构造：

```dart
    final authority = OAuthCredentialAuthority(
      fs: homeStorage.fs,
      basePath: homeStorage.paths.basePath,
      cliNamespace: 'grok',
      refresher: _XaiCredentialRefresher(),
    );
    final credentialLeaseEndpoint = CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (sessionId) => 'xai',
    );
    final grokAdapter = GrokCredentialAdapter(
      authority: authority,
      sessionProviderId: (sessionId) => 'xai',
    );
    // One-time migration of the pre-Authority provider store.
    unawaited(authority.importLegacyAuthJson('xai'));
    // Provider UI reflects fine-grained Authority health (rejected/missing).
    authority.healthChanges.addListener(() {
      unawaited(appProviderCubit.reconcileCredentials());
    });
```

`cli_bootstrap_wiring.dart` import 区补 `dart:async`（`unawaited`）、`dart:convert`、`dart:io`、`package:teampilot/services/provider/oauth_credential_authority.dart`、`package:teampilot/services/provider/credential_lease_endpoint.dart`、`package:teampilot/services/cli/grok/provider/grok_credential_adapter.dart`（已有项跳过）。`wireCliBootstrap` 在 app_shell 创建 gateway **之前**调用，本构造不依赖 gateway，顺序安全。

把 `:125` 的
```dart
      CliTool.grok: GrokBootstrapEntry(
        credentialSource: () => cachedGrokApiKey,
      ),
```
改为
```dart
      CliTool.grok: GrokBootstrapEntry(
        credentialSource: () => cachedGrokApiKey,
        authority: authority,
        adapter: grokAdapter,
        leaseEndpoint: credentialLeaseEndpoint,
      ),
```

在同一文件末尾加生产刷新器（`http` 来自 `dart:io`，按 `CODE_QUALITY.md` 注入 `HttpClient` 以便测试）：

```dart
final class _XaiCredentialRefresher implements CredentialRefresher {
  _XaiCredentialRefresher({
    HttpClient? client,
    this.issuer = 'https://auth.x.ai',
  }) : _client = client ?? HttpClient();

  final HttpClient _client;
  final String issuer;
  String? _tokenEndpoint;

  Future<String> _discoverTokenEndpoint() async {
    final cached = _tokenEndpoint;
    if (cached != null) return cached;
    final request = await _client
        .getUrl(Uri.parse('$issuer/.well-known/openid-configuration'));
    final response = await request.close();
    if (response.statusCode != 200) return '';
    final raw = await response.transform(utf8.decoder).join();
    final value =
        (jsonDecode(raw) as Map<String, Object?>)['token_endpoint']
            ?.toString() ??
            '';
    _tokenEndpoint = value;
    return value;
  }

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    final endpoint = await _discoverTokenEndpoint();
    if (endpoint.isEmpty) return const RefreshRejected();
    final request = await _client.postUrl(Uri.parse(endpoint));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': 'b1a00492-073a-47ea-816f-4c329264a828',
    }));
    final response = await request.close();
    final raw = await response.transform(utf8.decoder).join();
    // IdP `invalid_grant` and any non-200 are permanent: never retry with the
    // same (rotated-away) refresh token.
    if (response.statusCode != 200) return const RefreshRejected();
    final json = jsonDecode(raw) as Map<String, Object?>;
    final access = json['access_token']?.toString() ?? '';
    final next = json['refresh_token']?.toString() ?? refreshToken;
    final seconds = (json['expires_in'] as num?)?.toInt() ?? 3600;
    if (access.isEmpty) return const RefreshRejected();
    return RefreshSucceeded(
      accessToken: access,
      refreshToken: next,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    );
  }
}
```

> Token endpoint 通过 OIDC discovery 动态解析，无硬编码路径；`client_id` 取自 grok 1.0.77 的实际值（会话日志 `b1a00492-073a-47ea-816f-4c329264a828`）。`invalid_grant` / 非 200 一律映射为 `RefreshRejected()`，由 Authority 统一判定并清 RT。import 清单见本任务 Step 3 开头。

`client/lib/services/cli/registry/built_in_cli_tools.dart:148`：

```dart
    GrokCliTool(
      provider: GrokProviderCapability(
        storage: storage,
        fallbackCredentialSource: grokEntry?.credentialSource,
        authority: grokEntry?.authority,
        adapter: grokEntry?.adapter,
      ),
      headless: GrokHeadlessCapability(storage: storage),
      acp: GrokAcpCapability(credentialSource: grokEntry?.credentialSource),
    ),
```

`client/lib/app/app_shell.dart`，在 `:1273` 的 `attachCatalogHandler` 之后加：

```dart
    final grokBootstrap =
        cliToolRegistry.bootstrap?.entry<GrokBootstrapEntry>(CliTool.grok);
    if (grokBootstrap != null) {
      teammateBusMcpGateway
          .attachCredentialLeaseEndpoint(grokBootstrap.leaseEndpoint);
    }
```

并在 import 区补：
```dart
import '../services/cli/grok/grok_bootstrap_entry.dart';
import '../services/provider/credential_lease_endpoint.dart';
```

> `credentialLeaseEndpoint` 的 `sessionProviderId` 首版固定返回 `'xai'`（grok 官方 provider 唯一）。Stage 3 扩展多账号时改为从 session 记录解析，端点与 Authority 不变。

- [ ] **Step 4: 改造 GrokProviderCapability**

`client/lib/services/cli/grok/capabilities/provider.dart`：

构造函数（约 `:75`）改为：

```dart
  const GrokProviderCapability({
    this.storage,
    this.fallbackCredentialSource,
    this.authority,
    this.adapter,
  });

  final HomeStorage? storage;
  final AcpCredentialSource? fallbackCredentialSource;
  final OAuthCredentialAuthority? authority;
  final GrokCredentialAdapter? adapter;
```

`probe`（约 `:178-200`）替换为：

```dart
  @override
  Future<CredentialProbe> probe(AppProviderConfig provider) async {
    final path = _authStore?.providerAuthDir(provider.id) ?? '';
    final ready = provider.apiKey.trim().isNotEmpty ||
        (authority != null &&
            await authority!.status(provider.id) == CredentialHealth.ready);
    final stat = path.isEmpty ? null : await _authStore!.fs.stat(path);
    return CredentialProbe(
      providerId: provider.id,
      status: ready ? CredentialStatus.ready : CredentialStatus.missing,
      credentialPath: path,
      updatedAt: stat?.isDirectory == true ? stat!.mtime : null,
    );
  }
```

`execute`（约 `:203-243`）：`login` 分支改为

```dart
    if (kind == ProviderCredentialActionKind.login) {
      final target = authority;
      if (target == null) return CredentialActionResult.serviceUnavailable();
      final bytes = await store.fs.readBytes(store.loginAuthPath(providerId));
      if (bytes == null || bytes.isEmpty) {
        return CredentialActionResult.failure(
          const CredentialActionFailure(
            code: CredentialActionFailureCode.verifyFailed,
          ),
        );
      }
      return await target.importFromLogin(providerId, bytes)
          ? CredentialActionResult.success
          : CredentialActionResult.failure(
              const CredentialActionFailure(
                code: CredentialActionFailureCode.verifyFailed,
              ),
            );
    }
```

`importGlobal` 分支同样改为读 `store.machineAuthPath` 的字节并 `importFromLogin`。新增 `revoke` 分支：

```dart
    if (kind == ProviderCredentialActionKind.revoke) {
      final target = authority;
      if (target == null) return CredentialActionResult.serviceUnavailable();
      await target.revoke(providerId);
      return CredentialActionResult.success;
    }
```

`materializeSessionHome`（约 `:323-399`）的 OAuth 分支（`:361` 的 `else`）整体替换为：

```dart
    } else {
      final grokAdapter = adapter;
      if (grokAdapter == null) {
        warnings.add('grok_credentials_missing');
      } else {
        try {
          final leaseContribution = await grokAdapter.materialize(
            ctx,
            providerId: providerId,
          );
          for (final entry in leaseContribution.environment.entries) {
            environment[entry.key] = entry.value;
          }
        } on CredentialUnavailableException catch (error) {
          // Stage 1 pre-launch gate: fail before spawning an agent that would
          // immediately report "not logged in".
          throw GrokCredentialUnavailableException(providerId, error.health);
        }
      }
    }
```

在 `if (apiKey.isNotEmpty) { ... } else { ... }` **之前**（原 `:357` 处）声明可变的 `environment`，使 OAuth 分支能写入 adapter 的 env：

```dart
    final environment = <String, String>{
      GrokConstants.homeEnvKey: configDir,
      if (apiKey.isNotEmpty) GrokConstants.apiKeyEnvKey: apiKey,
    };
```

把原 `:392-398` 的 `return SessionHomeContribution(environment: {...}, warnings: warnings);` 改为：

```dart
    return SessionHomeContribution(
      environment: environment,
      warnings: warnings,
    );
```

在文件末尾加异常类：

```dart
final class GrokCredentialUnavailableException implements Exception {
  const GrokCredentialUnavailableException(this.providerId, this.health);

  final String providerId;
  final CredentialHealth health;

  @override
  String toString() =>
      'Grok provider $providerId needs a sign-in (${health.name})';
}
```

> **启动前拦截的 UI 呈现（spec 验收标准 5）**：`GrokCredentialUnavailableException` 经 `ConfigProfileService.materializeSessionHome`（`:1160` 的 `Error.throwWithStackTrace`）传播为 session-connect failure，agent 不会被 spawn；`probe` 同时返回 `CredentialStatus.missing`，provider 列表沿用现有的「需要登录」呈现；`Authority.healthChanges` 已在 Step 3 订阅 `appProviderCubit.reconcileCredentials()`，细粒度 `rejected` / `missing` 会刷新该行。全程不新增 l10n 文案。

新增 import：
```dart
import '../../../../models/credential_lease.dart';
import '../../../provider/oauth_credential_authority.dart';
import '../provider/grok_credential_adapter.dart';
```

- [ ] **Step 5: 退役 GrokAuthStore 复制逻辑**

`client/lib/services/cli/grok/provider/grok_auth_store.dart`：删除 `seedSessionAuth`（`:117-143`）、`authSourcePath`（`:147-160`）、`machineMarkerValue`（`:46`）及 `_digest`（`:165-166`）与 `crypto` import。保留 `loginRoot/loginHome/loginConfigDir/loginWorkspace/loginAuthPath/providerAuthDir/providerAuthPath/clearLoginAuth/hasLoginAuth/hasProviderAuth/restrictFile/_safe/_isNonEmptyFile`。类注释（`:10-17`）改为：

```dart
/// Grok login-home and provider-directory path helpers.
///
/// Credentials themselves are owned by `OAuthCredentialAuthority`; this class
/// no longer copies auth.json into session homes. Sessions receive a lease via
/// `GrokCredentialAdapter` instead.
```
删除 `writeProviderAuthFromLogin` / `importMachineAuth`（`:85-111`）—— 它们的职责已迁入 `OAuthCredentialAuthority.importFromLogin`。

> `GrokLoginDialog` 仍调用 `store.loginHome/loginConfigDir/loginWorkspace/clearLoginAuth`，保持不变。

- [ ] **Step 6: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/grok/grok_provider_materialize_test.dart test/services/cli/grok/grok_registry_test.dart test/services/cli/grok/grok_headless_test.dart`
Expected: PASS。

Run: `cd client && flutter analyze lib/services/cli/grok lib/app/bootstrap/cli_bootstrap_wiring.dart lib/services/cli/registry/built_in_cli_tools.dart lib/app/app_shell.dart`
Expected: `No issues found!`（若 `app_shell.dart` 因其他未提交改动报错，只修本任务引入的行）。

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/grok/grok_bootstrap_entry.dart \
  client/lib/app/bootstrap/cli_bootstrap_wiring.dart \
  client/lib/services/cli/registry/built_in_cli_tools.dart \
  client/lib/app/app_shell.dart \
  client/lib/services/cli/grok/capabilities/provider.dart \
  client/lib/services/cli/grok/provider/grok_auth_store.dart \
  client/test/services/cli/grok/grok_provider_materialize_test.dart
git commit -m "feat(grok): route provider auth through the credential authority"
```

---

## Task 7: ACP `auth_required` 恢复路径

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart:608`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `SessionCredentialCapability.onAuthRequired`（Task 2/5）
- Produces:
  - `AcpChatErrorKind.authRequired`
  - `AcpChatRuntimeCubit({..., Future<bool> Function(String sessionId)? authRecovery})`

- [ ] **Step 1: 写失败测试**

该测试文件已有 `late _FakeAcpRuntime runtime;`（`setUp` 里重建）、`bootCubit({...})` helper 与 `const _testStrings`。`_FakeAcpRuntime` 已有 `Object? startError`，`start()` 在 `startError != null` 时抛出 —— 不需要新 fake。

先给 `bootCubit` helper 的参数列表加一行、构造里加一行：

```dart
  AcpChatRuntimeCubit bootCubit({
    // ...existing optional params...
    Future<bool> Function(String sessionId)? authRecovery,
  }) {
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 's1',
      tool: CliTool.gemini,
      // ...existing args...
      authRecovery: authRecovery,
    )..ensureStrings(_testStrings);
    return cubit;
  }
```

在 `main()` 末尾加两个测试：

```dart
  test('auth_required recovers once when a fresh lease is available', () async {
    var recoveryCalls = 0;
    runtime.startError = acpd.RpcError(
      acpd.ErrorCode.authRequired.code,
      'auth required',
    );
    final cubit = bootCubit(
      authRecovery: (sessionId) async {
        recoveryCalls++;
        // The recovery re-runs start(); clear the injected error so the
        // retry succeeds.
        runtime.startError = null;
        return true;
      },
    );

    await cubit.start(
      executable: 'grok',
      sessionToolDir: '/tmp/grok',
      workingDirectory: '/workspace',
    );

    expect(recoveryCalls, 1);
    expect(runtime.started, isTrue);
    expect(cubit.state.phase, isNot(AcpChatPhase.ended));
    await cubit.close();
  });

  test('auth_required ends with authRequired when login is needed', () async {
    runtime.startError = acpd.RpcError(
      acpd.ErrorCode.authRequired.code,
      'auth required',
    );
    final cubit = bootCubit(
      authRecovery: (sessionId) async => false,
    );

    await cubit.start(
      executable: 'grok',
      sessionToolDir: '/tmp/grok',
      workingDirectory: '/workspace',
    );

    expect(cubit.state.phase, AcpChatPhase.ended);
    expect(cubit.state.error?.kind, AcpChatErrorKind.authRequired);
    await cubit.close();
  });
```

文件顶部已有 `import 'package:acpd/acpd.dart' as acpd;`（若无则补一条）。`AcpChatRuntimeCubit.start()` 的签名（`:535`）只接 `executable` / `sessionToolDir` / `workingDirectory` / `baseEnv` / `mcpServers` / `permissionPolicy`，**没有 `tool` 参数**（tool 是构造字段）。

- [ ] **Step 2: 运行确认失败**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: FAIL — `AcpChatRuntimeCubit` 没有 `authRecovery` 参数 / `AcpChatErrorKind.authRequired` 未定义。

- [ ] **Step 3: 实现恢复路径**

`client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`：

枚举（`:57`）加一个值：
```dart
  /// The agent reported ACP `auth_required` (-32000) and no fresh lease
  /// could be minted; the user must sign in under Settings → Providers.
  authRequired,
```

构造参数（`:174` 区块）加：
```dart
    this.authRecovery,
```
字段声明：
```dart
  final Future<bool> Function(String sessionId)? authRecovery;
```

把 `:620-626` 的分支替换为：

```dart
      if (error.code == acpd.ErrorCode.authRequired.code) {
        final recovered = await _recoverAuth(
          executable: executable,
          sessionToolDir: sessionToolDir,
          workingDirectory: effectiveWorkingDirectory,
          baseEnv: baseEnv,
          mcpServers: mcpServers,
          permissionPolicy: permissionPolicy,
          resumeSessionId: resumeId,
        );
        if (recovered) return;
        _endWith(
          AcpChatErrorKind.authRequired,
          _strings?.notLoggedIn ?? defaultAcpChatStrings.notLoggedIn,
        );
        return;
      }
```

新增私有方法（放在 `_endWith` 之前）：

```dart
  /// Re-mints a lease and retries the launch exactly once. `authRequired`
  /// from `session/new` is a recoverable credential problem, not a dead
  /// session — only a rejected refresh token ends the session.
  Future<bool> _recoverAuth({
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    required Map<String, String> baseEnv,
    required List<acpd.McpServer> mcpServers,
    required LaunchSecurityPolicy permissionPolicy,
    required String? resumeSessionId,
  }) async {
    final recovery = authRecovery;
    if (recovery == null) return false;
    final ok = await recovery(sessionId);
    if (!ok) return false;
    try {
      await _runtime.start(
        tool: this.tool,
        executable: executable,
        sessionToolDir: sessionToolDir,
        workingDirectory: workingDirectory,
        baseEnv: baseEnv,
        mcpServers: mcpServers,
        permissionPolicy: permissionPolicy,
        resumeSessionId: resumeSessionId,
      );
      return true;
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[acp-chat] session $sessionId auth recovery failed: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
```

> `_runtime.start` 的签名已核对（`client/lib/services/acp/acp_session_runtime.dart:153`），与上例及 `start()` 中已有的调用（`:559-569`）一致；`tool` 取 cubit 的构造字段。恢复不重放未完成 prompt —— 首版行为是重新建立连接，未发送的 prompt 由用户重发（见 spec「待确认」第 3 条）。

- [ ] **Step 4: 注入 recovery**

`client/lib/services/chat/launch/connect/acp_runtime_attach.dart`，在 `:608` 的 `AcpChatRuntimeCubit(` 参数列表加：

```dart
      authRecovery: (sessionId) async {
        final capability = _host.cliRegistry
            .capability<SessionCredentialCapability>(cli);
        if (capability == null) return false;
        return capability.onAuthRequired(
          providerId: launchProvider.isNotEmpty ? launchProvider : 'xai',
          sessionId: sessionId,
        );
      },
```

import 补：
```dart
import '../../../cli/registry/capabilities/session_credential_capability.dart';
```

- [ ] **Step 5: 运行确认通过 + analyze**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`
Expected: PASS。

Run: `cd client && flutter analyze lib/cubits/session/acp/acp_chat_runtime_cubit.dart lib/services/chat/launch/connect/acp_runtime_attach.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/lib/services/chat/launch/connect/acp_runtime_attach.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "feat(acp): recover from auth_required via a fresh credential lease"
```

---

## Task 8: 远程集成测试与验收

**Files:**
- Create: `client/test/integration/grok_credential_lease_remote_test.dart`

**Interfaces:**
- Consumes: Task 2–7 全部
- Produces: `@Tags(['integration'])` 端到端用例

- [ ] **Step 1: 写集成测试**

`client/test/integration/grok_credential_lease_remote_test.dart`：

```dart
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:teampilot/models/credential_lease.dart';
import 'package:teampilot/services/provider/credential_lease_endpoint.dart';
import 'package:teampilot/services/provider/oauth_credential_authority.dart';

import '../support/in_memory_filesystem.dart';

void main() {
  test('three concurrent seats share one refresh and all receive a lease',
      () async {
    final fs = InMemoryFilesystem();
    final authority = OAuthCredentialAuthority(
      fs: fs,
      basePath: '/tp',
      cliNamespace: 'grok',
      refresher: _CountingRefresher(),
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );
    await authority.importFromLogin(
      'xai',
      utf8.encode(jsonEncode({
        'scope': {
          'key': 'old',
          'refresh_token': 'rt-old',
          'expires_at': '2026-11-14T10:00:00Z',
        }
      })),
    );
    final endpoint = CredentialLeaseEndpoint(
      authority: authority,
      sessionProviderId: (_) => 'xai',
      now: () => DateTime.utc(2026, 11, 14, 11, 0, 0),
    );

    final responses = await Future.wait([
      for (final id in ['s1', 's2', 's3'])
        endpoint.serve(
          sessionId: id,
          busToken: 'bus-$id',
          providerId: 'xai',
          forceRefresh: false,
        ),
    ]);

    expect(responses.map((r) => r.statusCode), [200, 200, 200]);
    expect(responses.map((r) => r.body['access_token']).toSet(), {'fresh'});
    expect(jsonEncode(responses), isNot(contains('refresh_token')));
  });
}

final class _CountingRefresher implements CredentialRefresher {
  int calls = 0;

  @override
  Future<CredentialRefreshOutcome> refresh(String refreshToken) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return RefreshSucceeded(
      accessToken: 'fresh',
      refreshToken: 'rt-fresh',
      expiresAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
    );
  }
}
```

- [ ] **Step 2: 运行**

Run: `cd client && dart run tool/run_tests.dart test/integration/grok_credential_lease_remote_test.dart`
Expected: PASS。

> 真实 SSH 隧道验证按 `client/test/integration/remote_acp_prompt_docker_test.dart:267` 的 `HttpServer.bind` 模式补一条手工验收：在远程 seat 上 `curl` shim 使用的 `credential-lease.json` 端点，断言返回 200 且 body 无 `refresh_token`。该条需要 live SSH profile，标为手工验收项，不进 CI。

- [ ] **Step 3: 全量定向回归**

Run:
```bash
cd client && dart run tool/run_tests.dart \
  test/models/credential_lease_test.dart \
  test/services/provider/oauth_credential_authority_test.dart \
  test/services/provider/credential_lease_endpoint_test.dart \
  test/services/cli/grok \
  test/services/cli/registry/provider_credential_capability_test.dart \
  test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
```
Expected: 全部 PASS。

Run: `cd client && flutter analyze`
Expected: `No issues found!`（若报的是工作区里与本计划无关的未提交改动，只修本计划引入的问题）。

- [ ] **Step 4: 验收对照 spec**

逐条核对 `docs/superpowers/specs/2026-11-14-grok-credential-authority-design.md` 的「验收标准」：

1. 3 会话并发无 `invalid_grant` → Task 3 的 single-flight 测试 + Task 8 集成测试。
2. A 刷新后 B/C 不报未登录 → 同上的 epoch/single-flight 覆盖。
3. SSH 远程取 lease → Task 5 的 remote endpoint 测试 + 本任务手工验收。
4. 人为拒绝 RT → Task 3 `invalid_grant` 测试断言不写空凭证、统一 `rejected`；Task 7 落 `authRequired`。
5. 过期凭证启动前被拦截 → Task 5 `expired/rejected credential fails before launch` + Task 6 `probe` 测试。
6. `flutter analyze` 通过、无 `if (cli == …)` → 本任务 Step 3。

- [ ] **Step 5: Commit**

```bash
git add client/test/integration/grok_credential_lease_remote_test.dart
git commit -m "test(grok): cover concurrent leases and remote credential path"
```

- [ ] **Step 6: Stage 0 操作（无代码）**

在设置 → 服务商 → xai 重新登录（`grok login --device-auth`），或配置 `XAI_API_KEY`。这是解除当前阻塞的操作步骤，不产生 commit。

---

## 附录 B: 降级适配器（Task 1 结论为 `no` 时使用）

若 `grok agent stdio` 不回调 `auth_provider_command`，**不变量仍然成立**：RT 依旧只在控制面，会话只拿 access token。降级做法是 connect 时下发一个只含 access token 的 `auth.json`，`auth_required` 时重新下发。

替换 Task 5 的 `GrokCredentialAdapter.materialize` 中「写 shim + 注入 env」部分为：

```dart
    // Fallback: no external auth provider under ACP. Write an access-token-only
    // auth.json (NO refresh_token) that grok cannot rotate.
    final authPath = fs.pathContext.join(configDir, GrokConstants.authFileName);
    final lease = await leaseCredentials(
      providerId: providerId,
      sessionId: ctx.sessionId,
      forceRefresh: true,
    );
    final authJson = jsonEncode({
      'https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828': {
        'key': lease.accessToken,
        'expires_at': lease.expiresAt.toIso8601String(),
        'auth_mode': 'Oidc',
        // Deliberately no refresh_token: the CLI must not attempt a refresh.
      },
    });
    await fs.atomicWrite(authPath, authJson);
    _restrict(fs, authPath);

    return SessionHomeContribution(
      environment: {GrokConstants.homeEnvKey: configDir},
      warnings: const [],
    );
```

同时：
- 跳过 `GrokConstants.authProviderCommandEnvKey` 的注入（Task 5 Step 3 的 `environment` 里不再有该键）。
- `GrokCredentialAdapterTest` 中「injects GROK_AUTH_PROVIDER_COMMAND」用例改为断言 `auth.json` 存在、**不含** `refresh_token`、且 `environment` 不含 `GROK_AUTH_PROVIDER_COMMAND`。
- Task 7 的 `authRecovery` 仍调用 `authority.recover(...)`；恢复后 `_runtime.start` 重新执行 `materializeSessionHome`，从而重写 access-token-only `auth.json`。
- 会话内 access token 过期后 grok 会报 `auth_required`（无 RT 可刷新），由 Task 7 的恢复路径重连并重新下发。spec 的「不变量」不变，只是刷新时机从「CLI 主动回调」变成「重连时下发」。

其余任务（Task 2/3/4/6/7/8）**完全不变**。
