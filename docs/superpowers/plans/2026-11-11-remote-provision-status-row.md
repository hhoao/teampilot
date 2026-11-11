# 远程环境准备改为聊天状态行反馈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop covering the Chat view with the full-pane remote-provision overlay; instead show a fixed "Preparing remote environment…" label in the existing in-thread running/starting footer.

**Architecture:** `resolveChatWorkbenchOverlay` stops letting `showRemoteProvision` win in the Chat view (other views keep the pane). A new pure function `remoteProvisionFooterLabel` derives a fixed label from the existing `memberRemoteProvision` progress; `session_chat_message_area.dart` reads that progress with `seatSelect` and threads the label through `SessionHistoryReviewMessages` into `SessionHistoryThread._buildRunningInMessage`, which already renders the spinner + single-line footer. No new widget, no new i18n key, no progress bar.

**Tech Stack:** Flutter / Dart, `flutter_bloc` (`context.select` via local `seatSelect` helper), slang-generated l10n (`context.l10n`), `flutter_test` + `dart run tool/run_tests.dart`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-11-11-remote-provision-status-row-design.md` (committed as `3a0acf873`).
- **Never invoke `flutter test` directly** — always `cd client && dart run tool/run_tests.dart <paths/options>`; concurrent direct runs corrupt the shared build cache.
- **Test loop: fast inner, slow outer.** Inner loop is `flutter analyze`; verify with one test file (`--plain-name` to narrow); full suite only once before claiming done, in the background.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- **l10n:** slang-based; edit `client/lib/i18n/<feature>_en.i18n.json` / `_zh.i18n.json`, then regenerate with `cd client && dart run slang` (never via build_runner). **This plan adds no i18n keys** — it reuses `session.remoteProvisionPreparing`. Do not run `dart run slang`.
- **Logging:** user errors → l10n; diagnostics → `AppLogger`; no `print`.
- **Tests:** mock subprocess/filesystem via constructor injection; new integration tests use `@Tags(['integration'])` from `package:test`.
- Chat view label is **fixed** `「正在准备远程环境…」` / `「Preparing remote environment…」`, no host name, no phase detail, no progress bar.
- Terminal view keeps the existing `ChatWorkbenchRemoteProvisionView` pane, unchanged.
- `shouldMountWorkbenchTerminal` keeps receiving the raw `showRemoteProvision` bool — do not change it.
- Do not delete `ChatWorkbenchRemoteProvisionView`, `memberRemoteProvision`, or `setMemberRemoteProvisionProgress`.
- Working tree has unrelated in-flight edits. **Stage only the files this plan touches** in every commit; never `git add -A`.

---

## File Structure

| File | Responsibility |
|---|---|
| `client/lib/pages/chat/session_history_live_chrome.dart` | Pure `remoteProvisionFooterLabel(progress, label)` helper (no Flutter/l10n import). |
| `client/lib/pages/chat/session_history_thread.dart` | New optional `provisioningLabel` field; footer label override. |
| `client/lib/pages/chat/session_history_review_messages.dart` | Forward `provisioningLabel` to the thread. |
| `client/lib/pages/chat/session_chat_message_area.dart` | Read `memberRemoteProvision` via `seatSelect`, compute label, promote `none` → `starting`, pass down. |
| `client/lib/pages/chat/chat_workbench_overlay.dart` | `resolveChatWorkbenchOverlay`: Chat view never yields to `remoteProvision`. |
| `client/lib/pages/chat_workbench.dart` | Drive pane render + `chatOverlayHidesTerminal` from `overlay`, not the raw bool. |
| `client/test/pages/chat/session_history_live_chrome_test.dart` | Unit tests for the pure helper. |
| `client/test/pages/chat/session_history_thread_test.dart` | Widget tests for the footer override. |
| `client/test/pages/chat/session_history_review_messages_test.dart` | Widget test for forwarding. |
| `client/test/pages/chat/chat_workbench_overlay_test.dart` | Updated overlay-resolution expectations. |

---

### Task 1: Pure `remoteProvisionFooterLabel` helper

**Files:**
- Modify: `client/lib/pages/chat/session_history_live_chrome.dart`
- Test: `client/test/pages/chat/session_history_live_chrome_test.dart`

**Interfaces:**
- Consumes: `MemberRemoteProvisionProgress` from `client/lib/models/member_remote_provision_progress.dart` (`hasFailed` getter).
- Produces: `String? remoteProvisionFooterLabel(MemberRemoteProvisionProgress? progress, String preparingLabel)` — later tasks call this with `context.l10n.session.remoteProvisionPreparing`.

- [ ] **Step 1: Write the failing tests**

Append this group to `client/test/pages/chat/session_history_live_chrome_test.dart` (inside `main()`, after the existing `SessionHistoryLiveChromeX.resolve` group) and add the two imports at the top:

```dart
import 'package:teampilot/models/member_remote_provision_progress.dart';
import 'package:teampilot/services/cli/installer_types.dart';
```

```dart
  group('remoteProvisionFooterLabel', () {
    const preparing = 'Preparing remote environment…';

    MemberRemoteProvisionProgress progress({String? error}) =>
        MemberRemoteProvisionProgress(
          memberId: 'm1',
          phase: CliInstallPhase.syncingRemoteWorkspace,
          hostLabel: 'dev-box',
          error: error,
        );

    test('null when no provision is in flight', () {
      expect(remoteProvisionFooterLabel(null, preparing), isNull);
    });

    test('returns the fixed label while provisioning', () {
      expect(remoteProvisionFooterLabel(progress(), preparing), preparing);
    });

    test('null when provision failed', () {
      expect(
        remoteProvisionFooterLabel(progress(error: 'boom'), preparing),
        isNull,
      );
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_live_chrome_test.dart
```

Expected: FAIL — `Error: Couldn't find constructor 'remoteProvisionFooterLabel'` / undefined name (compile error is fine here; the point is the helper does not exist yet).

- [ ] **Step 3: Implement the helper**

In `client/lib/pages/chat/session_history_live_chrome.dart`, add the import as the first line:

```dart
import '../../models/member_remote_provision_progress.dart';
```

Append after the `SessionHistoryLiveChromeX` extension:

```dart
/// Fixed footer label while an SSH member's remote environment is provisioning.
///
/// Returns null when there is no provision in flight or when it failed, so the
/// existing [SessionHistoryLiveChrome] label (Starting… / Running…) is used.
/// Takes a plain [String] so this file needs no BuildContext or l10n lookup.
String? remoteProvisionFooterLabel(
  MemberRemoteProvisionProgress? progress,
  String preparingLabel,
) {
  if (progress == null || progress.hasFailed) return null;
  return preparingLabel;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_live_chrome_test.dart
```

Expected: PASS — all pre-existing tests plus the 3 new ones.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_history_live_chrome.dart client/test/pages/chat/session_history_live_chrome_test.dart
git commit -m "feat(chat): add pure remoteProvisionFooterLabel helper"
```

---

### Task 2: Overlay resolver stops covering Chat

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_overlay.dart:24-37`
- Test: `client/test/pages/chat/chat_workbench_overlay_test.dart:40-49`

**Interfaces:**
- Consumes: `resolveWorkbenchOverlay` (`client/lib/cubits/session/workbench_overlay_resolver.dart`), `ChatWorkbenchOverlay` enum (same file).
- Produces: same signature `ChatWorkbenchOverlay resolveChatWorkbenchOverlay({required SessionWorkbenchView workbenchView, required bool sessionConnectInProgress, required bool showRemoteProvision})`; new behavior — returns `chat` whenever `workbenchView == SessionWorkbenchView.chat`.

- [ ] **Step 1: Write the failing tests**

In `client/test/pages/chat/chat_workbench_overlay_test.dart`, replace the single test at lines 40-49 (`'remote provision wins over Chat and connect spinner'`) with these three:

```dart
    test('Chat stays visible while remote provision is in progress', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.chat,
          sessionConnectInProgress: true,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.chat,
      );
    });

    test('Chat stays visible while provision is in progress and idle', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.chat,
          sessionConnectInProgress: false,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.chat,
      );
    });

    test('Terminal shows remote provision over connect spinner', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.terminal,
          sessionConnectInProgress: true,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.remoteProvision,
      );
    });

    test('Terminal shows remote provision even when connect flag is false', () {
      expect(
        resolveChatWorkbenchOverlay(
          workbenchView: SessionWorkbenchView.terminal,
          sessionConnectInProgress: false,
          showRemoteProvision: true,
        ),
        ChatWorkbenchOverlay.remoteProvision,
      );
    });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/chat_workbench_overlay_test.dart
```

Expected: FAIL on `'Chat stays visible while remote provision is in progress'` — `Expected: ChatWorkbenchOverlay.chat, Actual: ChatWorkbenchOverlay.remoteProvision`.

- [ ] **Step 3: Implement the resolver change**

Replace the body of `resolveChatWorkbenchOverlay` in `client/lib/pages/chat/chat_workbench_overlay.dart`:

```dart
ChatWorkbenchOverlay resolveChatWorkbenchOverlay({
  required SessionWorkbenchView workbenchView,
  required bool sessionConnectInProgress,
  required bool showRemoteProvision,
}) {
  final base = resolveWorkbenchOverlay(
    phase: sessionConnectInProgress
        ? SessionPhase.connecting
        : SessionPhase.running,
    historyStatus: AiHistoryViewStatus.ready,
    view: workbenchView,
  );
  // Chat already renders an in-thread provisioning footer; never cover it with
  // the full-pane overlay. Other views keep the provision pane.
  if (showRemoteProvision && base != ChatWorkbenchOverlay.chat) {
    return ChatWorkbenchOverlay.remoteProvision;
  }
  return base;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/chat_workbench_overlay_test.dart
```

Expected: PASS — all tests in the file (8 resolver tests + 3 `shouldMountWorkbenchTerminal` tests = 11).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_overlay.dart client/test/pages/chat/chat_workbench_overlay_test.dart
git commit -m "fix(chat): keep Chat visible during remote provisioning"
```

---

### Task 3: `SessionHistoryThread` footer label override

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart:68-107`, `:1003-1019`
- Test: `client/test/pages/chat/session_history_thread_test.dart:31-68`, add tests near `:869`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SessionHistoryThread({..., String? provisioningLabel})` — Task 4 forwards it, Task 5 supplies it. When non-null it replaces the footer's `label` text; the spinner/hourglass choice stays driven by `liveChrome`.

- [ ] **Step 1: Write the failing tests**

In `client/test/pages/chat/session_history_thread_test.dart`, add `String? provisioningLabel` to the `_harness` helper (line 31-43) and forward it:

```dart
Widget _harness({
  required AiThreadRuntime runtime,
  bool hasOlder = false,
  bool isLoadingOlder = false,
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
  String? backgroundLabel,
  String? provisioningLabel,
  Future<void> Function()? onLoadOlder,
  ValueNotifier<String?>? visibleOwnerId,
  bool? mobilePerformanceMode,
  bool expandLatest = true,
  double width = 600,
  double height = 400,
}) {
```

and inside `SessionHistoryThread(...)`:

```dart
          liveChrome: liveChrome,
          backgroundLabel: backgroundLabel,
          provisioningLabel: provisioningLabel,
          onLoadOlder: onLoadOlder,
```

Add these two tests right after `'starting footer visible when liveChrome is starting'` (line 882). The harness locale is `en`, hence the English strings. `_pumpLive` (line 72) is required because the footer spinner never settles:

```dart
  testWidgets('provisioningLabel replaces the starting footer text', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(5));

    await tester.pumpWidget(
      _harness(
        runtime: store,
        liveChrome: SessionHistoryLiveChrome.starting,
        provisioningLabel: 'Preparing remote environment…',
      ),
    );
    await _pumpLive(tester);

    expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
    expect(find.text('Preparing remote environment…'), findsOneWidget);
    expect(find.text('Starting…'), findsNothing);
  });

  testWidgets('footer keeps its existing label when provisioningLabel is null', (
    tester,
  ) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(5));

    await tester.pumpWidget(
      _harness(
        runtime: store,
        liveChrome: SessionHistoryLiveChrome.starting,
      ),
    );
    await _pumpLive(tester);

    expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
    expect(find.text('Starting…'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart --plain-name "provisioningLabel"
```

Expected: FAIL — compile error `The named parameter 'provisioningLabel' isn't defined`.

- [ ] **Step 3: Implement the field and the override**

In `client/lib/pages/chat/session_history_thread.dart`, add the constructor parameter next to `backgroundLabel` (line 74):

```dart
    this.liveChrome = SessionHistoryLiveChrome.none,
    this.backgroundLabel,
    this.provisioningLabel,
    this.pendingDeliveryStatuses = const {},
```

Add the field right after `backgroundLabel` (line 107):

```dart
  /// What the out-of-turn background work is doing (e.g. the background shell
  /// task's description). Appended to the background footer so the row says
  /// what is still running, not just that something is.
  final String? backgroundLabel;

  /// Fixed status text while an SSH member's remote environment provisions.
  /// Overrides the [liveChrome] label; the spinner is still chosen by
  /// [liveChrome]. Null keeps the existing Starting… / Running… copy.
  final String? provisioningLabel;
```

In `_buildRunningInMessage` (line 1003), change only the `label` assignment so the switch becomes the fallback:

```dart
    final backgroundLabel = widget.backgroundLabel?.trim() ?? '';
    final label = widget.provisioningLabel ?? switch (widget.liveChrome) {
      SessionHistoryLiveChrome.starting => context.l10n.session.historyStarting,
      SessionHistoryLiveChrome.background =>
        backgroundLabel.isEmpty
            ? context.l10n.session.historyBackgroundRunning
            : '${context.l10n.session.historyBackgroundRunning} · '
                  '$backgroundLabel',
      SessionHistoryLiveChrome.running ||
      SessionHistoryLiveChrome.none => context.l10n.session.historyRunning,
    };
```

Leave `isBackground`, the spinner choice, padding, key, and `Text` widget untouched.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart
```

Expected: PASS — whole file, including the pre-existing `'starting footer visible when liveChrome is starting'`.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_history_thread.dart client/test/pages/chat/session_history_thread_test.dart
git commit -m "feat(chat): allow provisioning label override on history footer"
```

---

### Task 4: Forward `provisioningLabel` through `SessionHistoryReviewMessages`

**Files:**
- Modify: `client/lib/pages/chat/session_history_review_messages.dart:24-53`, `:151-157`
- Test: `client/test/pages/chat/session_history_review_messages_test.dart:16-48`

**Interfaces:**
- Consumes: `SessionHistoryThread.provisioningLabel` (Task 3).
- Produces: `SessionHistoryReviewMessages({..., String? provisioningLabel})` — Task 5 passes it.

- [ ] **Step 1: Write the failing test**

In `client/test/pages/chat/session_history_review_messages_test.dart`, add `String? provisioningLabel` to `_harness` (line 16-24) and forward it into `SessionHistoryReviewMessages(...)`:

```dart
Widget _harness({
  required AiHistoryState state,
  required AiThreadRuntime runtime,
  Map<String, FailedMessageStatus> pendingDeliveryStatuses = const {},
  ValueChanged<String>? onRetryFailedMessage,
  bool suppressEmptyPane = false,
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
  String pendingUserText = '',
  String? provisioningLabel,
}) {
```

```dart
          suppressEmptyPane: suppressEmptyPane,
          liveChrome: liveChrome,
          pendingUserText: pendingUserText,
          provisioningLabel: provisioningLabel,
```

Add the test (mirrors the proven harness at line 158-179 of the same file — note `AiHistoryState` has **no** `messages` field, so use `setEmpty()` + `suppressEmptyPane: true`):

```dart
  testWidgets('forwards provisioningLabel to the running footer', (
    tester,
  ) async {
    final runtime = ExternalStoreAiThreadRuntime()..setEmpty();

    await tester.pumpWidget(
      _harness(
        state: const AiHistoryState(status: AiHistoryViewStatus.empty),
        runtime: runtime,
        suppressEmptyPane: true,
        liveChrome: SessionHistoryLiveChrome.starting,
        provisioningLabel: 'Preparing remote environment…',
      ),
    );
    // The Starting footer spins forever; settle on fixed frames.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byKey(kSessionHistoryRunningFooterKey), findsOneWidget);
    expect(find.text('Preparing remote environment…'), findsOneWidget);
    expect(find.text('Starting…'), findsNothing);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_review_messages_test.dart --plain-name "forwards provisioningLabel"
```

Expected: FAIL — compile error `The named parameter 'provisioningLabel' isn't defined`.

- [ ] **Step 3: Implement the forwarding**

In `client/lib/pages/chat/session_history_review_messages.dart`, add the constructor param (after `backgroundLabel`, line 30):

```dart
    this.liveChrome = SessionHistoryLiveChrome.none,
    this.backgroundLabel,
    this.provisioningLabel,
    this.pendingDeliveryStatuses = const {},
```

Add the field after `backgroundLabel` (line 53):

```dart
  /// What the out-of-turn background work is doing, forwarded to the thread
  /// footer (see [SessionHistoryThread.backgroundLabel]).
  final String? backgroundLabel;

  /// Fixed status text while a remote environment provisions, forwarded to
  /// [SessionHistoryThread.provisioningLabel].
  final String? provisioningLabel;
```

Forward it in the `SessionHistoryThread(...)` call (line 156-157):

```dart
              liveChrome: liveChrome,
              backgroundLabel: backgroundLabel,
              provisioningLabel: provisioningLabel,
              pendingDeliveryStatuses: pendingDeliveryStatuses,
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_review_messages_test.dart
```

Expected: PASS — whole file.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_history_review_messages.dart client/test/pages/chat/session_history_review_messages_test.dart
git commit -m "feat(chat): forward provisioningLabel through review messages"
```

---

### Task 5: Read provision progress in the chat surface and drive the label

**Files:**
- Modify: `client/lib/pages/chat/session_chat_message_area.dart` (imports, ~line 323, `buildChrome` ~324-390)

**Interfaces:**
- Consumes: `remoteProvisionFooterLabel` (Task 1), `SessionHistoryReviewMessages.provisioningLabel` (Task 4), `ChatCubit.tabStore.getOpenTabBySessionId(sid)?.memberRemoteProvision` (`client/lib/services/chat/session/chat_tab.dart:172`), `seatSelect` (`client/lib/pages/chat/session_seat_working.dart:31`), `context.l10n.session.remoteProvisionPreparing`.
- Produces: `provisioningLabel` supplied to `SessionHistoryReviewMessages`; `liveChrome` promoted from `none` to `starting` when a label exists.

This task has no new unit test of its own (it is a `seatSelect` + wiring layer; the leaf behavior is covered by Tasks 1/3/4). Verification is `flutter analyze` plus the four targeted test files.

- [ ] **Step 1: Add the import**

Add to the import block in `client/lib/pages/chat/session_chat_message_area.dart`:

```dart
import '../../models/member_remote_provision_progress.dart';
```

- [ ] **Step 2: Add the progress read and computed label**

Immediately before `Widget buildChrome(` (line 324), inside the same builder scope where `sid` and `shellMemberId` are available, add:

```dart
                                    // Live remote-provision status for this
                                    // seat. Read independently of
                                    // chat_workbench.dart:429 — both Chat body
                                    // paths mount this widget, so the footer
                                    // works whether or not a shell exists yet.
                                    final remoteProvision =
                                        seatSelect<ChatCubit,
                                            MemberRemoteProvisionProgress?>(
                                      context,
                                      (c) => c.tabStore
                                          .getOpenTabBySessionId(sid)
                                          ?.memberRemoteProvision[shellMemberId],
                                    );
                                    final provisioningLabel =
                                        remoteProvisionFooterLabel(
                                      remoteProvision,
                                      l10n.session.remoteProvisionPreparing,
                                    );
```

`l10n` is already in scope from `final l10n = context.l10n;` at line 112. Do **not** select only a bool and look the progress up afterwards — `context.select` needs the new progress instance (or `null`) to trigger rebuilds.

- [ ] **Step 3: Promote `none` → `starting` and pass the label down**

Inside `buildChrome`, immediately after the existing `final liveChrome = SessionHistoryLiveChromeX.resolve(...)` block (ends line 347), add:

```dart
                                      // Background work keeps its own label;
                                      // provisioning only labels the send/wait
                                      // window. If no footer would otherwise
                                      // show, force `starting` so the label is
                                      // actually visible.
                                      final labelForChrome =
                                          liveChrome ==
                                                  SessionHistoryLiveChrome
                                                      .background
                                              ? null
                                              : provisioningLabel;
                                      final effectiveLiveChrome =
                                          labelForChrome != null &&
                                                  liveChrome ==
                                                      SessionHistoryLiveChrome
                                                          .none
                                              ? SessionHistoryLiveChrome
                                                  .starting
                                              : liveChrome;
```

Then change the two `SessionHistoryReviewMessages` arguments currently at lines 364-365 from:

```dart
                                              liveChrome: liveChrome,
                                              backgroundLabel: backgroundLabel,
```

to:

```dart
                                              liveChrome: effectiveLiveChrome,
                                              backgroundLabel: backgroundLabel,
                                              provisioningLabel: labelForChrome,
```

Do not change `buildChrome`'s signature, the `sessionHasLeases` call sites (lines 402, 414), or any other `liveChrome` usage.

- [ ] **Step 4: Verify with analyze and targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors/infos from the touched files.

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/session_history_live_chrome_test.dart test/pages/chat/session_history_thread_test.dart test/pages/chat/session_history_review_messages_test.dart test/pages/chat/chat_workbench_overlay_test.dart
```

Expected: PASS for all four files.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_chat_message_area.dart
git commit -m "feat(chat): show remote provision status in the in-thread footer"
```

---

### Task 6: Drive the pane from `overlay` in `chat_workbench.dart`

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart:577`, `:602-603`, `:634`

**Interfaces:**
- Consumes: `resolveChatWorkbenchOverlay` (Task 2) and `ChatWorkbenchOverlay.remoteProvision`.
- Produces: `showRemoteProvisionOverlay` local used by the render branch and `chatOverlayHidesTerminal`.

- [ ] **Step 1: Introduce `showRemoteProvisionOverlay`**

After line 577 (`final showSessionStarting = ...`), add:

```dart
    final showRemoteProvisionOverlay =
        overlay == ChatWorkbenchOverlay.remoteProvision;
```

- [ ] **Step 2: Use it for terminal hiding**

Replace lines 602-603:

```dart
    final chatOverlayHidesTerminal =
        showSessionStarting || showChat || showRemoteProvision;
```

with:

```dart
    final chatOverlayHidesTerminal =
        showSessionStarting || showChat || showRemoteProvisionOverlay;
```

- [ ] **Step 3: Use it for pane rendering**

Replace line 634:

```dart
                if (showRemoteProvision)
```

with:

```dart
                if (showRemoteProvisionOverlay)
```

Keep the `ChatWorkbenchRemoteProvisionView(...)` body (lines 635-641) unchanged — Terminal view still uses it. Keep `showRemoteProvision` (line 560) as-is: it still feeds `shouldMountWorkbenchTerminal` (line 568) and `resolveChatWorkbenchOverlay` (line 574).

- [ ] **Step 4: Verify with analyze and targeted tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new issues.

```bash
cd client && dart run tool/run_tests.dart test/pages/chat/chat_workbench_overlay_test.dart test/pages/chat/chat_workbench_remote_provision_view_test.dart
```

Expected: PASS — the overlay test reflects the new Chat behavior, and the provision-view test (Terminal view) is unchanged.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat_workbench.dart
git commit -m "fix(chat): render remote provision pane only outside Chat view"
```

---

### Task 7: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: clean (pre-existing infos/warnings from unrelated in-flight edits may appear; no new ones from this plan's files).

- [ ] **Step 2: Full test suite, in the background**

```bash
cd client && dart run tool/run_tests.dart
```

Run in background per the project's "fast inner, slow outer" rule; wait for completion before claiming done. Expected: no failures. If an unrelated in-flight test fails, report it separately rather than "fixing" it.

- [ ] **Step 3: Manual acceptance check (mobile / SSH target)**

Verify on an Android device connected to an SSH target:

1. In a new conversation, type a first message and send. The screen stays in the Chat view: the user bubble is visible, history scrolls, the composer is usable.
2. The bottom footer shows one spinner + `正在准备远程环境…`. No progress bar, no full-pane overlay, no second status row.
3. When the environment is ready the footer transitions to `运行中…` and the reply arrives.
4. Repeat from an existing conversation that triggers a reconnect — same behavior.
5. Desktop local-PTY session: no visible change.
6. Switch to Terminal view during provisioning: the original `ChatWorkbenchRemoteProvisionView` pane still shows; on failure the Chat view shows the compose error banner with Retry.

- [ ] **Step 4: Report**

Report the exact commands run and their results. Do not claim done if the full suite has failures attributable to this change.

---

## Self-Review (completed)

**Spec coverage:**
- Chat view no overlay → Task 2 (resolver) + Task 6 (render).
- Existing footer, fixed label, no progress bar, no host → Task 1 (fixed label), Task 3 (override), spec's 状态行设计 constraints.
- Landing create+send → covered by Task 5 reading at `session_chat_message_area.dart` level (both Chat body paths), verified in Task 7 step 3.
- Terminal view keeps pane → Task 2 test + Task 6 Step 3 keeps the widget body.
- Desktop local PTY unchanged → `seatSelect` returns null when `memberRemoteProvision` is empty; Task 7 step 3(5).
- Failure surfaced via compose banner → `remoteProvisionFooterLabel` returns null on `hasFailed` (Task 1); existing `SessionLaunchErrorBanner` untouched, verified in Task 7 step 3(6).
- `shouldMountWorkbenchTerminal` unchanged → Task 6 Step 3 note.
- No i18n changes → Global Constraints + no `dart run slang` step.
- Tests → Tasks 1-4 + Task 7 full suite.

**Placeholder scan:** no TBD/TODO/"implement later"/"add appropriate handling"/"similar to Task N". Every code step contains complete code.

**Type consistency:** `remoteProvisionFooterLabel(MemberRemoteProvisionProgress?, String) → String?` (Task 1) matches Task 5's call; `provisioningLabel` is `String?` in Task 3 (`SessionHistoryThread`), Task 4 (`SessionHistoryReviewMessages`), and Task 5 (computed value). `showRemoteProvisionOverlay` introduced in Task 6 Step 1 is used in Steps 2-3 with the same name. `effectiveLiveChrome` / `labelForChrome` are local to Task 5 Step 3 and used in the same step.
