# Automation Following CLI ACP Preference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make automations honor the existing per-CLI ACP preference for session creation, team ACP seats, and prompt delivery, with visible failures instead of silent drops.

**Architecture:** One shared seat-delivery policy (`seat_prompt_delivery.dart`) decides ACP vs PTY, reused by landing and automation. The automation gateway resolves/activates the ACP runtime and returns a delivery outcome; the dispatcher records `dispatchFailed` when delivery does not land. Personal launches pass `acp` from `SessionPreferences.personalAcpDefaultFor`, team launches seed the four member ACP flags from the same preference.

**Tech Stack:** Flutter/Dart, flutter_bloc Cubits, custom test runner (`dart run tool/run_tests.dart`).

## Global Constraints

- Never run `flutter test` directly — always `cd client && dart run tool/run_tests.dart <paths>`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- Automation sessions always use `LaunchSecurityPolicy.fullAccess`; settings' `acpPermissionDefault` is for manual sessions only.
- No new persisted automation fields, no editor UI change, no migration of existing bound sessions.
- l10n only in `client/lib/l10n/app_en.arb` and `app_zh.arb`; run status/error codes here are diagnostics, not l10n.
- Keep `services/chat/` directory naming rules (`team_bus`, `team_generation` untouched).
- Do not commit unrelated working-tree changes; stage only files listed per task.

---

### Task 1: Shared seat prompt delivery policy

**Files:**
- Create: `client/lib/services/chat/launch/session/seat_prompt_delivery.dart`
- Test: `client/test/services/chat/seat_prompt_delivery_test.dart`

**Interfaces:**
- Consumes: `isAcpChatSession` / `isAcpChatSeat` from `client/lib/services/chat/session/chat_tab.dart`.
- Produces:
  - `enum SeatPromptDeliveryResult { delivered, runtimeUnavailable, rejected, ptyUnconfirmed }`
  - `typedef AcpPromptSend = bool Function(String text);`
  - `typedef SeatPtySubmit = Future<String?> Function(String sessionId, String memberId, String message);`
  - `bool seatUsesAcp(AppSession session, String memberId)`
  - `Future<SeatPromptDeliveryResult> deliverSeatPrompt({required AppSession session, required String memberId, required String message, required AcpPromptSend? acpSend, required SeatPtySubmit ptySubmit})`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/chat/seat_prompt_delivery_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/session/seat_prompt_delivery.dart';

