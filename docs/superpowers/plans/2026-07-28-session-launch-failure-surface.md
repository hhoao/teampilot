# Session Launch Failure Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show session terminal launch failures on both Chat and Terminal workbench surfaces with a shared Retry action, without forcing view switches.

**Architecture:** Keep session-level `launchError` / `failSessionConnect` as the single error source. Add a pure `SessionLaunchFailurePresenter` + shared `SessionLaunchErrorBanner`, mount it above Chat compose and as a Terminal top-of-pane overlay, and add `ChatCubit.retrySessionLaunch` that reconnects via `ExistingSessionConnect(preserveWorkbenchView: true)`.

**Tech Stack:** Flutter / `flutter_bloc`; `shared_ui` (`TpTextStyles`, spacing); existing `formatSessionLaunchError`, `deadSshTargetIdFromError`, `connectWorkspaceSession`; `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-28-session-launch-failure-surface-design.md`

## Global Constraints

- Surfaces: **both** Chat and Terminal show failure; do **not** auto-switch Chat↔Terminal on failure or retry.
- Terminal chrome: **top banner overlay**, not full-page `launchFailed` and not a new `ChatWorkbenchOverlay` value.
- Error source: existing `ChatTabInfo.launchError` / `ChatState.sessionLaunchError` via `failSessionConnect` / `clearLaunchError` / `formatSessionLaunchError`.
- Retry: `ChatCubit.retrySessionLaunch(sessionId)` → `connectWorkspaceSession(ExistingSessionConnect(..., preserveWorkbenchView: true))`.
- Hide banner while `sessionConnectingId` matches the active session; Terminal may show existing `sessionStarting`.
- No Snackbar/Toast for launch failure.
- Team errors remain session-scoped in v1; Retry targets selected seat (same resolution as Terminal toggle reconnect).
- Keep dead-SSH remap CTA when `deadSshTargetIdFromError` matches; remap **before** retry in action order.
- Do not change `TerminalLaunchController` failure detection or remove `writeToDisplay` diagnostics.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/chat/session_launch_failure_presenter_test.dart test/pages/chat/session_launch_error_banner_test.dart test/pages/chat/session_launch_error_visibility_test.dart test/cubits/chat/retry_session_launch_test.dart test/utils/session/session_launch_error_test.dart`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/pages/chat/session_launch_failure_presenter.dart` | Pure view-model: message + ordered actions (`retry`, `remapDeadSsh`) |
| `client/lib/pages/chat/session_launch_error_visibility.dart` | Pure `shouldShowSessionLaunchErrorBanner(...)` |
| `client/lib/pages/chat/session_launch_error_banner.dart` | Shared error banner UI + Retry / remap buttons |
| `client/lib/pages/chat/session_launch_retry.dart` | Pure builder: `ExistingSessionConnect` for retry from session + tab + team |
| `client/lib/cubits/chat_cubit.dart` | `retrySessionLaunch(sessionId)` |
| `client/lib/pages/chat/session_review_compose_card.dart` | Replace inline error box with banner; wire `onRetry` |
| `client/lib/pages/chat/session_chat_view.dart` | Pass `onRetry` / connecting into compose card |
| `client/lib/pages/chat_workbench.dart` | Terminal top banner; shared retry/remap wiring |
| `client/lib/pages/chat/session_workbench_view_toggle.dart` | Use shared connect builder (avoid drift) |
| `client/lib/utils/ui/app_keys.dart` | Keys for banner + retry button |
| `client/test/pages/chat/session_launch_failure_presenter_test.dart` | Presenter unit tests |
| `client/test/pages/chat/session_launch_error_visibility_test.dart` | Visibility matrix unit tests |
| `client/test/pages/chat/session_launch_error_banner_test.dart` | Banner widget tests |
| `client/test/pages/chat/session_launch_retry_test.dart` | Retry request builder tests |
| `client/test/cubits/chat/retry_session_launch_test.dart` | Cubit retry → ExistingSessionConnect |

---

