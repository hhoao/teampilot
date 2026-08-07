# Thin ChatCubit slice: pod owns the session workbench view

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the session `workbenchView` (chat vs terminal) off `ChatTab` and onto the `SessionPod` — a first concrete step of the thin-ChatCubit sweep: the pod becomes the canonical per-session source of this UI state, and the launch machinery gains a narrow pod-write port.

**Architecture:** Add one narrow method `setPodView(sessionId, view)` to `SessionConnectStatePort` (implemented by `ChatCubit` → `podRuntime(sid).setView(...)`). `setSessionWorkbenchView` writes the pod (and keeps the tab in sync). The launch surface coordinator's two `tab.workbenchView = terminal` writes route through `_host.setPodView`. Readers (`chat_workbench.dart`, `right_tools_tool_views.dart`) read the pod's view first, falling back to the tab.

**Tech Stack:** Flutter / flutter_bloc. Tests: `flutter test` (unit + widget).

## Global Constraints

- Follow the SessionPod spec (`docs/superpowers/specs/2026-08-07-session-pod-architecture-design.md`); keep existing behavior — the view toggle and the connect-time "starts in terminal" preference must still work.
- Every task ends green: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test <target>`.
- Commit after each task.
- The pod stays the canonical view source; `ChatTab.workbenchView` remains in sync during the transition but is no longer the read path.

---

### Task 1: `setPodView` port + pod-driven `setSessionWorkbenchView`

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_host.dart` (`SessionConnectStatePort`)
- Modify: `client/lib/cubits/chat_cubit.dart` (`setSessionWorkbenchView`, implement `setPodView`)
- Test: `client/test/cubits/chat_cubit_view_pod_test.dart`

**Interfaces:**
- Consumes: `SessionPod`/`SessionPodState.view`, `ChatCubit.podRuntime`.
- Produces: `void setPodView(String sessionId, SessionWorkbenchView view)` on `SessionConnectStatePort` (and `SessionLaunchHost`); `setSessionWorkbenchView` writes the pod.

- [ ] **Step 1: Write the failing test**

Create `client/test/cubits/chat_cubit_view_pod_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/session_workbench_view.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  late ChatCubit cubit;

  setUp(() {
    setUpTestAppStorage();
    cubit = testChatCubit(executableResolver: () => 'true');
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test('setSessionWorkbenchView writes the pod view', () {
    cubit.ensurePodRuntime('s1');
    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.chat);

    cubit.setSessionWorkbenchView('s1', SessionWorkbenchView.terminal);

    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.terminal);
  });

  test('setPodView (host port) writes the pod view', () {
    cubit.ensurePodRuntime('s1');
    cubit.setPodView('s1', SessionWorkbenchView.terminal);
    expect(cubit.podFor('s1')!.view, SessionWorkbenchView.terminal);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/chat_cubit_view_pod_test.dart`
Expected: FAIL — `setPodView` not defined; `setSessionWorkbenchView` does not write the pod.

- [ ] **Step 3: Implement**

In `client/lib/cubits/chat/session_launch_host.dart`, add to `SessionConnectStatePort` (and the `SessionLaunchHost` union):

```dart
  /// Sets the pod's chat-vs-terminal view for [sessionId].
  void setPodView(String sessionId, SessionWorkbenchView view);
```

Check the file's imports for `SessionWorkbenchView` (add if missing).

In `client/lib/cubits/chat_cubit.dart`, add the implementation and update `setSessionWorkbenchView`:

```dart
  @override
  void setPodView(String sessionId, SessionWorkbenchView view) {
    podRuntime(sessionId)?.setView(view);
  }

  void setSessionWorkbenchView(String sessionId, SessionWorkbenchView view) {
    final pod = podRuntime(sessionId);
    if (pod != null && pod.state.view == view) return;
    setPodView(sessionId, view);
    final tab = _tabStore.openTabBySessionId(sessionId);
    if (tab != null && tab.workbenchView != view) {
      tab.workbenchView = view;
    }
    emit(state.copyWith(stateVersion: state.stateVersion + 1));
    if (view == SessionWorkbenchView.chat) {
      onSessionHistoryStale?.call(sessionId);
    }
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/cubits/chat_cubit_view_pod_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the chat cubit + view-toggle tests**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_simple_working_test.dart test/pages/chat/session_workbench_view_toggle_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/test/cubits/chat_cubit_view_pod_test.dart
git commit -m "feat(session): setPodView port — pod owns the workbench view

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 2: Launch surface writes route through `setPodView`; readers prefer the pod

**Files:**
- Modify: `client/lib/services/launch/session_tab_surface_coordinator.dart`
- Modify: `client/lib/pages/chat_workbench.dart`
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart`
- Test: `client/test/pages/chat/chat_workbench_view_test.dart` (new) or extend `chat_workbench_overlay_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchHost.setPodView` (Task 1), `ChatCubit.podFor`.
- Produces: `tab.workbenchView = terminal` becomes `_host.setPodView(tab.info.id, terminal)`; readers use `podFor(sid)?.view ?? tab?.workbenchView ?? chat`.

