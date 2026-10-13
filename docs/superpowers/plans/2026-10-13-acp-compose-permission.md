# ACP Compose Permission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the compose permission chip on ACP Landing and ACP sessions/seats so the user can pick Ask vs Full access, persisted as a session/seat fact plus a global preference.

**Architecture:** `CliLaunchSecurityCapability.policiesFor(acp:)` is the runtime axis. PTY stays `{fullAccess}`. Every CLI with `AcpCapability` declares `{ask, fullAccess}` for ACP. Handshake auto-allows all allowable `session/request_permission`; after open, Full access auto-allows and Ask surfaces `AcpPermissionCard` except teammate-bus. Compose pages only consume a helper-built `ComposePermissionControl`.

**Tech Stack:** Flutter/Dart (`teampilot`), vendored `acpd`, existing `ComposePermissionChip` / `AcpAgentSession` / `SessionPreferencesCubit`.

**Spec:** `docs/superpowers/specs/2026-10-13-acp-compose-permission-design.md`

## Global Constraints

- PTY product policy stays full-access-only. Do not restore PTY permission flags or continue-override permission fields.
- No settings-page switch. No per-CLI permission preference.
- No `if (cli == …)` in compose pages or `services/acp/*`. Gemini-as-ACP belongs in `willLaunchPersonalAcp` next to `resolveLaunchAcp`.
- Handshake (`session/new`) always auto-allows allowable permissions. Ask never pops a card during handshake.
- teammate-bus / host MCP always auto-allowed after open.
- User copy → `client/lib/l10n/app_en.arb` + `app_zh.arb` only. Diagnostics → `AppLogger`. No `print`.
- Tests: `cd client && dart run tool/run_tests.dart <paths>`. Never `flutter test` directly.
- Inner loop: one test file (`--plain-name` to narrow). Full suite only before claiming done, in the background.
- Do not grow `unbound_compose_body.dart`, `session_chat_compose_section.dart`, `acp_session.dart`, or `acp_chat_runtime_cubit.dart` with policy branching; extract helpers.

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/launch_security_policy.dart` | `LaunchSecurityPolicy.ask` + named-id codec |
| `client/lib/services/cli/registry/capabilities/cli_launch_security_capability.dart` | `policiesFor`; `AcpAskFullAccessCliLaunchSecurityCapability` |
| `client/lib/services/cli/{gemini,claude,cursor,codex}/*_tool.dart` | Default `launchSecurity` for ACP CLIs |
| `client/lib/models/session_preferences.dart` + cubit | `acpPermissionDefault` |
| `client/lib/models/app_session.dart` | Personal `acpPermission` |
| `client/lib/models/session_member_binding.dart` | Mixed-seat `acpPermission` |
| `client/lib/services/chat/launch/session/member_acp_stamp.dart` | Stamp seat policy on ACP bindings |
| `client/lib/services/chat/session/session_create_request.dart` | `acpPermission` seed |
| `client/lib/repositories/session_repository.dart` | Create + `updateAcpPermission` |
| `client/lib/services/acp/acp_host_mcp_permission.dart` | `allowNonHost` auto-allow |
| `client/lib/services/chat/team_bus/teammate_bus_permission.dart` | Raw tool-call host-MCP check |
| `client/lib/services/acp/acp_connection.dart` | Handshake always auto-allow |
| `client/lib/services/acp/acp_session.dart` | Policy-gated auto-allow + `setPermissionPolicy` |
| `client/lib/services/acp/acp_session_runtime.dart` | `start(permissionPolicy:)` + `setPermissionPolicy` |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | Forward policy; remove cubit bus auto-allow |
| `client/lib/services/chat/launch/connect/acp_runtime_attach.dart` | Pass session/seat policy into `start` |
| `client/lib/widgets/compose/compose_permission_chip.dart` + `compose_chrome.dart` | Render `.ask` |
| `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart` | Visibility + control builder + apply |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Ask / Full access labels |

---

### Task 1: `LaunchSecurityPolicy.ask` named-id codec

**Files:**
- Modify: `client/lib/models/launch_security_policy.dart`
- Test: `client/test/models/launch_security_policy_test.dart`

**Interfaces:**
- Consumes: existing `LaunchSecurityPolicy` / `LaunchApprovalPolicy.ask`
- Produces:
  - `LaunchSecurityPolicy.ask` (`approval: ask`, `sandbox: fullAccess`, `hookTrust: cliDefault`)
  - `String? acpPermissionToJson(LaunchSecurityPolicy policy)` — `'ask'` or `null`
  - `LaunchSecurityPolicy acpPermissionFromJson(Object? value)` — `'ask'` → ask, anything else → fullAccess

- [ ] **Step 1: Write the failing test**

Add to `client/test/models/launch_security_policy_test.dart`:

```dart
test('ask named preset is not dangerous execution', () {
  expect(
    LaunchSecurityPolicy.ask,
    const LaunchSecurityPolicy(
      approval: LaunchApprovalPolicy.ask,
      sandbox: LaunchSandboxPolicy.fullAccess,
      hookTrust: LaunchHookTrustPolicy.cliDefault,
    ),
  );
  expect(LaunchSecurityPolicy.ask.requiresDangerousExecution, isFalse);
});

test('acp permission named-id codec omits fullAccess and maps unknown to fullAccess', () {
  expect(acpPermissionToJson(LaunchSecurityPolicy.fullAccess), isNull);
  expect(acpPermissionToJson(LaunchSecurityPolicy.ask), 'ask');
  expect(acpPermissionFromJson(null), LaunchSecurityPolicy.fullAccess);
  expect(acpPermissionFromJson('fullAccess'), LaunchSecurityPolicy.fullAccess);
  expect(acpPermissionFromJson('ask'), LaunchSecurityPolicy.ask);
  expect(acpPermissionFromJson('nope'), LaunchSecurityPolicy.fullAccess);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/models/launch_security_policy_test.dart --plain-name 'ask named preset'`

Expected: FAIL (undefined `LaunchSecurityPolicy.ask` / codec)

- [ ] **Step 3: Write minimal implementation**

In `client/lib/models/launch_security_policy.dart`, after `autoApproveWorkspaceWriteTrusted`:

```dart
  /// ACP client-side ask: show permission cards. Not a PTY sandbox mode.
  static const ask = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.ask,
    sandbox: LaunchSandboxPolicy.fullAccess,
    hookTrust: LaunchHookTrustPolicy.cliDefault,
  );
```

At the bottom of the same file:

```dart
String? acpPermissionToJson(LaunchSecurityPolicy policy) =>
    policy == LaunchSecurityPolicy.ask ? 'ask' : null;

LaunchSecurityPolicy acpPermissionFromJson(Object? value) =>
    value == 'ask' ? LaunchSecurityPolicy.ask : LaunchSecurityPolicy.fullAccess;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/launch_security_policy_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/launch_security_policy.dart client/test/models/launch_security_policy_test.dart
git commit -m "Add ACP Ask launch-security preset and named-id codec."
```

---

### Task 2: Runtime-aware launch-security capability

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/cli_launch_security_capability.dart`
- Modify: `client/lib/services/cli/gemini/gemini_tool.dart` (default `launchSecurity`)
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/test/services/cli/registry/cli_launch_security_capability_test.dart`
- Modify: `client/test/services/cli/claude_launch_capabilities_test.dart` (add `.ask` to the reject list)
- Modify: the matching reject-list tests in `flashskyai_launch_capabilities_test.dart`, `codex_launch_capabilities_test.dart`, `cursor_launch_capabilities_test.dart`, `opencode_launch_capabilities_test.dart`

**Interfaces:**
- Consumes: `LaunchSecurityPolicy.ask` / `.fullAccess` from Task 1; `AcpCapability` presence on CLI definitions
- Produces:
  - `Set<LaunchSecurityPolicy> policiesFor({required bool acp})`
  - `bool supportsUserConfigurationFor({required bool acp})`
  - `AcpAskFullAccessCliLaunchSecurityCapability` — PTY `{fullAccess}`, ACP `{ask, fullAccess}`
  - `FullAccessOnlyCliLaunchSecurityCapability.policiesFor` returns `{fullAccess}` for both runtimes
  - Existing `supportedPolicies` remains the PTY set (`{fullAccess}`)

- [ ] **Step 1: Write the failing test**

Replace `client/test/services/cli/registry/cli_launch_security_capability_test.dart` contents with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_launch_security_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('PTY security stays full-access-only for every CLI', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      final capability = registry.launchSecurityFor(cli);
      expect(capability.supportsUserConfiguration, isFalse);
      expect(capability.supportedPolicies, {LaunchSecurityPolicy.fullAccess});
      expect(capability.policiesFor(acp: false), {
        LaunchSecurityPolicy.fullAccess,
      });
      expect(capability.supportsUserConfigurationFor(acp: false), isFalse);
    }
  });

  test('ACP-capable CLIs expose ask+fullAccess; others stay fullAccess', () {
    final registry = CliToolRegistry.builtIn();
    for (final cli in CliTool.values) {
      final capability = registry.launchSecurityFor(cli);
      final hasAcp = registry.capability<AcpCapability>(cli) != null;
      if (hasAcp) {
        expect(capability, isA<AcpAskFullAccessCliLaunchSecurityCapability>());
        expect(capability.policiesFor(acp: true), {
          LaunchSecurityPolicy.ask,
          LaunchSecurityPolicy.fullAccess,
        });
        expect(capability.supportsUserConfigurationFor(acp: true), isTrue);
      } else {
        expect(capability.policiesFor(acp: true), {
          LaunchSecurityPolicy.fullAccess,
        });
        expect(capability.supportsUserConfigurationFor(acp: true), isFalse);
      }
    }
  });
}
```

In each CLI `assembler rejects every non-full-access policy` test, add `LaunchSecurityPolicy.ask` to the `for (final policy in const [ ... ])` list.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/cli_launch_security_capability_test.dart`

Expected: FAIL (`policiesFor` missing and/or Gemini still `FullAccessOnly`)

- [ ] **Step 3: Write minimal implementation**

In `cli_launch_security_capability.dart`:

```dart
abstract interface class CliLaunchSecurityCapability implements CliCapability {
  bool get supportsUserConfiguration;
  Set<LaunchSecurityPolicy> get supportedPolicies;
  Set<LaunchSecurityPolicy> policiesFor({required bool acp});
  bool supportsUserConfigurationFor({required bool acp}) =>
      policiesFor(acp: acp).length > 1;
}

final class FullAccessOnlyCliLaunchSecurityCapability
    implements CliLaunchSecurityCapability {
  const FullAccessOnlyCliLaunchSecurityCapability();

  static final Set<LaunchSecurityPolicy> _supportedPolicies = Set.unmodifiable({
    LaunchSecurityPolicy.fullAccess,
  });

  @override
  bool get supportsUserConfiguration => false;

  @override
  Set<LaunchSecurityPolicy> get supportedPolicies => _supportedPolicies;

  @override
  Set<LaunchSecurityPolicy> policiesFor({required bool acp}) =>
      _supportedPolicies;
}

final class AcpAskFullAccessCliLaunchSecurityCapability
    implements CliLaunchSecurityCapability {
  const AcpAskFullAccessCliLaunchSecurityCapability();

  static final Set<LaunchSecurityPolicy> _pty = Set.unmodifiable({
    LaunchSecurityPolicy.fullAccess,
  });
  static final Set<LaunchSecurityPolicy> _acp = Set.unmodifiable({
    LaunchSecurityPolicy.ask,
    LaunchSecurityPolicy.fullAccess,
  });

  @override
  bool get supportsUserConfiguration => false;

  @override
  Set<LaunchSecurityPolicy> get supportedPolicies => _pty;

  @override
  Set<LaunchSecurityPolicy> policiesFor({required bool acp}) =>
      acp ? _acp : _pty;
}
```

Change the default `launchSecurity:` in `GeminiCliTool`, `ClaudeCliTool`, `CursorCliTool`, and `CodexCliTool` to `const AcpAskFullAccessCliLaunchSecurityCapability()`. Leave FlashskyAI and OpenCode on `FullAccessOnly` unless that definition already registers `AcpCapability` — if it does, switch it too (the test is capability-driven).

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/cli_launch_security_capability_test.dart test/services/cli/claude_launch_capabilities_test.dart test/services/cli/cursor_launch_capabilities_test.dart test/services/cli/codex_launch_capabilities_test.dart test/services/cli/flashskyai_launch_capabilities_test.dart test/services/cli/opencode_launch_capabilities_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/cli_launch_security_capability.dart client/lib/services/cli/gemini/gemini_tool.dart client/lib/services/cli/claude/claude_tool.dart client/lib/services/cli/cursor/cursor_tool.dart client/lib/services/cli/codex/codex_tool.dart client/test/services/cli/registry/cli_launch_security_capability_test.dart client/test/services/cli/claude_launch_capabilities_test.dart client/test/services/cli/cursor_launch_capabilities_test.dart client/test/services/cli/codex_launch_capabilities_test.dart client/test/services/cli/flashskyai_launch_capabilities_test.dart client/test/services/cli/opencode_launch_capabilities_test.dart
git commit -m "Declare ACP Ask+Full-access on ACP-capable CLI security."
```

---

### Task 3: Global `acpPermissionDefault` preference

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Test: `client/test/models/session_preferences_test.dart`
- Test: `client/test/cubits/session_preferences_cubit_test.dart`

**Interfaces:**
- Consumes: `acpPermissionToJson` / `acpPermissionFromJson` from Task 1
- Produces:
  - `SessionPreferences.acpPermissionDefault` (`LaunchSecurityPolicy`, default `fullAccess`)
  - JSON key `acpPermissionDefault`: omit when fullAccess; `"ask"` when ask
  - `SessionPreferencesCubit.setAcpPermissionDefault(LaunchSecurityPolicy value)`

- [ ] **Step 1: Write the failing tests**

Add to `session_preferences_test.dart`:

```dart
    test('acpPermissionDefault defaults fullAccess and round-trips ask', () {
      expect(
        SessionPreferences().acpPermissionDefault,
        LaunchSecurityPolicy.fullAccess,
      );
      expect(
        SessionPreferences.fromJson(const {}).acpPermissionDefault,
        LaunchSecurityPolicy.fullAccess,
      );
      expect(
        SessionPreferences().toJson().containsKey('acpPermissionDefault'),
        isFalse,
      );
      final ask = SessionPreferences(
        acpPermissionDefault: LaunchSecurityPolicy.ask,
      );
      expect(ask.toJson()['acpPermissionDefault'], 'ask');
      expect(
        SessionPreferences.fromJson(ask.toJson()).acpPermissionDefault,
        LaunchSecurityPolicy.ask,
      );
    });
```

Add to `session_preferences_cubit_test.dart` (same `makeCubit` harness as the Cursor test):

```dart
  test('setAcpPermissionDefault persists ask', () async {
    final cubit = await makeCubit();
    await cubit.load();
    expect(
      cubit.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.fullAccess,
    );
    await cubit.setAcpPermissionDefault(LaunchSecurityPolicy.ask);
    expect(
      cubit.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.ask,
    );
    final cubit2 = await makeCubit();
    await cubit2.load();
    expect(
      cubit2.state.preferences.acpPermissionDefault,
      LaunchSecurityPolicy.ask,
    );
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart --plain-name 'acpPermissionDefault'`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Thread `this.acpPermissionDefault = LaunchSecurityPolicy.fullAccess` through the constructor, `fromJson` (`acpPermissionFromJson(json['acpPermissionDefault'])`), field, `copyWith`, and `toJson`:

```dart
      if (acpPermissionToJson(acpPermissionDefault) case final id?)
        'acpPermissionDefault': id,
```

Cubit:

```dart
  Future<void> setAcpPermissionDefault(LaunchSecurityPolicy value) {
    return _save(state.preferences.copyWith(acpPermissionDefault: value));
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/session_preferences_test.dart test/cubits/session_preferences_cubit_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart client/lib/cubits/session_preferences_cubit.dart client/test/models/session_preferences_test.dart client/test/cubits/session_preferences_cubit_test.dart
git commit -m "Persist global ACP compose permission default."
```

---

### Task 4: Session and binding `acpPermission` facts

**Files:**
- Modify: `client/lib/models/app_session.dart`
- Modify: `client/lib/models/session_member_binding.dart`
- Test: `client/test/models/app_session_acp_test.dart`
- Test: `client/test/models/session_member_binding_test.dart`

**Interfaces:**
- Consumes: codec from Task 1
- Produces:
  - `AppSession.acpPermission` default `fullAccess`. JSON key `acpPermission` omitted unless `acp == true` and policy is ask. Team sessions (`acp` false) never persist it. `copyWith` / `==` / `hashCode` include it. Factory forces `fullAccess` when resolved `acp` is false.
  - `SessionMemberBinding.acpPermission` default `fullAccess`. JSON omitted unless `acp == true` and ask. `withNativeSessionId` preserves it.

- [ ] **Step 1: Write the failing tests**

Add to `app_session_acp_test.dart`:

```dart
  test('acpPermission omits fullAccess and round-trips ask only when acp', () {
    final off = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
    );
    expect(off.acpPermission, LaunchSecurityPolicy.fullAccess);
    expect(off.toJson().containsKey('acpPermission'), isFalse);

    final ask = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      cli: CliTool.claude,
      acp: true,
      acpPermission: LaunchSecurityPolicy.ask,
    );
    expect(ask.toJson()['acpPermission'], 'ask');
    expect(
      AppSession.fromJson(ask.toJson()).acpPermission,
      LaunchSecurityPolicy.ask,
    );

    final team = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 'team-1',
      acpPermission: LaunchSecurityPolicy.ask,
    );
    expect(team.acp, isFalse);
    expect(team.acpPermission, LaunchSecurityPolicy.fullAccess);
    expect(team.toJson().containsKey('acpPermission'), isFalse);
  });
```

Add to `session_member_binding_test.dart`:

```dart
  test('acpPermission omits unless acp ask', () {
    const pty = SessionMemberBinding(rosterMemberId: 'lead', taskId: 't1');
    expect(pty.acpPermission, LaunchSecurityPolicy.fullAccess);
    expect(pty.toJson().containsKey('acpPermission'), isFalse);

    const acpFull = SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 't1',
      acp: true,
    );
    expect(acpFull.toJson().containsKey('acpPermission'), isFalse);

    const ask = SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 't1',
      acp: true,
      acpPermission: LaunchSecurityPolicy.ask,
    );
    expect(ask.toJson()['acpPermission'], 'ask');
    expect(
      SessionMemberBinding.fromJson(ask.toJson()).acpPermission,
      LaunchSecurityPolicy.ask,
    );
    expect(ask.withNativeSessionId('cursor', 'n1').acpPermission, LaunchSecurityPolicy.ask);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_acp_test.dart test/models/session_member_binding_test.dart`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Thread `acpPermission` through `AppSession._`, factory (if `!resolvedAcp` store `fullAccess`), `fromJson`, field, `copyWith`, `toJson` (`if (acp && acpPermissionToJson(acpPermission) case final id?) 'acpPermission': id`), `==`, `hashCode`.

Same for `SessionMemberBinding` constructor / `fromJson` / `toJson` / `withNativeSessionId` / `==` / `hashCode`. When `acp` is false, ignore an incoming ask and store `fullAccess`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/app_session_acp_test.dart test/models/session_member_binding_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/app_session.dart client/lib/models/session_member_binding.dart client/test/models/app_session_acp_test.dart client/test/models/session_member_binding_test.dart
git commit -m "Persist ACP Ask/Full-access on sessions and mixed seats."
```

---

### Task 5: Create-path seed

**Files:**
- Modify: `client/lib/services/chat/session/session_create_request.dart`
- Modify: `client/lib/services/chat/launch/session/member_acp_stamp.dart`
- Modify: `client/lib/services/chat/launch/session/session_launch_coordinator.dart`
- Modify: `client/lib/repositories/session_repository.dart` (`createSession`)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart` (`stampMemberAcp` group)
- Test: `client/test/models/app_session_acp_test.dart` is not enough — add stamp cases in the existing stamp group

**Interfaces:**
- Consumes: `LaunchSecurityPolicy` from Task 1; binding field from Task 4
- Produces:
  - `stampMemberAcp(..., LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess)` — when the stamped `acp` is true, copy `acpPermission`; PTY seats stay default fullAccess / omit JSON
  - `SessionCreateRequest.acpPermission` default `fullAccess`
  - `createSession(..., LaunchSecurityPolicy acpPermission = fullAccess)` writes personal `AppSession.acpPermission` when `resolvedAcp` is true; passes the seed into `stampMemberAcp`
  - Coordinator passes `request.acpPermission`
  - `buildWorkspaceConversationCreateRequest` / `_requestCreateWorkspaceConversation` thread `readAcpPermissionDefault` (added in Task 8; for this task pass the request field from `workspace_session_actions` reading the cubit inline is OK only if Task 8 helper is not yet present — prefer adding `readAcpPermissionDefault` here in `claude_acp_launch_switch.dart`)

- [ ] **Step 1: Write the failing stamp test**

In `claude_acp_launch_switch_test.dart` `stampMemberAcp` group, extend the local `stamp` helper with `LaunchSecurityPolicy acpPermission = LaunchSecurityPolicy.fullAccess` and add:

```dart
    test('ACP seats receive acpPermission seed; PTY seats omit it', () {
      final mixed = stamp(
        members: [
          member(CliTool.claude, 'lead'),
          member(CliTool.flashskyai, 'pty'),
        ],
        seedClaude: true,
        acpPermission: LaunchSecurityPolicy.ask,
      );
      expect(mixed.first.acp, isTrue);
      expect(mixed.first.acpPermission, LaunchSecurityPolicy.ask);
      expect(mixed.last.acp, isFalse);
      expect(mixed.last.acpPermission, LaunchSecurityPolicy.fullAccess);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart --plain-name 'ACP seats receive'`

Expected: FAIL (named arg missing / field not stamped)

- [ ] **Step 3: Write minimal implementation**

`stampMemberAcp`: add `acpPermission` param; `_bindingWithAcp` takes policy and sets `acpPermission: acp ? acpPermission : LaunchSecurityPolicy.fullAccess`.

`SessionCreateRequest`: `this.acpPermission = LaunchSecurityPolicy.fullAccess`.

`createSession`: add the same named param; `AppSession(..., acpPermission: resolvedAcp ? acpPermission : LaunchSecurityPolicy.fullAccess)`; pass into `stampMemberAcp`.

Coordinator: `acpPermission: request.acpPermission` on both `createSession` and `stampMemberAcp`.

`claude_acp_launch_switch.dart`:

```dart
LaunchSecurityPolicy readAcpPermissionDefault(BuildContext context) {
  try {
    return context
        .read<SessionPreferencesCubit>()
        .state
        .preferences
        .acpPermissionDefault;
  } on ProviderNotFoundException {
    return LaunchSecurityPolicy.fullAccess;
  }
}
```

`workspace_session_actions.dart`: pass `acpPermission: readAcpPermissionDefault(context)` into `SessionCreateRequest` / `buildWorkspaceConversationCreateRequest`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/session/session_create_request.dart client/lib/services/chat/launch/session/member_acp_stamp.dart client/lib/services/chat/launch/session/session_launch_coordinator.dart client/lib/repositories/session_repository.dart client/lib/pages/home_workspace/workspace/workspace_session_actions.dart client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
git commit -m "Seed ACP permission policy on session create and mixed seats."
```

---

### Task 6: Protocol auto-allow gated by policy

**Files:**
- Create or modify: `client/lib/services/acp/acp_host_mcp_permission.dart`
- Modify: `client/lib/services/chat/team_bus/teammate_bus_permission.dart` (add `isTeammateBusToolCall` / `isTeammateBusPermissionText` if HEAD still only checks server name)
- Modify: `client/lib/services/acp/acp_connection.dart`
- Modify: `client/lib/services/acp/acp_session.dart`
- Test: `client/test/services/acp/acp_host_mcp_permission_test.dart`
- Test: `client/test/services/acp/acp_session_test.dart`
- Test: `client/test/services/chat/team_bus/teammate_bus_permission_test.dart`

**Interfaces:**
- Consumes: `isTeammateBusToolCall`; `LaunchSecurityPolicy.ask`
- Produces:
  - `String? autoAllowAcpPermissionOptionId(Object? params, {bool allowNonHost = true})`
  - Handshake handler always calls with `allowNonHost: true`
  - `AcpAgentSession({LaunchSecurityPolicy permissionPolicy = fullAccess})` and `void setPermissionPolicy(LaunchSecurityPolicy policy)`
  - After open: `allowNonHost: permissionPolicy != LaunchSecurityPolicy.ask`
  - Prefer allow-always (hyphen or underscore kinds), else allow-once; reject-only → null

Keep the raw-JSON option parser (Cursor sends `allow-always`). Do not require `RequestPermissionRequest.fromJson` to succeed before auto-allow.

- [ ] **Step 1: Write the failing tests**

`acp_host_mcp_permission_test.dart`:

```dart
  test('Ask mode auto-allows teammate-bus but not bash', () {
    final bus = {
      'toolCall': {'title': 'teammate-bus-read_messages: read_messages'},
      'options': [
        {'optionId': 'always-1', 'kind': 'allow-always'},
      ],
    };
    final bash = {
      'toolCall': {'title': 'Run npm install'},
      'options': [
        {'optionId': 'always-1', 'kind': 'allow-always'},
      ],
    };
    expect(
      autoAllowAcpPermissionOptionId(bus, allowNonHost: false),
      'always-1',
    );
    expect(autoAllowAcpPermissionOptionId(bash, allowNonHost: false), isNull);
    expect(autoAllowAcpPermissionOptionId(bash, allowNonHost: true), 'always-1');
  });
```

In `acp_session_test.dart`:

- Handshake (`session/new`) bash-style permission is auto-allowed even if the later session policy is Ask.
- After open, Full access (default) auto-allows bash without a card (prefer allow-always).
- After `session.setPermissionPolicy(LaunchSecurityPolicy.ask)`, bash surfaces a card; teammate-bus title does not.
- reject-only still surfaces a card.

If those tests currently expect every bash request to auto-allow with no policy, rewrite them to the table above.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_host_mcp_permission_test.dart test/services/acp/acp_session_test.dart`

Expected: FAIL on Ask gating / missing handshake handler / missing `setPermissionPolicy`

- [ ] **Step 3: Write minimal implementation**

`autoAllowAcpPermissionOptionId`: if `!allowNonHost`, return null unless `isTeammateBusToolCall` on `toolCall.title` / `rawInput` / `_meta`. Then pick first allow-always else allow-once from raw options (existing hyphen/underscore parser).

`openSession`: register early `session/request_permission`; `autoAllowAcpPermissionOptionId(params, allowNonHost: true)`; encode selected or cancelled via the translator.

`AcpAgentSession`: store `LaunchSecurityPolicy permissionPolicy`; `setPermissionPolicy` assigns it; `_onRequestPermission` uses `allowNonHost: permissionPolicy != LaunchSecurityPolicy.ask` before surfacing a card.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_host_mcp_permission_test.dart test/services/acp/acp_session_test.dart test/services/acp/acp_session_runtime_test.dart test/services/chat/team_bus/teammate_bus_permission_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_host_mcp_permission.dart client/lib/services/acp/acp_connection.dart client/lib/services/acp/acp_session.dart client/lib/services/chat/team_bus/teammate_bus_permission.dart client/test/services/acp/acp_host_mcp_permission_test.dart client/test/services/acp/acp_session_test.dart client/test/services/chat/team_bus/teammate_bus_permission_test.dart
git commit -m "Gate ACP auto-allow on Ask vs Full access after handshake."
```

---

### Task 7: Runtime start + cubit use session/seat policy

**Files:**
- Modify: `client/lib/services/acp/acp_session_runtime.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Test: `client/test/services/acp/acp_session_runtime_test.dart`
- Test: cubit tests that listen for permission cards (`client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`)

**Interfaces:**
- Consumes: `AcpAgentSession.setPermissionPolicy` from Task 6; session/binding fields from Task 4
- Produces:
  - `AcpSessionRuntimeApi.start({..., LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess})`
  - `void setPermissionPolicy(LaunchSecurityPolicy policy)` on the API, runtime, and cubit
  - After `openSession`, call `session.setPermissionPolicy(permissionPolicy)`
  - `AcpChatRuntimeCubit.start` forwards `permissionPolicy`
  - Personal attach passes `session.acpPermission`; mixed attach passes `session.bindingFor(member.id)?.acpPermission ?? fullAccess`
  - Delete `_onPermissionRequest` teammate-bus branch and `_autoAllowTeammateBus`

- [ ] **Step 1: Write the failing test**

In `acp_session_runtime_test.dart`, after a successful `start`, drive a bash `request_permission` and assert:

- default / `permissionPolicy: fullAccess` → no card, selected allow-always
- `permissionPolicy: LaunchSecurityPolicy.ask` → card surfaces

Use the same fake-agent pattern already in that file. Add `runtime.setPermissionPolicy(LaunchSecurityPolicy.ask)` and show the *next* bash request surfaces.

In cubit tests, a teammate-bus permission must complete without `pendingClient` even in Ask (protocol layer). A bash permission in Ask still becomes `AcpPendingPermission`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart --plain-name 'permission'`

Expected: FAIL (`start` / API missing `permissionPolicy`)

- [ ] **Step 3: Write minimal implementation**

Thread `permissionPolicy` through `AcpSessionRuntimeApi.start`, `AcpSessionRuntime.start` (after `openSession`: `_session!.setPermissionPolicy(permissionPolicy)`), cubit `start`, and both `cubit.start(` call sites in `acp_runtime_attach.dart`.

Add `setPermissionPolicy` on the API/runtime/cubit that forwards to `_session`.

Replace cubit `_onPermissionRequest` with `_onClientRequest(AcpPendingPermission(request));` and delete `_autoAllowTeammateBus`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_session_runtime_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/services/chat/launch/acp_runtime_attach_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_session_runtime.dart client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart client/lib/services/chat/launch/connect/acp_runtime_attach.dart client/test/services/acp/acp_session_runtime_test.dart client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "Start ACP runtimes with the session permission policy."
```

---

### Task 8: Chip + l10n + compose helpers

**Files:**
- Modify: `client/lib/widgets/compose/compose_chrome.dart`
- Modify: `client/lib/widgets/compose/compose_permission_chip.dart`
- Modify: `client/lib/widgets/compose/workspace_compose_card.dart` (pass `askLabel`)
- Create: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Test: `client/test/widgets/compose/compose_chips_test.dart`
- Create: `client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart`

**Interfaces:**
- Consumes: `policiesFor` from Task 2; `readAcpPermissionDefault` from Task 5; `stampMemberAcp`; `willLaunchPersonalAcp` (new)
- Produces:
  - `ComposePermissionControl.askLabel` (`String?`)
  - Chip renders `LaunchSecurityPolicy.ask` when it is in `supportedPolicies` and `askLabel != null`
  - l10n `acpPermissionAskLabel` / `acpPermissionFullAccessLabel`
  - `bool willLaunchPersonalAcp({required bool isPersonal, required CliTool? cli, required bool requested, bool? isAndroidOverride})` — Gemini personal desktop true; else `resolveLaunchAcp`
  - `bool showLandingAcpPermissionChip({...})` — personal uses `willLaunchPersonalAcp`; team uses `stampMemberAcp` any `acp`
  - `ComposePermissionControl? acpComposePermissionControl({required LaunchSecurityPolicy current, required Set<LaunchSecurityPolicy> supported, required AppLocalizations l10n, required ValueChanged<LaunchSecurityPolicy> onSelected})` — null unless `supported.length > 1` and contains ask+fullAccess

- [ ] **Step 1: Write the failing tests**

Chip: in `compose_chips_test.dart`, a control with `supportedPolicies: {ask, fullAccess}`, `askLabel: 'Ask'`, `fullAccessLabel: 'Full access'` shows Ask and selecting Full access fires `onSelected` with `LaunchSecurityPolicy.fullAccess`.

Helper tests (no widgets):

```dart
test('willLaunchPersonalAcp is true for Gemini and for requested Claude desktop', () {
  expect(
    willLaunchPersonalAcp(isPersonal: true, cli: CliTool.gemini, requested: false),
    isTrue,
  );
  expect(
    willLaunchPersonalAcp(isPersonal: true, cli: CliTool.claude, requested: true),
    isTrue,
  );
  expect(
    willLaunchPersonalAcp(isPersonal: true, cli: CliTool.claude, requested: false),
    isFalse,
  );
  expect(
    willLaunchPersonalAcp(
      isPersonal: true,
      cli: CliTool.claude,
      requested: true,
      isAndroidOverride: true,
    ),
    isFalse,
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/widgets/compose/compose_chips_test.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart`

Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Arb (append before the closing `}` of both files):

```json
  "acpPermissionAskLabel": "Ask",
  "acpPermissionFullAccessLabel": "Full access",
```

```json
  "acpPermissionAskLabel": "询问",
  "acpPermissionFullAccessLabel": "完全访问",
```

Chip `_renderablePolicies`: after cliDefault, if `supportedPolicies.contains(LaunchSecurityPolicy.ask) && askLabel != null` include `.ask`. Label/specs branches for `.ask` using `askLabel!`.

`workspace_compose_card.dart`: pass `askLabel: control.askLabel` into both chip constructions.

`acp_compose_permission.dart`: implement `willLaunchPersonalAcp`, `showLandingAcpPermissionChip`, and `acpComposePermissionControl`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/widgets/compose/compose_chips_test.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart`

Expected: PASS (regenerate l10n if analyze complains: tests that import `l10n` will fail to compile until arb is generated; `flutter gen-l10n` is invoked by `run_tests.dart` / analyze)

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/compose/compose_chrome.dart client/lib/widgets/compose/compose_permission_chip.dart client/lib/widgets/compose/workspace_compose_card.dart client/lib/pages/home_workspace/workspace/acp_compose_permission.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/widgets/compose/compose_chips_test.dart client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart
git commit -m "Add ACP Ask chip rendering and compose permission helpers."
```

---

### Task 9: Wire compose + persist mid-session changes

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` — pass `permissionControl:` only, built by helper
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart` — same
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart` `_currentDraft` to set `acp: willLaunchPersonalAcp(...)` so Gemini landing counts
- Modify: `client/lib/repositories/session_repository.dart` — `updateAcpPermission`
- Modify: `client/lib/cubits/chat_cubit.dart` — thin `setAcpPermission` like `renameSession` (snapshot replace + repo). Keep it a few lines; no policy logic.
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart` — `applyAcpComposePermission` that writes preference, session/seat fact, and `cubit.setPermissionPolicy`
- Test: repository test for `updateAcpPermission`
- Test: helper test that `showLandingAcpPermissionChip` is true for Gemini personal
- Test: existing session compose tests still build; add a focused test that ACP session chrome includes the chip when control is non-null (card test file or `session_history_continue_chrome_test.dart` pattern)

**Interfaces:**
- Consumes: helpers from Task 8; cubit `setPermissionPolicy` from Task 7; preference setter from Task 3
- Produces:
  - `Future<AppSession?> SessionRepository.updateAcpPermission(String sessionId, {String? memberId, required LaunchSecurityPolicy policy})` — personal writes `AppSession.acpPermission` when `session.acp`; mixed writes the named binding when `binding.acp`; no-op otherwise
  - Landing `onSelected`: `setAcpPermissionDefault` only
  - Session `onSelected`: preference + `updateAcpPermission` + `replaceSessionSnapshot` + runtime `setPermissionPolicy`
  - Chip hidden on PTY landing / PTY seats / Android

- [ ] **Step 1: Write the failing repository test**

Follow `renameSession` tests in `client/test/repositories/session_repository_test.dart`: create a personal ACP session, `updateAcpPermission(id, policy: ask)`, reload, expect `acpPermission == ask`. Mixed: only the ACP member binding changes.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_repository_test.dart --plain-name 'updateAcpPermission'`

Expected: FAIL

- [ ] **Step 3: Implement persist + wire compose**

Repository method mirrors `renameSession` (`_withSessionFile`, `copyWith`, `_writeSession`).

ChatCubit:

```dart
  Future<void> setAcpPermission(
    SessionRepository repo,
    String sessionId, {
    String? memberId,
    required LaunchSecurityPolicy policy,
  }) async {
    final updated = await repo.updateAcpPermission(
      sessionId,
      memberId: memberId,
      policy: policy,
    );
    if (updated != null) replaceSessionSnapshot(updated);
  }
```

Landing: in `UnboundComposeChrome(...)`, set `permissionControl:` from `acpComposePermissionControl` when `showLandingAcpPermissionChip` is true. `onSelected` → `context.read<SessionPreferencesCubit>().setAcpPermissionDefault(policy)`. Do not add other logic in `unbound_compose_body.dart`.

Fix `_currentDraft().acp` to `willLaunchPersonalAcp(isPersonal: isSimple, cli: launchCli, requested: readPersonalAcpDefault(context, launchCli))`.

Session compose: `permissionControl` from helper using `isAcpChatSession(session) || isAcpChatSeat(session, selectedMemberId)`, current policy from session or binding, `onSelected` calling the apply helper.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_repository_test.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart test/widgets/compose/workspace_compose_card_test.dart test/pages/chat/session_history_continue_chrome_test.dart`

Then: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/lib/pages/chat/session_chat_compose_section.dart client/lib/pages/home_workspace/workspace/acp_compose_permission.dart client/lib/repositories/session_repository.dart client/lib/cubits/chat_cubit.dart client/test/repositories/session_repository_test.dart
git commit -m "Show ACP permission chip on Landing and session compose."
```

---

## Self-review

| Spec requirement | Task |
|------------------|------|
| Chip on ACP session + Landing ACP | 8, 9 |
| PTY no chip / assembler still fullAccess | 2, 9 |
| Capability `(cli, pty\|acp)` | 2 |
| Default fullAccess | 3, 4, 5 |
| Preference + session/seat facts | 3, 4, 5, 9 |
| Global preference, not per-CLI | 3 |
| Handshake always allow | 6 |
| After open Full access vs Ask | 6, 7 |
| teammate-bus always allow | 6, 7 |
| Mid-session next request, held card unchanged | 6 `setPermissionPolicy` |
| No PTY flags / no settings row | 2, 8 (no cli_config_section) |
| No oversized-file policy branching | 8 helper, 9 pass-through |
| l10n arb only | 8 |
| Existing ACP sessions missing key → fullAccess | 4 codec |
| Gemini landing chip | 8 `willLaunchPersonalAcp` |

No TBD/TODO placeholders. Types: `setPermissionPolicy` / `permissionPolicy` / `acpPermission` / `acpPermissionDefault` / `allowNonHost` are used consistently across tasks.