### Task 1: Presenter + visibility helpers

**Files:**
- Create: `client/lib/pages/chat/session_launch_failure_presenter.dart`
- Create: `client/lib/pages/chat/session_launch_error_visibility.dart`
- Create: `client/test/pages/chat/session_launch_failure_presenter_test.dart`
- Create: `client/test/pages/chat/session_launch_error_visibility_test.dart`

**Interfaces:**
- Consumes: `deadSshTargetIdFromError` from `client/lib/services/workspace/dead_ssh_target_error.dart`
- Produces:
  - `SessionLaunchFailureView? presentSessionLaunchFailure(String? launchError)`
  - `enum SessionLaunchFailureActionKind { retry, remapDeadSsh }`
  - `SessionLaunchFailureAction({required SessionLaunchFailureActionKind kind, String? deadSshTargetId})`
  - `SessionLaunchFailureView({required String message, required List<SessionLaunchFailureAction> actions})`
  - `bool shouldShowSessionLaunchErrorBanner({required String? launchError, required bool sessionConnectInProgress})`
  - `bool shouldShowTerminalSessionLaunchErrorBanner({required ChatWorkbenchOverlay overlay, required String? launchError, required bool sessionConnectInProgress})`

- [ ] **Step 1: Write failing presenter + visibility tests**

Create `client/test/pages/chat/session_launch_failure_presenter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/session_launch_failure_presenter.dart';

void main() {
  test('null and blank yield null', () {
    expect(presentSessionLaunchFailure(null), isNull);
    expect(presentSessionLaunchFailure('   '), isNull);
  });

  test('normal error yields retry only', () {
    final view = presentSessionLaunchFailure('Failed to start claude');
    expect(view, isNotNull);
    expect(view!.message, 'Failed to start claude');
    expect(view.actions.map((a) => a.kind).toList(), [
      SessionLaunchFailureActionKind.retry,
    ]);
  });

  test('dead SSH error yields remap then retry', () {
    final view = presentSessionLaunchFailure(
      'No SSH profile for target "ssh:missing-profile"',
    );
    expect(view, isNotNull);
    expect(view!.actions.map((a) => a.kind).toList(), [
      SessionLaunchFailureActionKind.remapDeadSsh,
      SessionLaunchFailureActionKind.retry,
    ]);
    expect(view.actions.first.deadSshTargetId, 'ssh:missing-profile');
  });
}
```

Create `client/test/pages/chat/session_launch_error_visibility_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_overlay.dart';
import 'package:teampilot/pages/chat/session_launch_error_visibility.dart';

void main() {
  test('hidden while connecting even if error set', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: 'boom',
        sessionConnectInProgress: true,
      ),
      isFalse,
    );
  });

  test('shown when failed and idle', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isTrue,
    );
  });

  test('hidden when no error', () {
    expect(
      shouldShowSessionLaunchErrorBanner(
        launchError: null,
        sessionConnectInProgress: false,
      ),
      isFalse,
    );
  });

  test('terminal banner only when overlay is none', () {
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.none,
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isTrue,
    );
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.sessionStarting,
        launchError: 'boom',
        sessionConnectInProgress: true,
      ),
      isFalse,
    );
    expect(
      shouldShowTerminalSessionLaunchErrorBanner(
        overlay: ChatWorkbenchOverlay.chat,
        launchError: 'boom',
        sessionConnectInProgress: false,
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/chat/session_launch_failure_presenter_test.dart test/pages/chat/session_launch_error_visibility_test.dart`

Expected: FAIL (library not found / undefined functions)

- [ ] **Step 3: Implement presenter + visibility**

Create `client/lib/pages/chat/session_launch_failure_presenter.dart`:

