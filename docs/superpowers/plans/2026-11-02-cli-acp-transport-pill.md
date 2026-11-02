# CLI 传输胶囊与 ACP 范围放开 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 ACP 适用于个人、原生团队、混合团队与远程成员，并把设置页的 ACP 开关收进 CLI 卡片 header 的图标胶囊。

**Architecture:** 先拆三处后端门禁（会话级策略、临时会话构建、成员打标），再改设置卡片 UI 与文案，最后做一次纯重命名。每一层都能独立测试与回滚。

**Tech Stack:** Flutter/Dart（package `teampilot`）、`flutter_bloc`、`shared_ui`（`TpSegmentedControl` / `TpStatusBadge`）、`flutter_test` + `mocktail`。

## Global Constraints

- **禁止**直接 `flutter test`：一律 `cd client && dart run tool/run_tests.dart <path> [--plain-name ...]`。
- 单个测试文件验证：`cd client && dart run tool/run_tests.dart test/<path>_test.dart`。
- 收尾前必须跑：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
- l10n 只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，改完在 `client/` 下跑 `flutter gen-l10n`。
- 不新增 `print`；不改 `personalAcpDefaults` 的 JSON key（避免偏好迁移）。
- **不改** Android 平台门禁（`_isAndroid` 在两处保留）。
- 不做 ACP / PTY 能力对齐本身，不动 `CliLaunchSecurityCapability` 的档位语义。

---

### Task 1: 会话级 ACP 策略去掉 isPersonal

**Files:**
- Modify: `client/lib/services/chat/launch/session/launch_acp_policy.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart:811-870`
- Modify: `client/lib/services/automation/automation_dispatcher.dart:287-291`
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart:28-47,159-170`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart:986`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart:10-240`
- Test: `client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart:17-73`

**Interfaces:**
- Produces: `bool resolveLaunchAcp({required CliTool? cli, required bool requested, bool? isAndroidOverride})`
- Produces: `bool willLaunchAcp({required CliTool? cli, required bool requested, bool? isAndroidOverride})`
- `showLandingAcpPermissionChip` 签名不变，仅内部改调 `willLaunchAcp`。

- [ ] **Step 1: 改测试，写下期望的新行为**

把 `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` 中
`group('resolveLaunchAcp', ...)`（第 10-138 行）整体替换为：

```dart
  group('resolveLaunchAcp', () {
    test('true for desktop Claude, Cursor, Codex and OpenCode', () {
      for (final cli in [
        CliTool.claude,
        CliTool.cursor,
        CliTool.codex,
        CliTool.opencode,
      ]) {
        expect(
          resolveLaunchAcp(
            cli: cli,
            requested: true,
            isAndroidOverride: false,
          ),
          isTrue,
          reason: '$cli should honour the ACP preference on desktop',
        );
      }
    });

    test('false when not requested, ACP-only, null, or Android', () {
      expect(
        resolveLaunchAcp(
          cli: CliTool.claude,
          requested: false,
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        resolveLaunchAcp(
          cli: CliTool.gemini,
          requested: true,
          isAndroidOverride: false,
        ),
        isFalse,
        reason: 'Gemini is ACP-only and has no transport choice',
      );
      expect(
        resolveLaunchAcp(
          cli: null,
          requested: true,
          isAndroidOverride: false,
        ),
        isFalse,
      );
      expect(
        resolveLaunchAcp(
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: true,
        ),
        isFalse,
      );
    });
  });
```

同一文件里 `group('buildWorkspaceConversationCreateRequest', ...)` 的三处团队断言改为：

```dart
    test('team create keeps request.acp when requested', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
    });
```

```dart
    test('team create copies CLI seeds and keeps request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
        acp: true,
        seedClaudeMemberAcp: true,
        seedCodexMemberAcp: true,
        seedCursorMemberAcp: true,
        seedOpencodeMemberAcp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
      expect(request.seedClaudeMemberAcp, isTrue);
      expect(request.seedCodexMemberAcp, isTrue);
      expect(request.seedCursorMemberAcp, isTrue);
      expect(request.seedOpencodeMemberAcp, isTrue);
    });