- [ ] **Step 1: Write the failing test**

Add to `client/test/pages/chat/chat_workbench_overlay_test.dart` (or a new `chat_workbench_view_test.dart`) a widget test that pumps `ChatWorkbench` with a pod whose `view` is terminal and a slice whose active session is that session, asserting the workbench resolves terminal:

```dart
testWidgets('workbench reads the pod view for the active session', (tester) async {
  // ChatCubit mock whose podFor(sid) returns view: terminal; slice.activeSessionId == sid.
  // Pump ChatWorkbench; expect the terminal surface (or the workbenchView resolution) is terminal.
});
```

If `ChatWorkbench` is too heavy to pump, test the resolution function directly by extracting the `workbenchView` select into a small pure helper `resolveWorkbenchViewFor(podView, tabView)` — prefer this.

- [ ] **Step 2: Implement**

In `session_tab_surface_coordinator.dart`, replace both `tab.workbenchView = SessionWorkbenchView.terminal;` / `existing.workbenchView = SessionWorkbenchView.terminal;` with `_host.setPodView(tab.info.id, SessionWorkbenchView.terminal);` / `_host.setPodView(existing.info.id, SessionWorkbenchView.terminal);`.

In `chat_workbench.dart`, change the `workbenchView` select to prefer the pod:

```dart
    final workbenchView = context.select<ChatCubit, SessionWorkbenchView>((c) {
      final activeId = slice.activeSessionId;
      if (activeId == null || activeId.isEmpty) {
        return SessionWorkbenchView.chat;
      }
      final podView = c.podFor(activeId)?.view;
      if (podView != null) return podView;
      final tab = c.tabStore.openTabBySessionId(activeId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });
```

In `right_tools_tool_views.dart:632`, mirror the same pod-first read:

```dart
    final podView = context.read<ChatCubit>().podFor(sessionId)?.view;
    return podView ?? tab?.workbenchView ?? SessionWorkbenchView.chat;
```

- [ ] **Step 3: Run test to verify it passes**

Run: `cd client && flutter test test/pages/chat/ test/widgets/`
Expected: PASS.

- [ ] **Step 4: Run the launch surface tests**

Run: `cd client && flutter test test/services/launch/session_tab_surface_coordinator_test.dart`
Expected: PASS (the coordinator now writes the pod; behavior is unchanged since the tab is also in sync from Task 1).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_tab_surface_coordinator.dart client/lib/pages/chat_workbench.dart client/lib/widgets/right_tools/right_tools_tool_views.dart client/test/pages/chat/
git commit -m "refactor(workbench): view read/write routes through the pod

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 3: Full verification

- [ ] **Step 1: Run the full affected suite**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/cubits/chat/ test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_simple_working_test.dart test/services/launch/ test/pages/chat/ test/pages/chat_workbench_terminal_key_test.dart test/widgets/`
Expected: PASS.

- [ ] **Step 2: Grep for leftover direct workbenchView reads**

Run: `grep -rn "workbenchView" client/lib --include="*.dart" | grep -v "session_workbench_view.dart\|_test\|setSessionWorkbenchView\|setPodView\|chat_tab.dart"`
Expected: only the pod-first reads (with `tab?.workbenchView` fallback) and the `ChatTab` field declaration remain.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore(workbench): full-suite green after pod-owned view

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** thin ChatCubit direction — the pod now canonically owns the workbench view; the launch machinery writes it through a narrow port; `ChatTab.workbenchView` stays in sync during transition (read path already pod-first).
- **Risk:** the `setSessionWorkbenchView` no-op guard moved from the tab to the pod; the double-emit (pod `setView` onChanged + method emit) is accepted for this slice and folded into a later emit-dedup cleanup.
- **Placeholders:** none — every code step shows the code.