```dart
import '../../services/workspace/dead_ssh_target_error.dart';

enum SessionLaunchFailureActionKind { retry, remapDeadSsh }

final class SessionLaunchFailureAction {
  const SessionLaunchFailureAction({
    required this.kind,
    this.deadSshTargetId,
  });

  final SessionLaunchFailureActionKind kind;
  final String? deadSshTargetId;
}

final class SessionLaunchFailureView {
  const SessionLaunchFailureView({
    required this.message,
    required this.actions,
  });

  final String message;
  final List<SessionLaunchFailureAction> actions;
}

/// Builds a product-facing failure view from a stored launch error string.
///
/// [launchError] is expected to already be formatted via
/// `formatSessionLaunchError` when stored on the tab.
SessionLaunchFailureView? presentSessionLaunchFailure(String? launchError) {
  final message = launchError?.trim() ?? '';
  if (message.isEmpty) return null;

  final dead = deadSshTargetIdFromError(message);
  final actions = <SessionLaunchFailureAction>[
    if (dead != null)
      SessionLaunchFailureAction(
        kind: SessionLaunchFailureActionKind.remapDeadSsh,
        deadSshTargetId: dead,
      ),
    const SessionLaunchFailureAction(kind: SessionLaunchFailureActionKind.retry),
  ];
  return SessionLaunchFailureView(message: message, actions: actions);
}
```

Create `client/lib/pages/chat/session_launch_error_visibility.dart`:

```dart
import 'chat_workbench_overlay.dart';

bool shouldShowSessionLaunchErrorBanner({
  required String? launchError,
  required bool sessionConnectInProgress,
}) {
  if (sessionConnectInProgress) return false;
  final text = launchError?.trim() ?? '';
  return text.isNotEmpty;
}

bool shouldShowTerminalSessionLaunchErrorBanner({
  required ChatWorkbenchOverlay overlay,
  required String? launchError,
  required bool sessionConnectInProgress,
}) {
  if (overlay != ChatWorkbenchOverlay.none) return false;
  return shouldShowSessionLaunchErrorBanner(
    launchError: launchError,
    sessionConnectInProgress: sessionConnectInProgress,
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/chat/session_launch_failure_presenter_test.dart test/pages/chat/session_launch_error_visibility_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/pages/chat/session_launch_failure_presenter.dart \
  client/lib/pages/chat/session_launch_error_visibility.dart \
  client/test/pages/chat/session_launch_failure_presenter_test.dart \
  client/test/pages/chat/session_launch_error_visibility_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): add session launch failure presenter and visibility helper

EOF
)"
```

---

### Task 2: Shared `SessionLaunchErrorBanner` widget