```

`team create seed defaults match preference defaults` 用例保持 `expect(request.acp, isFalse)`
（未请求时不改默认）。

`client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart` 中把
`willLaunchPersonalAcp(` 全部替换为 `willLaunchAcp(`，并删掉每处的 `isPersonal: true,` 行。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart`
Expected: 编译失败，报 `No named parameter with the name 'isPersonal'` / `willLaunchAcp isn't defined`.

- [ ] **Step 3: 重写策略文件**

`client/lib/services/chat/launch/session/launch_acp_policy.dart` 全文替换为：

```dart
import 'dart:io' show Platform;

import '../../../../models/team_config.dart';
import '../../../cli/registry/capabilities/cli_transport_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

/// Final ACP flag for a launch.
///
/// [requested] only counts when the CLI declares both transports, on a platform
/// where ACP is available. Session scope (personal / native team / mixed team)
/// and member placement (local / remote) no longer restrict ACP — the CLI
/// preference is the single source of truth. ACP-only CLIs (Gemini, CodeBuddy)
/// are inferred by session create, so `requested` stays false for them.
bool resolveLaunchAcp({
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!requested || cli == null) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  return CliToolRegistry.builtIn()
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
}
```

- [ ] **Step 4: 更新四个调用点**

`client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`：
doc 注释改为「`acp` 会保留到任何会话范围（个人 / 原生团队 / 混合团队），只剩平台与该 CLI
是否可选两种约束」；`acp:` 实参改为：

```dart
    acp: resolveLaunchAcp(
      cli: cli,
      requested: acp,
      isAndroidOverride: isAndroidOverride,
    ),
```

`client/lib/services/automation/automation_dispatcher.dart:287`：

```dart
      final acp = resolveLaunchAcp(
        cli: simpleIdentity.cli,
        requested: _personalAcpDefaultFor(simpleIdentity.cli),
      );
```

`client/lib/pages/home_workspace/workspace/acp_compose_permission.dart:28-47`：

```dart
/// ACP-only CLIs (Gemini, CodeBuddy) always launch ACP; otherwise
/// [resolveLaunchAcp].
bool willLaunchAcp({
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (_isAndroid(isAndroidOverride)) return false;
  if (CliToolRegistry.builtIn().launchesAcpOnly(cli)) return true;
  return resolveLaunchAcp(
    cli: cli,
    requested: requested,
    isAndroidOverride: isAndroidOverride,
  );
}
```

同文件第 159-170 行改为：

```dart
  if (!showLandingAcpPermissionChip(
    isPersonal: isPersonal,
    cli: launchCli,
    requested: requested,
    stampedMembers: stampedMembers,
    isAndroidOverride: isAndroidOverride,
  )) {
    return null;
  }
```

并在 `showLandingAcpPermissionChip` 内部把 `willLaunchPersonalAcp(` 改成 `willLaunchAcp(`，
删掉它的 `isPersonal: true,` 实参。

`client/lib/pages/home_workspace/workspace/unbound_compose_body.dart:986` 同样改名并删掉
`isPersonal: true,`。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart`
Expected: PASS

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`
Expected: PASS（`resolveMemberBindingAcp` / `stampMemberAcp` 两组仍然通过）

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/chat/launch/session/launch_acp_policy.dart \
  client/lib/pages/home_workspace/workspace/workspace_session_actions.dart \
  client/lib/services/automation/automation_dispatcher.dart \
  client/lib/pages/home_workspace/workspace/acp_compose_permission.dart \
  client/lib/pages/home_workspace/workspace/unbound_compose_body.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart \
  client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart
git commit -m "feat(acp): allow ACP launch for every session scope"
```

---

### Task 2: 成员打标去掉团队模式与目标限制

**Files:**
- Modify: `client/lib/services/chat/launch/session/member_acp_stamp.dart`
- Modify: `client/lib/services/chat/launch/session/session_launch_coordinator.dart:189-200`
- Modify: `client/lib/repositories/session_repository.dart:850`
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart:115`
- Modify: `client/lib/services/chat/launch/pre_send/local_binary_requirements.dart:67-73`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart:314-320`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart:242-414`

**Interfaces:**
- Produces: `bool resolveMemberBindingAcp({required CliTool? cli, required bool requested, bool? isAndroidOverride})`
- Produces: `bool shouldAttachMemberAcp({required AppSession session, required String memberId, bool? isAndroidOverride})`
- Produces: `List<SessionMemberBinding> stampMemberAcp({required List<SessionMemberBinding> members, required Map<String, String> memberTargets, required bool seedClaudeMemberAcp, required bool seedCodexMemberAcp, bool seedCursorMemberAcp = true, bool seedOpencodeMemberAcp = true, LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess, bool? isAndroidOverride})`
- 三个函数的 `teamMode` / `targetId` / `team` 参数全部删除。

- [ ] **Step 1: 改测试**

`client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` 中
`group('resolveMemberBindingAcp', ...)` 替换为：

```dart
  group('resolveMemberBindingAcp', () {
    test('follows requested for every team mode and target; Gemini always', () {
      bool resolve({
        CliTool? cli = CliTool.claude,
        bool requested = true,
        bool android = false,
      }) => resolveMemberBindingAcp(
        cli: cli,
        requested: requested,
        isAndroidOverride: android,
      );

      expect(resolve(), isTrue);
      expect(resolve(requested: false), isFalse);
      expect(resolve(cli: CliTool.codex), isTrue);
      expect(resolve(cli: CliTool.gemini, requested: false), isTrue);
      expect(resolve(cli: CliTool.opencode), isTrue);
      expect(resolve(cli: CliTool.opencode, requested: false), isFalse);
      expect(resolve(cli: CliTool.flashskyai), isFalse);
      expect(resolve(android: true), isFalse);
    });
  });
```

`group('stampMemberAcp', ...)` 的 `stamp` 辅助去掉 `mode` / `targets` 之外的团队参数：
把 `stamp()` 里的 `teamMode: mode,` 删除，并删掉 `TeamMode mode = TeamMode.mixed,` 形参。
`test('Codex follows seed and non-local or native seats stay false', ...)` 替换为：

```dart
    test('non-local and native seats follow the seed', () {
      expect(
        stamp(
          members: [member(CliTool.claude, 'lead')],
          targets: const {'lead': 'ssh:prod'},
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.gemini, 'gem')],
          targets: const {'gem': 'ssh:prod'},
        ).single.acp,
        isTrue,
      );
      expect(
        stamp(
          members: [member(CliTool.claude, 'lead')],
          android: true,
        ).single.acp,
        isFalse,
      );
    });
```

`group('shouldAttachMemberAcp', ...)` 两处调用删掉 `team:` 与 `targetId:` 实参，把
`targetId: 'ssh:prod'` 用例改为断言 `isTrue`（保留 local 用例）：

```dart
    test('attaches for any target when the seat is ACP', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        createdAt: 1,
        sessionTeam: 't1',
        members: const [
          SessionMemberBinding(
            rosterMemberId: 'lead',
            taskId: 't',
            cli: CliTool.claude,
            acp: true,
          ),
        ],
      );
      expect(
        shouldAttachMemberAcp(session: session, memberId: 'lead'),
        isTrue,
      );
    });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart --plain-name "resolveMemberBindingAcp"`
Expected: 编译失败，`isn't defined` / 多余的命名参数。

- [ ] **Step 3: 改 `member_acp_stamp.dart`**

顶部 import 删掉 `../../../../models/runtime_target.dart`。三个函数替换为：

```dart
bool _memberAcpGates({
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (_isAndroid(isAndroidOverride)) return false;
  if (cli == null) return false;
  return CliToolRegistry.builtIn().capability<AcpCapability>(cli) != null;
}

bool resolveMemberBindingAcp({
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) {
  if (!_memberAcpGates(cli: cli, isAndroidOverride: isAndroidOverride)) {
    return false;
  }
  if (CliToolRegistry.builtIn().launchesAcpOnly(cli)) return true;
  return requested;
}
```

`stampMemberAcp` 删掉 `required TeamMode teamMode,`，内部调用改为：

```dart
            : resolveMemberBindingAcp(
                cli: member.cli,
                requested: _requestedMemberAcpSeed(
                  member.cli,
                  seedClaudeMemberAcp: seedClaudeMemberAcp,
                  seedCodexMemberAcp: seedCodexMemberAcp,
                  seedCursorMemberAcp: seedCursorMemberAcp,
                  seedOpencodeMemberAcp: seedOpencodeMemberAcp,
                ),
                isAndroidOverride: isAndroidOverride,
              ),
```

`shouldAttachMemberAcp` 替换为：

```dart
bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  bool? isAndroidOverride,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpGates(cli: cli, isAndroidOverride: isAndroidOverride);
}
```

同时更新 `stampMemberAcp` 的文档注释：删掉「Native teams stay false.」，改成
「Every seat follows the CLI preference; only the platform and the CLI's ACP
capability gate it.」删掉因门禁移除而不再使用的 import（`runtime_target.dart`；
`team_config.dart` 若 `TeamMode` 已无引用也一并删），由 `flutter analyze` 兜底确认。

- [ ] **Step 4: 更新四个调用点**

`session_launch_coordinator.dart:189` 删掉 `teamMode: request.team!.teamMode,`。
`session_repository.dart:850` 删掉 `teamMode:` 实参。
`acp_compose_permission.dart:115` 删掉 `teamMode:` 实参。
`local_binary_requirements.dart:67` 改为：

```dart
      final memberAcp = resolveMemberBindingAcp(
        cli: cli,
        requested: acpSeed?.call(cli) ?? false,
        isAndroidOverride: isAndroidOverride,
      );
```

同文件第 32-37 行的注释改成「`acpSeed` 是该 CLI 的 ACP 偏好；成员会跑 ACP 且 CLI 需要
独立适配器时，追加一条 `kind: adapter` 要求」，删掉「Mixed teams only — native teams
and remote members always use the terminal」。

`acp_runtime_attach.dart:314-320` 改为：

```dart
    if (team == null ||
        !shouldAttachMemberAcp(
          session: session,
          memberId: member.id,
        )) {
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`
Expected: PASS

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/pre_send`
Expected: PASS（`local_binary_requirements` 相关用例不受影响）

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/chat/launch/session/member_acp_stamp.dart \
  client/lib/services/chat/launch/session/session_launch_coordinator.dart \
  client/lib/repositories/session_repository.dart \
  client/lib/pages/home_workspace/workspace/acp_compose_permission.dart \
  client/lib/services/chat/launch/pre_send/local_binary_requirements.dart \
  client/lib/services/chat/launch/connect/acp_runtime_attach.dart \
  client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "feat(acp): stamp member ACP for native teams and remote targets"
```

---

### Task 3: 团队临时会话保留 acp 标记

**Files:**
- Modify: `client/lib/services/chat/launch/session/session_provisional_builder.dart:45-49`
- Test: `client/test/services/chat/launch/session_provisional_builder_test.dart:49-60`

**Interfaces:**
- 无签名变化；`buildProvisionalSession` 的 `acp` 语义变为「与会话范围无关」。

- [ ] **Step 1: 改测试**

把 `team session is always acp false` 替换为两个用例：

```dart
  test('team session keeps acp true when requested', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: false,
      usesPosixPaths: true,
      cli: CliTool.claude,
      sessionTeamId: 'team-1',
      acp: true,
    );
    expect(session.acp, isTrue);
  });

  test('team session defaults to acp false when not requested', () {
    final session = buildProvisionalSession(
      sessionId: 's1',
      workspace: workspace,
      isPersonal: false,
      usesPosixPaths: true,
      cli: CliTool.claude,
      sessionTeamId: 'team-1',
    );
    expect(session.acp, isFalse);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_provisional_builder_test.dart`
Expected: FAIL — `team session keeps acp true when requested` 得到 false。

- [ ] **Step 3: 改实现**

`session_provisional_builder.dart:45-49` 替换为：

```dart
  final resolvedAcp =
      (acp ?? false) ||
      CliToolRegistry.builtIn().launchesAcpOnly(identity?.cli ?? cli);
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_provisional_builder_test.dart`
Expected: PASS（4 个用例全绿）

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/chat/launch/session/session_provisional_builder.dart \
  client/test/services/chat/launch/session_provisional_builder_test.dart
git commit -m "feat(acp): keep the ACP flag on team sessions"
```

---

### Task 4: 设置卡片 header 胶囊

**Files:**
- Modify: `client/lib/pages/config/cli_readiness_card.dart:544-561,608-685`
- Modify: `client/lib/l10n/app_en.arb:4750-4751`（删 2 条，加 2 条）
- Modify: `client/lib/l10n/app_zh.arb:4054-4055`（同上）
- Regenerate: `client/lib/l10n/app_localizations*.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart:527-539`

**Interfaces:**
- Consumes: `SessionPreferencesCubit.acpDefaultFor(CliTool)` / `setAcpDefaultFor(CliTool, bool)`
  —— 本任务先用现有方法名 `personalAcpDefaultFor` / `setPersonalAcpDefaultFor`，Task 5 统一改名。
- Produces: 私有 widget `_CliTransportPill({required bool acp, required ValueChanged<bool> onChanged})`

- [ ] **Step 1: 改测试**

`client/test/pages/config/cli_config_section_test.dart:527` 的
`Gemini has no personal ACP switch` 替换为三个用例：

```dart
  testWidgets('ACP pill toggles the CLI transport default', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrapCard(cubit));
    await tester.pump();
    expect(cubit.personalAcpDefaultFor(CliTool.claude), isTrue);

    await tester.tap(find.byIcon(Icons.terminal_rounded));
    await tester.pumpAndSettle();
    expect(cubit.personalAcpDefaultFor(CliTool.claude), isFalse);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    expect(cubit.personalAcpDefaultFor(CliTool.claude), isTrue);
  });

  testWidgets('ACP pill replaces the old preference row', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrapCard(cubit));
    await tester.pump();

    expect(
      find.byKey(AppKeys.personalAcpSwitchFor(CliTool.claude)),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('Gemini has no ACP pill', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(
      find.byKey(AppKeys.personalAcpSwitchFor(CliTool.gemini)),
      findsNothing,
    );
    expect(find.byKey(AppKeys.claudePersonalAcpSwitch), findsOneWidget);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name "ACP pill"`
Expected: FAIL — 找不到 `Icons.terminal_rounded`。

- [ ] **Step 3: 改 l10n**

`client/lib/l10n/app_en.arb`：删除 `personalAcpSwitchLabel`、`personalAcpSwitchCaption`、
`claudePersonalAcpAndroidDisabled`、`codexPersonalAcpAndroidDisabled` 四条，新增：

```json
  "cliTransportDefaultChat": "New sessions default to chat (ACP)",
  "cliTransportDefaultTerminal": "New sessions default to the terminal (PTY)",
```

`client/lib/l10n/app_zh.arb`：删除同四条的 zh 版本，新增：

```json
  "cliTransportDefaultChat": "新会话默认使用对话（ACP）",
  "cliTransportDefaultTerminal": "新会话默认使用终端（PTY）",
```

Run: `cd client && flutter gen-l10n`
Expected: `lib/l10n/app_localizations*.dart` 更新，旧 getter 消失、新 getter 出现。

- [ ] **Step 4: 改 header**

`cli_readiness_card.dart:544-561` 的 `Row` 末段改为：

```dart
              TpStatusBadge(
                label: chipLabel,
                tone: kind == CliReadinessChipKind.ready
                    ? TpStatusBadgeTone.success
                    : TpStatusBadgeTone.warning,
              ),
              if (_canChooseTransport && !_isAndroid) ...[
                const SizedBox(width: 10),
                KeyedSubtree(
                  key: AppKeys.personalAcpSwitchFor(widget.cli),
                  child: _CliTransportPill(
                    acp: cubit.personalAcpDefaultFor(widget.cli),
                    onChanged: (value) =>
                        cubit.setPersonalAcpDefaultFor(widget.cli, value),
                  ),
                ),
              ],
```

- [ ] **Step 5: 删除偏好行**

`cli_readiness_card.dart:622` 的 `final showSwitch = _canChooseTransport;` 删除；
`cli_readiness_card.dart:666-682` 整段 `if (showSwitch) TpPreferenceRow(...)` 删除。

`_buildAcpBlock` 里 `TpPreferenceRow` 用到的 `l10n` 仍然需要（ACP 路径行在用），不要删参数。

顶部 `if (_separateAdapter || _canChooseTransport) ...[` （第 592 行）改成
`if (_separateAdapter) ...[`——偏好行搬走后，没有独立适配器的 CLI 在这个 block 里已经
没有内容，保留原条件只会多出一个 12px 间隔。

- [ ] **Step 6: 加胶囊 widget**

文件末尾（`_remoteSshProfile` 之前）加入：

```dart
/// Default-transport pill: chat (ACP) on the left, terminal (PTY) on the right.
///
/// Mirrors the in-session toggle in
/// `pages/chat/session_workbench_view_toggle.dart` so settings and session use
/// the same visual language: 36×28 icon segments, main-colour active chip.
class _CliTransportPill extends StatelessWidget {
  const _CliTransportPill({required this.acp, required this.onChanged});

  final bool acp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpSegmentedControl(
      key: ValueKey(acp),
      totalSwitches: 2,
      initialLabelIndex: acp ? 0 : 1,
      labels: const ['', ''],
      icons: const [
        Icons.chat_bubble_outline_rounded,
        Icons.terminal_rounded,
      ],
      tooltips: [
        l10n.cliTransportDefaultChat,
        l10n.cliTransportDefaultTerminal,
      ],
      minWidth: 32,
      minHeight: 28,
      customWidths: const [36, 36],
      onToggle: (index) {
        if (index == null) return;
        final next = index == 0;
        if (next == acp) return;
        onChanged(next);
      },
    );
  }
}
```

- [ ] **Step 7: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`
Expected: PASS（含既有的 ACP 路径行用例）

- [ ] **Step 8: 提交**

```bash
git add client/lib/pages/config/cli_readiness_card.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "feat(settings): move the CLI transport choice into a header pill"
```

---

### Task 5: 去掉命名里的 personal

**Files:**
- Modify: `client/lib/models/session_preferences.dart:156-161`
- Modify: `client/lib/cubits/session_preferences_cubit.dart:198-202,370-390`
- Modify: `client/lib/services/automation/automation_dispatcher.dart:51,66-67,87,290`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart:15-39`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart:891-897`
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart:203-206`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart:179`
- Modify: `client/lib/app/app_shell.dart:2602`
- Modify: `client/lib/pages/config/cli_readiness_card.dart`（Task 4 写入的调用）
- Test: `client/test/models/session_preferences_test.dart`

**Interfaces:**
- Produces: `bool SessionPreferences.acpDefaultFor(CliTool)`
- Produces: `SessionPreferences SessionPreferences.withAcpDefault(CliTool, bool)`
- Produces: `bool SessionPreferencesCubit.acpDefaultFor(CliTool)`
- Produces: `Future<void> SessionPreferencesCubit.setAcpDefaultFor(CliTool, bool)`
- Produces: `bool readAcpDefault(BuildContext, CliTool?)`

- [ ] **Step 1: 机械重命名**

在 `client/` 下执行（只改标识符，不动 JSON key）：

```bash
cd client && grep -rl "personalAcpDefaultFor\|withPersonalAcpDefault\|setPersonalAcpDefaultFor\|readPersonalAcpDefault\|readClaudePersonalAcpDefault\|readCodexPersonalAcpDefault" lib test
```

对列出的每个文件做替换：

| 旧 | 新 |
|---|---|
| `personalAcpDefaultFor` | `acpDefaultFor` |
| `withPersonalAcpDefault` | `withAcpDefault` |
| `setPersonalAcpDefaultFor` | `setAcpDefaultFor` |
| `readPersonalAcpDefault` | `readAcpDefault` |
| `readClaudePersonalAcpDefault` | `readClaudeAcpDefault` |
| `readCodexPersonalAcpDefault` | `readCodexAcpDefault` |

**不要改** `personalAcpDefaults`（字段与 JSON key）、`SessionPreferences.copyWith` 的
`personalAcpDefaults` 形参、`AppKeys.personalAcpSwitchFor`。

`session_preferences.dart` 的两个方法改名后应为：

```dart
  /// Whether new sessions for [cli] launch as ACP chat.
  bool acpDefaultFor(CliTool cli) => personalAcpDefaults[cli.value] ?? true;

  SessionPreferences withAcpDefault(CliTool cli, bool value) =>
      copyWith(personalAcpDefaults: {...personalAcpDefaults, cli.value: value});
```

- [ ] **Step 2: 修文档注释**

`claude_acp_launch_switch.dart` 里
`/// Current settings default for "personal Claude uses ACP"` 改为
`/// Current settings default for "this CLI uses ACP"`；`SessionPreferences` 中
`/// Whether new personal sessions for [cli] launch as ACP chat.` 改为
`/// Whether new sessions for [cli] launch as ACP chat.`

- [ ] **Step 3: 静态检查**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found（无 unused import / 未定义标识符）

- [ ] **Step 4: 跑受影响测试**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart`
Expected: PASS

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add -A client/lib client/test
git commit -m "refactor(acp): drop the personal prefix from the transport preference"
```

---

## 收尾验收

- [ ] `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
- [ ] 手动：桌面新建个人 Claude 会话 → 默认无终端；切到终端 → 新建走 PTY
- [ ] 手动：桌面新建原生 Claude 团队会话 → lead 与成员均无终端面板，发一条指令能送达
- [ ] 手动：SSH 工作区建团队会话 → 成员走远端 ACP（按 `docs/remote-acp-adapter-smoke.md` 前三项）
- [ ] 手动：360dp 宽度下设置页 header 不溢出，标题省略、徽章与胶囊完整
- [ ] 手动：Android 上不出现胶囊，行为与改动前一致