void main() {
  final acpSession = AppSession(
    sessionId: 'sess-acp',
    workspaceId: 'ws',
    cli: CliTool.claude,
    acp: true,
    createdAt: 1,
  );
  final ptySession = AppSession(
    sessionId: 'sess-pty',
    workspaceId: 'ws',
    cli: CliTool.claude,
    createdAt: 1,
  );
  final mixedAcpSession = AppSession(
    sessionId: 'sess-mixed',
    workspaceId: 'ws',
    sessionTeam: 'team-1',
    members: const [
      SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 't1',
        cli: CliTool.cursor,
        acp: true,
      ),
    ],
    createdAt: 1,
  );

  test('personal ACP sends through the cubit and never the PTY seam', () async {
    final sent = <String>[];
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: (text) {
        sent.add(text);
        return true;
      },
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(sent, ['hello']);
    expect(ptyCalls, 0);
  });

  test('ACP without a runtime is runtimeUnavailable, not a PTY submit', () async {
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: null,
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.runtimeUnavailable);
    expect(ptyCalls, 0);
  });

  test('ACP send rejected while a turn is in flight', () async {
    final result = await deliverSeatPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'hello',
      acpSend: (text) => false,
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(result, SeatPromptDeliveryResult.rejected);
  });

  test('mixed ACP seat uses the cubit', () async {
    final sent = <String>[];
    var ptyCalls = 0;

    final result = await deliverSeatPrompt(
      session: mixedAcpSession,
      memberId: 'team-lead',
      message: 'hello',
      acpSend: (text) {
        sent.add(text);
        return true;
      },
      ptySubmit: (sessionId, memberId, message) async {
        ptyCalls++;
        return 'pty-id';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(sent, ['hello']);
    expect(ptyCalls, 0);
  });

  test('PTY session uses the submit seam', () async {
    String? seenMessage;

    final result = await deliverSeatPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'via pty',
      acpSend: (text) => fail('ACP must not be used for a PTY session'),
      ptySubmit: (sessionId, memberId, message) async {
        seenMessage = message;
        return 'delivery-1';
      },
    );

    expect(result, SeatPromptDeliveryResult.delivered);
    expect(seenMessage, 'via pty');
  });

  test('PTY submit without an id is ptyUnconfirmed', () async {
    final result = await deliverSeatPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'via pty',
      acpSend: (text) => fail('ACP must not be used for a PTY session'),
      ptySubmit: (sessionId, memberId, message) async => null,
    );

    expect(result, SeatPromptDeliveryResult.ptyUnconfirmed);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/seat_prompt_delivery_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'teampilot' ... seat_prompt_delivery.dart` / `deliverSeatPrompt` is not defined.

- [ ] **Step 3: Write the implementation**

Create `client/lib/services/chat/launch/session/seat_prompt_delivery.dart`:

```dart
import '../../../../models/app_session.dart';
import '../../session/chat_tab.dart';

/// Outcome of sending one prompt to one runtime seat.
enum SeatPromptDeliveryResult {
  /// Handed to the seat's runtime (ACP cubit queued or PTY submit issued).
  delivered,

  /// The seat is ACP but no runtime cubit was attached, so nothing was sent.
  runtimeUnavailable,

  /// The ACP runtime refused the prompt (turn in flight, session ended).
  rejected,

  /// The PTY submit seam did not confirm the write.
  ptyUnconfirmed,
}

/// Sends one prompt into an ACP cubit. False means the runtime refused it.
typedef AcpPromptSend = bool Function(String text);

/// Existing PTY submit seam. A non-empty delivery id means "submitted".
typedef SeatPtySubmit =
    Future<String?> Function(String sessionId, String memberId, String message);

/// True when this seat runs over ACP and has no PTY composer.
bool seatUsesAcp(AppSession session, String memberId) =>
    isAcpChatSession(session) || isAcpChatSeat(session, memberId);

/// Single policy point for "does this prompt go to ACP or the PTY seam".
///
/// ACP seats never spawn a shell: falling through to [ptySubmit] would fail
/// with `terminal_surface_unavailable`, so a missing runtime is its own result.
Future<SeatPromptDeliveryResult> deliverSeatPrompt({
  required AppSession session,
  required String memberId,
  required String message,
  required AcpPromptSend? acpSend,
  required SeatPtySubmit ptySubmit,
}) async {
  if (seatUsesAcp(session, memberId)) {
    final send = acpSend;
    if (send == null) return SeatPromptDeliveryResult.runtimeUnavailable;
    return send(message)
        ? SeatPromptDeliveryResult.delivered
        : SeatPromptDeliveryResult.rejected;
  }
  final deliveryId = await ptySubmit(session.sessionId, memberId, message);
  return deliveryId != null && deliveryId.trim().isNotEmpty
      ? SeatPromptDeliveryResult.delivered
      : SeatPromptDeliveryResult.ptyUnconfirmed;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/seat_prompt_delivery_test.dart`
Expected: PASS — 6 tests.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/session/seat_prompt_delivery.dart client/test/services/chat/seat_prompt_delivery_test.dart
git commit -m "feat(chat): add shared ACP/PTY seat prompt delivery policy"
```

---

### Task 2: Move the ACP launch gate into services

**Files:**
- Create: `client/lib/services/chat/launch/session/launch_acp_policy.dart`
- Modify: `client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart:1-60`

**Interfaces:**
- Produces: `bool resolveLaunchAcp({required bool isPersonal, required CliTool? cli, required bool requested, bool? isAndroidOverride})`, re-exported from `claude_acp_launch_switch.dart` so existing UI/test imports keep working.

- [ ] **Step 1: Move the code**

Create `client/lib/services/chat/launch/session/launch_acp_policy.dart`:

```dart
import 'dart:io' show Platform;

import '../../../../models/team_config.dart';
import '../../../cli/registry/capabilities/cli_transport_capability.dart';
import '../../../cli/registry/cli_tool_registry.dart';

bool _isAndroid(bool? isAndroidOverride) =>
    isAndroidOverride ?? Platform.isAndroid;

bool _personalAcpAllowed({
  required bool isPersonal,
  required CliTool? cli,
  bool? isAndroidOverride,
}) {
  if (!isPersonal || cli == null) return false;
  if (_isAndroid(isAndroidOverride)) return false;
  return CliToolRegistry.builtIn()
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
}

/// Final ACP flag for a launch: [requested] only counts for personal Claude,
/// Cursor, Codex, or OpenCode on desktop and is always false on Android.
/// Gemini ACP is inferred by session create.
bool resolveLaunchAcp({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  bool? isAndroidOverride,
}) =>
    requested &&
    _personalAcpAllowed(
      isPersonal: isPersonal,
      cli: cli,
      isAndroidOverride: isAndroidOverride,
    );
```

Then delete `_isAndroid`, `_personalAcpAllowed`, and `resolveLaunchAcp` from
`client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart`
(lines 14-44) and replace the header with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/capabilities/cli_transport_capability.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';

export '../../../services/chat/launch/session/launch_acp_policy.dart'
    show resolveLaunchAcp;

export '../../../services/chat/launch/session/member_acp_stamp.dart'
    show resolveMemberBindingAcp, shouldAttachMemberAcp, stampMemberAcp;
```

The `dart:io` import goes away with `_isAndroid`; `CliTransport` /
`CliTransportCapability` stay for the `readPersonalAcpDefault` fallback.

Leave `readPersonalAcpDefault`, `readClaudePersonalAcpDefault`,
`readCodexPersonalAcpDefault`, `readAcpPermissionDefault`,
`watchAcpPermissionDefault` unchanged.

- [ ] **Step 2: Run the existing gate tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`
Expected: PASS — all `resolveLaunchAcp`, `buildWorkspaceConversationCreateRequest`, `resolveMemberBindingAcp`, `stampMemberAcp`, `shouldAttachMemberAcp` tests still green (the re-export keeps imports valid).

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/chat/launch/session/launch_acp_policy.dart client/lib/pages/home_workspace/workspace/claude_acp_launch_switch.dart
git commit -m "refactor(chat): move ACP launch gate into services"
```

---

### Task 3: Landing delegates to the shared policy

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_prompt_delivery.dart:1-45`
- Test: `client/test/pages/home_workspace/workspace/workspace_landing_prompt_delivery_test.dart` (no edits expected)

**Interfaces:**
- Consumes: `seatUsesAcp`, `deliverSeatPrompt`, `SeatPromptDeliveryResult` from Task 1.
- Produces: `landingPromptUsesAcp(AppSession, String)` and `Future<bool> deliverWorkspaceLandingPrompt(...)` unchanged signatures.

- [ ] **Step 1: Replace the body with a delegation**

Edit `client/lib/pages/home_workspace/workspace/workspace_landing_prompt_delivery.dart`:

```dart
import '../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../models/app_session.dart';
import '../../../services/chat/launch/session/member_input_ready_wait.dart';
import '../../../services/chat/launch/session/seat_prompt_delivery.dart';
import '../../../services/chat/session/chat_tab.dart';

typedef LandingPtySubmit =
    Future<String?> Function(String sessionId, String memberId, String message);

/// Whether landing should write a PTY optimistic bubble before delivery.
bool shouldPersistLandingHistoryPending({
  required bool switchToTerminal,
  required AppSession session,
  String memberId = '',
}) =>
    !switchToTerminal &&
    !isAcpChatSession(session) &&
    (memberId.isEmpty || !isAcpChatSeat(session, memberId));

/// True when the landing prompt must go to an ACP cubit, not PTY.
bool landingPromptUsesAcp(AppSession session, String memberId) =>
    seatUsesAcp(session, memberId);

/// Landing prompt for a personal or mixed-seat ACP session goes to
/// [AcpChatRuntimeCubit.sendPrompt], never PTY `issueSubmit` — those seats
/// never spawn a shell, so prompt-delivery would throw
/// `Cannot transition failed to submitIssued`.
Future<bool> deliverWorkspaceLandingPrompt({
  required AppSession session,
  required AcpChatRuntimeCubit? acpRuntime,
  required String memberId,
  required String message,
  required LandingPtySubmit ptySubmit,
}) async {
  final result = await deliverSeatPrompt(
    session: session,
    memberId: memberId,
    message: message,
    acpSend: acpRuntime?.sendPrompt,
    ptySubmit: ptySubmit,
  );
  return result == SeatPromptDeliveryResult.delivered;
}
```

Keep `AcpLandingQueueResult`, `queueAcpLandingPromptDuringConnect`, and
`waitForLandingAcpRuntime` below untouched.

- [ ] **Step 2: Run the landing tests**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_landing_prompt_delivery_test.dart`
Expected: PASS — 10 tests, including "ACP landing without a runtime is not a PTY submit" and "mixed ACP landing …".

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_prompt_delivery.dart
git commit -m "refactor(chat): route landing prompt delivery through the shared seat policy"
```

---

### Task 4: Automation delivery outcome + ACP-aware gateway

**Files:**
- Create: `client/lib/services/automation/automation_prompt_delivery.dart`
- Modify: `client/lib/services/automation/automation_bus_gateway.dart` (whole file)
- Modify: `client/lib/app/app_shell.dart:2579-2600`
- Test: `client/test/services/automation/automation_prompt_delivery_test.dart`
- Modify (compile fixes only): `client/test/support/post_frame_test_harness.dart:303-315`,
  `client/test/cubits/automation_cubit_test.dart:27-37`,
  `client/test/services/automation/automation_scheduler_test.dart:34-44`,
  `client/test/services/automation/automation_dispatcher_test.dart:38-60` and `:569-583`

**Interfaces:**
- Consumes: `seatUsesAcp`, `deliverSeatPrompt`, `SeatPromptDeliveryResult` (Task 1); `ChatTabStore`, `acpRuntimeForView`.
- Produces:
  - `class AutomationDeliveryOutcome { const AutomationDeliveryOutcome.delivered(); const AutomationDeliveryOutcome.failed(String reason); final bool delivered; final String? reason; }`
  - `AutomationBusGateway.deliverUserCommandToMember(AppSession session, String memberId, String message) → Future<AutomationDeliveryOutcome>`
  - `Future<AutomationDeliveryOutcome> deliverAutomationPrompt({required AppSession session, required String memberId, required String message, required AcpPromptSend? Function() acpSend, required Future<void> Function() activateAcp, required SeatPtySubmit ptySubmit, Duration activationTimeout = const Duration(seconds: 30), Duration pollInterval = const Duration(milliseconds: 50)})`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/automation/automation_prompt_delivery_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_prompt_delivery.dart';

void main() {
  final acpSession = AppSession(
    sessionId: 'sess-acp',
    workspaceId: 'ws',
    cli: CliTool.claude,
    acp: true,
    createdAt: 1,
  );
  final ptySession = AppSession(
    sessionId: 'sess-pty',
    workspaceId: 'ws',
    cli: CliTool.claude,
    createdAt: 1,
  );

  test('activates a missing ACP runtime and then delivers', () async {
    bool? sender;
    var activations = 0;

    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => sender == null ? null : (text) => true,
      activateAcp: () async {
        activations++;
        sender = true;
      },
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 50),
    );

    expect(outcome.delivered, isTrue);
    expect(outcome.reason, isNull);
    expect(activations, 1);
  });

  test('reports acp_runtime_unavailable when activation never attaches', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async {},
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
      pollInterval: const Duration(milliseconds: 1),
      activationTimeout: const Duration(milliseconds: 5),
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_runtime_unavailable');
  });

  test('reports acp_prompt_rejected when the runtime refuses', () async {
    final outcome = await deliverAutomationPrompt(
      session: acpSession,
      memberId: 'sess-acp',
      message: 'run',
      acpSend: () => (text) => false,
      activateAcp: () async {},
      ptySubmit: (sessionId, memberId, message) async => 'pty-id',
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'acp_prompt_rejected');
  });

  test('PTY seats report pty_submit_failed without an id', () async {
    final outcome = await deliverAutomationPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async => fail('PTY seats must not activate ACP'),
      ptySubmit: (sessionId, memberId, message) async => null,
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'pty_submit_failed');
  });

  test('PTY seats deliver on a submitted id', () async {
    final outcome = await deliverAutomationPrompt(
      session: ptySession,
      memberId: 'sess-pty',
      message: 'run',
      acpSend: () => null,
      activateAcp: () async => fail('PTY seats must not activate ACP'),
      ptySubmit: (sessionId, memberId, message) async => 'delivery-1',
    );

    expect(outcome.delivered, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_prompt_delivery_test.dart`
Expected: FAIL — `automation_prompt_delivery.dart` not found.

- [ ] **Step 3: Write the delivery helper**

Create `client/lib/services/automation/automation_prompt_delivery.dart`:

```dart
import '../../models/app_session.dart';
import '../chat/launch/session/seat_prompt_delivery.dart';

/// Result of one automation prompt delivery.
class AutomationDeliveryOutcome {
  const AutomationDeliveryOutcome.delivered()
    : delivered = true,
      reason = null;

  const AutomationDeliveryOutcome.failed(this.reason) : delivered = false;

  final bool delivered;

  /// Diagnostic code stored on [AutomationRun.error]; never user-facing copy.
  final String? reason;
}

/// Resolves the ACP sender for one seat; null means "no runtime attached".
typedef AutomationAcpSendResolver = AcpPromptSend? Function();

/// Delivers one automation prompt to [memberId], activating a missing ACP
/// runtime once before giving up.
Future<AutomationDeliveryOutcome> deliverAutomationPrompt({
  required AppSession session,
  required String memberId,
  required String message,
  required AutomationAcpSendResolver acpSend,
  required Future<void> Function() activateAcp,
  required SeatPtySubmit ptySubmit,
  Duration activationTimeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  if (seatUsesAcp(session, memberId) && acpSend() == null) {
    await activateAcp();
    final deadline = DateTime.now().add(activationTimeout);
    while (acpSend() == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
  }
  final result = await deliverSeatPrompt(
    session: session,
    memberId: memberId,
    message: message,
    acpSend: acpSend(),
    ptySubmit: ptySubmit,
  );
  return switch (result) {
    SeatPromptDeliveryResult.delivered =>
      const AutomationDeliveryOutcome.delivered(),
    SeatPromptDeliveryResult.runtimeUnavailable =>
      const AutomationDeliveryOutcome.failed('acp_runtime_unavailable'),
    SeatPromptDeliveryResult.rejected =>
      const AutomationDeliveryOutcome.failed('acp_prompt_rejected'),
    SeatPromptDeliveryResult.ptyUnconfirmed =>
      const AutomationDeliveryOutcome.failed('pty_submit_failed'),
  };
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_prompt_delivery_test.dart`
Expected: PASS — 5 tests.

- [ ] **Step 5: Rewrite the gateway**

Replace `client/lib/services/automation/automation_bus_gateway.dart`:

```dart
import '../../models/app_session.dart';
import '../chat/launch/session/tab_member_materializer.dart';
import '../chat/runtime/tab_session_runtime_coordinator.dart';
import '../chat/session/chat_tab.dart';
import '../chat/session/chat_tab_store.dart';
import 'automation_prompt_delivery.dart';

/// Delivery seam for automation dispatch (ACP cubit, TeamBus, or PTY inject).
abstract interface class AutomationBusGateway {
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  );

  /// PTY connected and member past startup (TUI frame + agent loop when needed).
  Future<void> ensureMemberReady(String sessionId, String memberId);
}

class TabTeamBusGateway implements AutomationBusGateway {
  TabTeamBusGateway({
    required TabMemberMaterializer memberMaterializer,
    required TabSessionRuntimeCoordinator sessionRuntime,
    required ChatTabStore tabStore,
    Future<void> Function(String sessionId)? activatePersonalAcp,
    Future<void> Function(String sessionId, String memberId)? activateMemberSeat,
    Duration acpActivationTimeout = const Duration(seconds: 30),
  }) : _memberMaterializer = memberMaterializer,
       _sessionRuntime = sessionRuntime,
       _tabStore = tabStore,
       _activatePersonalAcp = activatePersonalAcp,
       _activateMemberSeat = activateMemberSeat,
       _acpActivationTimeout = acpActivationTimeout;

  final TabMemberMaterializer _memberMaterializer;
  final TabSessionRuntimeCoordinator _sessionRuntime;
  final ChatTabStore _tabStore;
  final Future<void> Function(String sessionId)? _activatePersonalAcp;
  final Future<void> Function(String sessionId, String memberId)?
  _activateMemberSeat;
  final Duration _acpActivationTimeout;

  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) {
    final tab = _tabStore.getOpenTabBySessionId(session.sessionId);
    if (tab == null) {
      return Future.value(
        const AutomationDeliveryOutcome.failed('tab_unavailable'),
      );
    }
    return deliverAutomationPrompt(
      session: session,
      memberId: memberId,
      message: message,
      acpSend: () => acpRuntimeForView(
        session: session,
        tab: tab,
        selectedMemberId: memberId,
      )?.sendPrompt,
      activateAcp: () => _activate(session, memberId),
      ptySubmit: (sessionId, memberId, text) => _sessionRuntime
          .deliverUserCommandToMember(
            sessionId,
            memberId,
            text,
            directToPty: true,
          ),
      activationTimeout: _acpActivationTimeout,
    );
  }

  Future<void> _activate(AppSession session, String memberId) async {
    if (session.isSimple) {
      await _activatePersonalAcp?.call(session.sessionId);
      return;
    }
    await _activateMemberSeat?.call(session.sessionId, memberId);
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) {
    return _memberMaterializer.ensureMemberInputReady(
      sessionId,
      memberId,
      directToPty: true,
    );
  }
}
```

- [ ] **Step 6: Wire app_shell**

Edit `client/lib/app/app_shell.dart:2583-2586` to:

```dart
      busGateway: TabTeamBusGateway(
        memberMaterializer: chatCubit.memberMaterializer,
        sessionRuntime: chatCubit.sessionRuntime,
        tabStore: chatCubit.tabStore,
        activatePersonalAcp: chatCubit.retrySessionLaunch,
        activateMemberSeat: chatCubit.ensureMemberTerminalForView,
      ),
```

- [ ] **Step 7: Update the four test fakes**

In each file replace the `deliverUserCommandToMember` signature/body:

`client/test/support/post_frame_test_harness.dart` (`_NoopAutomationBusGateway`):

```dart
  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) async => const AutomationDeliveryOutcome.delivered();
```

`client/test/cubits/automation_cubit_test.dart` (`_NoopBusGateway`): same body.

`client/test/services/automation/automation_scheduler_test.dart` (`_RecordingBusGateway`):

```dart
  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) async {
    deliverCount++;
    return const AutomationDeliveryOutcome.delivered();
  }
```

`client/test/services/automation/automation_dispatcher_test.dart` — replace the
whole `_RecordingBusGateway` class with:

```dart
class _RecordingBusGateway implements AutomationBusGateway {
  _RecordingBusGateway({
    this.events,
    this.deliveryOutcome = const AutomationDeliveryOutcome.delivered(),
  });

  final List<String>? events;
  final AutomationDeliveryOutcome deliveryOutcome;
  final deliverCalls = <(String sessionId, String memberId, String message)>[];
  final ensureCalls = <(String sessionId, String memberId)>[];

  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) async {
    events?.add('deliver:${session.sessionId}');
    deliverCalls.add((session.sessionId, memberId, message));
    return deliveryOutcome;
  }

  @override
  Future<void> ensureMemberReady(String sessionId, String memberId) async {
    events?.add('ensure:$sessionId');
    ensureCalls.add((sessionId, memberId));
  }
}
```

`_SlowBusGateway` (`:569`):

```dart
  @override
  Future<AutomationDeliveryOutcome> deliverUserCommandToMember(
    AppSession session,
    String memberId,
    String message,
  ) async => const AutomationDeliveryOutcome.delivered();
```

Ensure every edited test file imports `package:teampilot/models/app_session.dart`
and `package:teampilot/services/automation/automation_prompt_delivery.dart`
(neither the harness nor the cubit/scheduler tests have both today).

- [ ] **Step 8: Run the gateway + delivery tests**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_prompt_delivery_test.dart test/services/automation/automation_dispatcher_test.dart test/services/automation/automation_scheduler_test.dart test/cubits/automation_cubit_test.dart`
Expected: PASS (dispatcher still ignores the outcome at this task; all existing tests green).

- [ ] **Step 9: Commit**

```bash
git add client/lib/services/automation/automation_bus_gateway.dart client/lib/services/automation/automation_prompt_delivery.dart client/lib/app/app_shell.dart client/test/services/automation/automation_prompt_delivery_test.dart client/test/services/automation/automation_dispatcher_test.dart client/test/services/automation/automation_scheduler_test.dart client/test/cubits/automation_cubit_test.dart client/test/support/post_frame_test_harness.dart
git commit -m "feat(automation): deliver prompts through ACP runtimes and report outcomes"
```

---

### Task 5: Dispatcher follows the CLI ACP preference

**Files:**
- Modify: `client/lib/services/automation/automation_dispatcher.dart` (constructor, `_createSessionForLaunchPrompt`)
- Modify: `client/lib/app/app_shell.dart:2579-2600`
- Test: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Consumes: `resolveLaunchAcp` (Task 2), `SessionPreferences.personalAcpDefaultFor`.
- Produces: constructor parameter `bool Function(CliTool cli)? personalAcpDefaultFor` (defaults to `(_) => true`, matching `SessionPreferences`).

- [ ] **Step 1: Write the failing tests**

Append to `client/test/services/automation/automation_dispatcher_test.dart` inside `main()`:

```dart
  test('personal launchPrompt passes the CLI ACP preference to the request', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    SessionCreateRequest? captured;

    Future<void> run(bool acpEnabled) async {
      captured = null;
      final dispatcher = AutomationDispatcher(
        repository: repo,
        scheduleCalculator: AutomationScheduleCalculator(),
        sessionRepository: _FakeSessionRepository(const []),
        busGateway: _RecordingBusGateway(),
        requestOpenSession: (_) async => SessionOpenStatus.opened,
        requestCreateAndOpenSession: (request) async {
          captured = request;
          return SessionOpenStatus.opened;
        },
        workspaceById: (_) => workspace,
        teamById: (_) => null,
        sessionById: (sessionId, workspaceId) => AppSession(
          sessionId: sessionId,
          workspaceId: workspaceId,
          createdAt: 1,
        ),
        personalAcpDefaultFor: (_) => acpEnabled,
        nowMs: () => 100,
      );
      await dispatcher.dispatch(
        Automation(
          id: 'launch-acp',
          name: 'ACP launch',
          action: AutomationAction.launchPrompt,
          workspaceId: 'ws1',
          isPersonal: true,
          presetId: 'preset-1',
          message: 'run',
          preset: AutomationSchedulePreset.daily,
          hourMinute: '09:00',
          timezone: 'UTC',
          dtstartMs: 1,
          enabled: true,
          nextRunAtMs: 1,
          createdAtMs: 1,
          updatedAtMs: 1,
        ),
      );
    }

    await run(true);
    expect(captured!.acp, isTrue);
    expect(captured!.acpPermission, LaunchSecurityPolicy.fullAccess);

    await run(false);
    expect(captured!.acp, isFalse);
  });

  test('team launchPrompt seeds member ACP from the same preference', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    SessionCreateRequest? captured;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (request) async {
        captured = request;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        createdAt: 1,
      ),
      personalAcpDefaultFor: (cli) => cli == CliTool.codex,
      nowMs: () => 100,
    );

    await dispatcher.dispatch(
      Automation(
        id: 'launch-team-acp',
        name: 'Team ACP launch',
        action: AutomationAction.launchPrompt,
        workspaceId: 'ws1',
        isPersonal: false,
        teamId: 'team-1',
        targetMemberId: 'team-lead',
        message: 'run',
        preset: AutomationSchedulePreset.daily,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 1,
        enabled: true,
        nextRunAtMs: 1,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );

    expect(captured!.acp, isFalse);
    expect(captured!.seedClaudeMemberAcp, isFalse);
    expect(captured!.seedCodexMemberAcp, isTrue);
    expect(captured!.seedCursorMemberAcp, isFalse);
    expect(captured!.seedOpencodeMemberAcp, isFalse);
  });
```

Add imports at the top of that test file:

```dart
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/services/chat/session/session_create_request.dart';
```

- [ ] **Step 2: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: FAIL — `No named parameter with the name 'personalAcpDefaultFor'`.

- [ ] **Step 3: Implement the preference plumbing**

In `client/lib/services/automation/automation_dispatcher.dart`:

Add imports:

```dart
import '../../models/launch_security_policy.dart';
import '../chat/launch/session/launch_acp_policy.dart';
```

Add the field/resolver:

```dart
bool _defaultPersonalAcpDefaultFor(CliTool cli) => true;
```

Constructor: add `bool Function(CliTool cli)? personalAcpDefaultFor,` and
initializer:

```dart
       _personalAcpDefaultFor =
           personalAcpDefaultFor ?? _defaultPersonalAcpDefaultFor,
```

Field:

```dart
  final bool Function(CliTool cli) _personalAcpDefaultFor;
```

In `_createSessionForLaunchPrompt`, personal branch: replace the
`SessionCreateRequest(...)` argument list with

```dart
      final acp = resolveLaunchAcp(
        isPersonal: true,
        cli: simpleIdentity.cli,
        requested: _personalAcpDefaultFor(simpleIdentity.cli),
      );
      status = await _requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: true,
          repo: _sessionRepository,
          cli: simpleIdentity.cli,
          simpleIdentity: simpleIdentity,
          expertKey: expertKey,
          workingDirectory: workingDirectory,
          fixedSessionId: plannedSessionId,
          acp: acp,
          acpPermission: LaunchSecurityPolicy.fullAccess,
        ),
      );
```

Team branch: add the four seeds to the existing `SessionCreateRequest`:

```dart
          seedClaudeMemberAcp: _personalAcpDefaultFor(CliTool.claude),
          seedCodexMemberAcp: _personalAcpDefaultFor(CliTool.codex),
          seedCursorMemberAcp: _personalAcpDefaultFor(CliTool.cursor),
          seedOpencodeMemberAcp: _personalAcpDefaultFor(CliTool.opencode),
          acpPermission: LaunchSecurityPolicy.fullAccess,
```

In `client/lib/app/app_shell.dart:2579-2600` add to the dispatcher args:

```dart
      personalAcpDefaultFor:
          sessionPreferencesCubit.state.preferences.personalAcpDefaultFor,
```

- [ ] **Step 4: Run the dispatcher tests**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: PASS — the two new tests plus all existing launch/dispatch cases.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/automation/automation_dispatcher.dart client/lib/app/app_shell.dart client/test/services/automation/automation_dispatcher_test.dart
git commit -m "feat(automation): follow the CLI ACP preference when launching sessions"
```

---

### Task 6: Fail the run when delivery does not land

**Files:**
- Modify: `client/lib/services/automation/automation_dispatcher.dart` (`_dispatchMessage`)
- Test: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Consumes: `AutomationDeliveryOutcome.reason` from Task 4.
- Produces: run status `AutomationRunStatus.dispatchFailed` with `error` ∈ `{acp_runtime_unavailable, acp_prompt_rejected, pty_submit_failed, tab_unavailable}`.

- [ ] **Step 1: Write the failing test**

Append inside `main()`:

```dart
  test('failed delivery marks the run dispatchFailed with the reason', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final bus = _RecordingBusGateway(
      deliveryOutcome: const AutomationDeliveryOutcome.failed(
        'acp_runtime_unavailable',
      ),
    );

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: bus,
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (_) => team,
      nowMs: () => 100,
    );

    final result = await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-1'),
    );

    expect(result.run.status, AutomationRunStatus.dispatchFailed);
    expect(result.run.error, 'acp_runtime_unavailable');
    expect(result.run.sessionId, 'sess-1');
    final runs = await repo.runsFor('ws1', automationId: 'auto-1');
    expect(runs.single.status, AutomationRunStatus.dispatchFailed);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart --plain-name "failed delivery marks the run dispatchFailed"`
Expected: FAIL — `Expected: AutomationRunStatus.dispatchFailed Actual: AutomationRunStatus.completed`.

- [ ] **Step 3: Handle the outcome**

In `_dispatchMessage`, replace the delivery call:

```dart
      final outcome = await _busGateway.deliverUserCommandToMember(
        session,
        memberId,
        automation.message,
      );
      if (!outcome.delivered) {
        final failed = _finishRun(
          pending,
          AutomationRunStatus.dispatchFailed,
          startedAtMs: startedAtMs,
          sessionId: session.sessionId,
          error: outcome.reason,
        );
        final updated = _advanceAutomationAfterRun(
          automation,
          lastRunAtMs: startedAtMs,
        );
        return (failed, updated);
      }