**Files:**
- Create: `client/lib/pages/chat/session_launch_error_banner.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (add banner + retry keys)
- Create: `client/test/pages/chat/session_launch_error_banner_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchFailureView`, `SessionLaunchFailureActionKind` from Task 1; `TpTextStyles` / `context.tpSpacing`; l10n `sessionRetryButton`, `workspaceDeadTargetRemapFromLaunch`
- Produces:
  - `SessionLaunchErrorBanner({required SessionLaunchFailureView view, VoidCallback? onRetry, VoidCallback? onRemapDeadTarget, bool isRetrying = false})`
  - `AppKeys.sessionLaunchErrorBanner`
  - `AppKeys.sessionLaunchErrorRetryButton`

- [ ] **Step 1: Add AppKeys**

In `client/lib/utils/ui/app_keys.dart`, add near other chat keys:

```dart
static const sessionLaunchErrorBanner = Key('session-launch-error-banner');
static const sessionLaunchErrorRetryButton = Key(
  'session-launch-error-retry-button',
);
```

- [ ] **Step 2: Write failing banner widget tests**

Read exact EN string for `workspaceDeadTargetRemapFromLaunch` from `client/lib/l10n/app_en.arb` and use that in `find.text(...)`.

Create `client/test/pages/chat/session_launch_error_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/session_launch_error_banner.dart';
import 'package:teampilot/pages/chat/session_launch_failure_presenter.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('shows message and invokes onRetry', (tester) async {
    var retried = false;
    final view = presentSessionLaunchFailure('spawn failed')!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () => retried = true,
        ),
      ),
    );
    expect(find.text('spawn failed'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.sessionLaunchErrorRetryButton));
    await tester.pump();
    expect(retried, isTrue);
  });

  testWidgets('shows remap CTA for dead SSH', (tester) async {
    final view = presentSessionLaunchFailure(
      'No SSH profile for target "ssh:x"',
    )!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () {},
          onRemapDeadTarget: () {},
        ),
      ),
    );
    // Use exact EN l10n string from app_en.arb for workspaceDeadTargetRemapFromLaunch.
    expect(find.byKey(AppKeys.sessionLaunchErrorRetryButton), findsOneWidget);
    expect(find.byType(TextButton), findsNWidgets(2));
  });

  testWidgets('disables retry while isRetrying', (tester) async {
    final view = presentSessionLaunchFailure('spawn failed')!;
    await tester.pumpWidget(
      _wrap(
        SessionLaunchErrorBanner(
          view: view,
          onRetry: () {},
          isRetrying: true,
        ),
      ),
    );
    final button = tester.widget<TextButton>(
      find.byKey(AppKeys.sessionLaunchErrorRetryButton),
    );
    expect(button.onPressed, isNull);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/session_launch_error_banner_test.dart`

Expected: FAIL (banner widget missing)

- [ ] **Step 4: Implement banner**

Create `client/lib/pages/chat/session_launch_error_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'session_launch_failure_presenter.dart';

class SessionLaunchErrorBanner extends StatelessWidget {
  const SessionLaunchErrorBanner({
    required this.view,
    this.onRetry,
    this.onRemapDeadTarget,
    this.isRetrying = false,
    super.key,
  });

  final SessionLaunchFailureView view;
  final VoidCallback? onRetry;
  final VoidCallback? onRemapDeadTarget;
  final bool isRetrying;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;

    return DecoratedBox(
      key: AppKeys.sessionLaunchErrorBanner,
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              view.message,
              style: TpTextStyles.of(context).smRelaxedColored(
                cs.onErrorContainer,
              ),
            ),
            for (final action in view.actions) ...[
              SizedBox(height: spacing.xs),
              Align(
                alignment: Alignment.centerLeft,
                child: switch (action.kind) {
                  SessionLaunchFailureActionKind.remapDeadSsh => TextButton(
                    onPressed: onRemapDeadTarget,
                    child: Text(l10n.workspaceDeadTargetRemapFromLaunch),
                  ),
                  SessionLaunchFailureActionKind.retry => TextButton(
                    key: AppKeys.sessionLaunchErrorRetryButton,
                    onPressed: isRetrying ? null : onRetry,
                    child: Text(l10n.sessionRetryButton),
                  ),
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/chat/session_launch_error_banner_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add \
  client/lib/pages/chat/session_launch_error_banner.dart \
  client/lib/utils/ui/app_keys.dart \
  client/test/pages/chat/session_launch_error_banner_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): add shared session launch error banner

EOF
)"
```

---

### Task 3: Retry request builder + `ChatCubit.retrySessionLaunch`

**Files:**
- Create: `client/lib/pages/chat/session_launch_retry.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (add `retrySessionLaunch`)
- Modify: `client/lib/pages/chat/session_workbench_view_toggle.dart` (use shared builder)
- Create: `client/test/cubits/chat/retry_session_launch_test.dart`
- Create: `client/test/pages/chat/session_launch_retry_test.dart`

**Interfaces:**
- Consumes: `AppSession`, `TeamProfile`, `TeamMemberNaming`, `ExistingSessionConnect`, `ChatCubit.teamProfileById`
- Produces:
  - `ExistingSessionConnect? buildRetryExistingSessionConnect({required AppSession session, required String selectedMemberId, TeamProfile? team, bool preserveWorkbenchView = true})`
  - `Future<void> ChatCubit.retrySessionLaunch(String sessionId)`

- [ ] **Step 1: Write failing retry builder tests**

Create `client/test/pages/chat/session_launch_retry_test.dart`. Copy `TeamProfile` / `TeamMemberConfig` / `AppSession` fixture patterns from an existing team test if constructors need more fields. Core assertions:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/session_launch_retry.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

// Fixtures: _simple(), _teamSession(), _team() using real constructors.

void main() {
  test('simple session has no team/member and preserves workbench', () {
    final req = buildRetryExistingSessionConnect(
      session: /* simple AppSession */,
      selectedMemberId: 's1',
    );
    expect(req, isA<ExistingSessionConnect>());
    final existing = req!;
    expect(existing.preserveWorkbenchView, isTrue);
    expect(existing.team, isNull);
    expect(existing.member, isNull);
  });

  test('team uses selected member when present', () {
    final req = buildRetryExistingSessionConnect(
      session: /* team AppSession */,
      selectedMemberId: 'developer',
      team: /* TeamProfile with lead + developer */,
    )!;
    expect(req.member?.id, 'developer');
    expect(req.preserveWorkbenchView, isTrue);
  });

  test('team falls back to lead when selection missing', () {
    final req = buildRetryExistingSessionConnect(
      session: /* team AppSession */,
      selectedMemberId: '',
      team: /* TeamProfile with TeamMemberNaming.teamLeadName */,
    )!;
    expect(req.member?.id, TeamMemberNaming.teamLeadName);
  });

  test('toggle path can force preserveWorkbenchView false', () {
    final req = buildRetryExistingSessionConnect(
      session: /* simple */,
      selectedMemberId: 's1',
      preserveWorkbenchView: false,
    )!;
    expect(req.preserveWorkbenchView, isFalse);
  });
}
```

Fill fixtures with real model constructors from the codebase (do not leave placeholders in the committed test file).

- [ ] **Step 2: Write failing cubit retry test**

Create `client/test/cubits/chat/retry_session_launch_test.dart` using `setUpTestAppStorage` / `tearDownTestAppStorage` and a recording cubit:

```dart
class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final connects = <SessionConnectRequest>[];

  @override
  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    connects.add(request);
  }
}
```

Install an open tab + simple `AppSession` the same way other chat cubit tests do (`tabStore` helpers / emit sessions). Call `await cubit.retrySessionLaunch(session.sessionId)` and assert:

- `connects` length 1
- `ExistingSessionConnect.preserveWorkbenchView == true`
- `team` / `member` null for simple session

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && flutter test test/pages/chat/session_launch_retry_test.dart test/cubits/chat/retry_session_launch_test.dart`

Expected: FAIL

- [ ] **Step 4: Implement builder + cubit method**

Create `client/lib/pages/chat/session_launch_retry.dart`:

```dart
import '../../cubits/chat/model/session_connect_request.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/team/team_member_naming.dart';

ExistingSessionConnect? buildRetryExistingSessionConnect({
  required AppSession session,
  required String selectedMemberId,
  TeamProfile? team,
  bool preserveWorkbenchView = true,
}) {
  final isPersonal = session.sessionTeam.trim().isEmpty;
  if (isPersonal) {
    return ExistingSessionConnect(
      session: session,
      preserveWorkbenchView: preserveWorkbenchView,
    );
  }
  if (team == null) return null;

  TeamMemberConfig? member;
  final mid = selectedMemberId.trim();
  if (mid.isNotEmpty) {
    member = team.members.where((m) => m.id == mid).firstOrNull;
  }
  member ??= team.members.where(TeamMemberNaming.isTeamLead).firstOrNull;
  member ??= team.members.firstOrNull;

  return ExistingSessionConnect(
    session: session,
    team: team,
    member: member,
    preserveWorkbenchView: preserveWorkbenchView,
  );
}
```

Add to `ChatCubit` near `connectWorkspaceSession`:

```dart
Future<void> retrySessionLaunch(String sessionId) async {
  final id = sessionId.trim();
  if (id.isEmpty) return;
  final tab = tabStore.openTabBySessionId(id);
  AppSession? session;
  for (final s in state.sessions) {
    if (s.sessionId == id) {
      session = s;
      break;
    }
  }
  session ??= tab?.persistedSession;
  if (session == null) return;

  TeamProfile? team;
  final teamId = session.sessionTeam.trim();
  if (teamId.isNotEmpty) {
    team = await teamProfileById(teamId);
  }

  final request = buildRetryExistingSessionConnect(
    session: session,
    selectedMemberId: tab?.selectedMemberId ?? state.selectedMemberId,
    team: team,
  );
  if (request == null) return;
  await connectWorkspaceSession(request);
}
```

Import `session_launch_retry.dart` in `chat_cubit.dart`.

Refactor `SessionWorkbenchViewToggle` Chat→Terminal reconnect to use `buildRetryExistingSessionConnect(..., preserveWorkbenchView: false)` after it sets Terminal view (toggle still switches view; shared member resolution only).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && flutter test test/pages/chat/session_launch_retry_test.dart test/cubits/chat/retry_session_launch_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add \
  client/lib/pages/chat/session_launch_retry.dart \
  client/lib/cubits/chat_cubit.dart \
  client/lib/pages/chat/session_workbench_view_toggle.dart \
  client/test/pages/chat/session_launch_retry_test.dart \
  client/test/cubits/chat/retry_session_launch_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): add retrySessionLaunch with shared ExistingSessionConnect builder

EOF
)"
```

---

### Task 4: Wire Chat compose surface

**Files:**
- Modify: `client/lib/pages/chat/session_review_compose_card.dart`
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/pages/chat_workbench.dart` (pass connecting / onRetry if needed)

**Interfaces:**
- Consumes: `SessionLaunchErrorBanner`, `presentSessionLaunchFailure`, `shouldShowSessionLaunchErrorBanner`, `ChatCubit.retrySessionLaunch`
- Produces: Compose card shows shared banner with Retry when failed+idle

- [ ] **Step 1: Replace inline error in `SessionReviewComposeCard`**

Remove the local `DecoratedBox` error block and any `deadSshTargetIdFromError` usage that only served that block.

Add ctor params:

```dart
this.onRetry,
this.sessionConnectInProgress = false,
```

Render:

```dart
final failure = presentSessionLaunchFailure(launchError);
if (shouldShowSessionLaunchErrorBanner(
      launchError: launchError,
      sessionConnectInProgress: sessionConnectInProgress,
    ) &&
    failure != null) ...[
  SessionLaunchErrorBanner(
    view: failure,
    onRetry: onRetry,
    onRemapDeadTarget: onRemapDeadTarget,
    isRetrying: sessionConnectInProgress,
  ),
  SizedBox(height: spacing.md),
],
```

- [ ] **Step 2: Wire `SessionChatView`**

Where `SessionReviewComposeCard` is constructed, pass:

```dart
sessionConnectInProgress: /* true when ChatCubit.state.sessionConnectingId
  == session.sessionId — use BlocSelect or parent-provided flag */,
onRetry: () => unawaited(
  context.read<ChatCubit>().retrySessionLaunch(session.sessionId),
),
```