```

Leave the existing dispatched/completed recording after it unchanged.

- [ ] **Step 4: Run all automation tests**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/`
Expected: PASS — gateway/delivery/dispatcher/scheduler suites green.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/automation/automation_dispatcher.dart client/test/services/automation/automation_dispatcher_test.dart
git commit -m "fix(automation): record dispatchFailed when prompt delivery does not land"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!` (or only pre-existing infos unrelated to the touched files).

- [ ] **Step 2: Targeted regression**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/seat_prompt_delivery_test.dart test/services/automation/ test/pages/home_workspace/workspace/`
Expected: PASS.

- [ ] **Step 3: Full suite once, in the background**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS. If any automation/ACP suite fails, fix before reporting done.

- [ ] **Step 4: Update the spec status line**

Edit `docs/superpowers/specs/2026-11-01-automation-follows-cli-acp-design.md:4` from
`状态：已评审（待实现）` to `状态：已实现`.

```bash
git add docs/superpowers/specs/2026-11-01-automation-follows-cli-acp-design.md
git commit -m "docs(spec): mark automation ACP preference design implemented"
```

---

## Notes for the implementer

- `personalAcpDefaultFor` defaults to `true` (matching `SessionPreferences`), so on desktop the new tests see `acp: true` unless they inject a resolver.
- `resolveLaunchAcp` returns false for Android and ACP-only CLIs; ACP-only CLIs still become ACP sessions through `session_provisional_builder.dart:45-49` — do not "fix" that.
- Team seeds only take effect for mixed + local seats (`member_acp_stamp.dart`); native teams stay PTY.
- If `dart run tool/run_tests.dart` reports a shared-cache lock issue, another run is in flight — wait for it instead of running `flutter test`.