Prefer passing `sessionConnectInProgress` from `chat_workbench.dart` `_buildSessionChatView` via `slice.isActiveSessionConnecting` to avoid nested selects if already available.

- [ ] **Step 3: Analyze touched files**

Run: `cd client && dart analyze lib/pages/chat/session_review_compose_card.dart lib/pages/chat/session_chat_view.dart lib/pages/chat_workbench.dart`

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add \
  client/lib/pages/chat/session_review_compose_card.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/lib/pages/chat_workbench.dart
git commit -m "$(cat <<'EOF'
feat(chat): show shared launch error banner with retry on Chat compose

EOF
)"
```

---

### Task 5: Wire Terminal workbench top banner

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart` (`_buildTerminalBody` Stack)

**Interfaces:**
- Consumes: Task 1–3 APIs; existing `launchError`, `sessionConnectInProgress`, `onRemapDeadTargetFromLaunch`
- Produces: Top-aligned Terminal banner when `shouldShowTerminalSessionLaunchErrorBanner` is true

- [ ] **Step 1: Add Terminal banner layer**

In `_buildTerminalBody`, after resolving `overlay`:

```dart
final failure = presentSessionLaunchFailure(launchError);
final showTerminalLaunchError = shouldShowTerminalSessionLaunchErrorBanner(
  overlay: overlay,
  launchError: launchError,
  sessionConnectInProgress: sessionConnectInProgress,
);
```

Inside the workbench `Stack` children (last child so it paints on top):

```dart
if (showTerminalLaunchError && failure != null)
  Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.all(context.tpSpacing.md),
        child: SessionLaunchErrorBanner(
          view: failure,
          isRetrying: sessionConnectInProgress,
          onRetry: () {
            final id = slice.activeSessionId;
            if (id == null || id.isEmpty) return;
            unawaited(chatCubit.retrySessionLaunch(id));
          },
          onRemapDeadTarget: deadSshTargetIdFromError(launchError) != null
              ? () {
                  final id = slice.activeSessionId;
                  if (id == null || id.isEmpty) return;
                  unawaited(
                    onRemapDeadTargetFromLaunch(
                      launchError: launchError!,
                      sessionId: id,
                    ),
                  );
                }
              : null,
        ),
      ),
    ),
  ),
```

Import presenter, visibility, banner. Do **not** add `ChatWorkbenchOverlay.launchFailed`.

- [ ] **Step 2: Run targeted tests + analyze**

Run:

```bash
cd client && flutter test \
  test/pages/chat/session_launch_failure_presenter_test.dart \
  test/pages/chat/session_launch_error_visibility_test.dart \
  test/pages/chat/session_launch_error_banner_test.dart \
  test/pages/chat/session_launch_retry_test.dart \
  test/cubits/chat/retry_session_launch_test.dart \
  test/utils/session/session_launch_error_test.dart \
  test/pages/chat/chat_workbench_overlay_test.dart
```

Expected: PASS

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: clean for project norms / no new errors in touched files

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/chat_workbench.dart
git commit -m "$(cat <<'EOF'
feat(chat): show session launch failure banner on Terminal workbench

EOF
)"
```

---

### Task 6: Final verification

**Files:** none new

- [ ] **Step 1: Full required verification**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test \
  test/pages/chat/session_launch_failure_presenter_test.dart \
  test/pages/chat/session_launch_error_visibility_test.dart \
  test/pages/chat/session_launch_error_banner_test.dart \
  test/pages/chat/session_launch_retry_test.dart \
  test/cubits/chat/retry_session_launch_test.dart \
  test/utils/session/session_launch_error_test.dart \
  test/pages/chat/chat_workbench_overlay_test.dart
```

Expected: analyze OK; all listed tests PASS

- [ ] **Step 2: Manual checklist**

1. Fail a session spawn while on Terminal → top banner + Retry.
2. Switch to Chat → compose banner + Retry with same message.
3. Retry → connecting hides banner; success clears; failure resurfaces.
4. Dead SSH still offers remap before Retry.
5. Chat continue-from-history while connecting stays on Chat.

- [ ] **Step 3: Commit leftover fixes only if needed**

```bash
git status
```

---

## Spec coverage self-review

| Spec requirement | Task |
|------------------|------|
| Both Chat + Terminal surfaces | 4, 5 |
| Shared banner + Retry | 2, 4, 5 |
| Presenter / remap-then-retry | 1 |
| No auto view switch | 3 (`preserveWorkbenchView: true`) |
| Top Terminal banner, not new overlay enum | 5 |
| Hide while connecting | 1 + 4/5 |
| `retrySessionLaunch` API | 3 |
| Dead SSH remap | 2, 4, 5 |
| No Snackbar | no task adds one |
| Session-scoped team error v1 | unchanged model; 3 retries selected seat |
| Keep `writeToDisplay` | untouched |
| Tests in Global Constraints | 1–6 |
