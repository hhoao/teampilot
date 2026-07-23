# AI History Seat Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Isolate chat History per seat (`sessionId|shellMemberId`) so multi-workspace keep-alive sessions never mix transcripts, while hot seats keep live refresh.

**Architecture:** Split today’s single-runtime `AiHistoryCubit` into a facade registry plus per-seat `AiHistorySeat` cubits (each with its own `ExternalStoreAiThreadRuntime`). Wire scoped member / `isMemberRunning` / `routeActive` / tab-close eviction in the same deliverable.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `AiHistoryLoader`, `AiHistoryLiveRefreshController`, `ChatCubit` / `ChatTabStore`.

**Spec:** `docs/superpowers/specs/2026-07-23-ai-history-seat-isolation-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/session/history_seat_key.dart` | Pure `shellMemberIdForHistory` + `historySeatKey` |
| `client/lib/cubits/ai_history_seat.dart` | Per-seat `Cubit<AiHistoryState>` + runtime, load/softReload/pendings/tip-hold (logic moved from current cubit) |
| `client/lib/cubits/ai_history_cubit.dart` | Facade: seat map, seed pending by key, `ensureSeat` / `disposeSeatsForSession` / `softReloadIfSession` |
| `client/lib/services/session/ai_history_live_refresh_controller.dart` | Soft-reload **bound seat** (not bare facade `softReload`) |
| `client/lib/cubits/chat_cubit.dart` | Session-scoped `isMemberRunning`; call history dispose on tab tear-down; stale hook unchanged at app_shell |
| `client/lib/app/app_shell.dart` | Keep single `AiHistoryCubit` provider; optional `onSessionHistoryStale` stays |
| `client/lib/pages/chat/session_chat_view.dart` | Bind UI to seat cubit; scoped member; hot/warm live refresh |
| `client/lib/pages/chat/agent_permission_attention_banner.dart` | Require scoped `selectedMemberId` prop |
| `client/lib/pages/chat_page.dart` | Pass `routeActive` from `WorkspaceRouteActiveScope` |
| `client/lib/pages/chat/chat_page_shell.dart` | Honor `routeActive`; pass through to `ChatWorkbench` |
| `client/lib/pages/chat_workbench.dart` | Pass `routeActive` into `SessionChatView` (required for warm mode) |
| `client/lib/pages/chat/session_history_thread.dart` | Comment: runtime is seat-scoped |
| Tests under `client/test/services/session/`, `client/test/cubits/`, `client/test/pages/chat/` | As listed per task |

### Seat key (locked)

```dart
String shellMemberIdForHistory({
  required String sessionId,
  required String selectedMemberId,
}) {
  final mid = selectedMemberId.trim();
  return mid.isEmpty ? sessionId : mid;
}

String historySeatKey({
  required String sessionId,
  required String selectedMemberId,
}) {
  final shell = shellMemberIdForHistory(
    sessionId: sessionId,
    selectedMemberId: selectedMemberId,
  );
  return '$sessionId|$shell';
}
```

Same `shell` value is the `memberShells` map key and `isMemberRunning`’s `memberId`.

### Eviction owner (locked)

`ChatCubit._tearDownTab` → `onHistorySeatsDispose?.call(sessionId)` (or inject `AiHistoryCubit` callback) → `AiHistoryCubit.disposeSeatsForSession(sessionId)`.

---

### Task 1: Seat key helper (TDD)

**Files:**
- Create: `client/lib/services/session/history_seat_key.dart`
- Create: `client/test/services/session/history_seat_key_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/history_seat_key.dart';

void main() {
  test('simple empty member uses sessionId as shell segment', () {
    expect(
      historySeatKey(sessionId: 's1', selectedMemberId: ''),
      's1|s1',
    );
    expect(
      shellMemberIdForHistory(sessionId: 's1', selectedMemberId: '  '),
      's1',
    );
  });

  test('team member uses trimmed member id', () {
    expect(
      historySeatKey(sessionId: 's1', selectedMemberId: ' lead '),
      's1|lead',
    );
  });
}
```

- [ ] **Step 2: Run test — expect FAIL** (library missing)

Run: `cd client && flutter test test/services/session/history_seat_key_test.dart`

- [ ] **Step 3: Implement helper**

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit** (only if user asked to commit)

```bash
git add client/lib/services/session/history_seat_key.dart \
  client/test/services/session/history_seat_key_test.dart
git commit -m "$(cat <<'EOF'
feat(history): add shared history seat key helper

EOF
)"
```

---

### Task 2: Multi-seat isolation failing test on facade

**Files:**
- Create: `client/test/cubits/ai_history_seat_isolation_test.dart`
- Modify later: `client/lib/cubits/ai_history_cubit.dart` (Task 3)

- [ ] **Step 1: Write failing isolation test** (uses public `AiHistoryCubit` API)

```dart
test('two seats keep independent runtimes after load', () async {
  // Script loader: sess-a → messages labeled A; sess-b → messages labeled B
  final cubit = AiHistoryCubit(loader: scriptedLoader);
  await cubit.load(
    session: sessionA,
    memberId: '',
    launchContext: launchA,
  );
  await cubit.load(
    session: sessionB,
    memberId: '',
    launchContext: launchB,
  );

  final seatA = cubit.ensureSeat(
    sessionId: sessionA.sessionId,
    selectedMemberId: '',
  );
  final seatB = cubit.ensureSeat(
    sessionId: sessionB.sessionId,
    selectedMemberId: '',
  );

  expect(identical(seatA.runtime, seatB.runtime), isFalse);
  expect(seatA.runtime.messages.any((m) => /* A marker */), isTrue);
  expect(seatB.runtime.messages.any((m) => /* B marker */), isTrue);
  expect(seatA.runtime.messages.any((m) => /* B marker */), isFalse);
});

test('softReload seat A does not change seat B messages', () async {
  await cubit.load(session: sessionA, memberId: '', launchContext: launchA);
  await cubit.load(session: sessionB, memberId: '', launchContext: launchB);
  final seatA = cubit.ensureSeat(
    sessionId: sessionA.sessionId,
    selectedMemberId: '',
  );
  final seatB = cubit.ensureSeat(
    sessionId: sessionB.sessionId,
    selectedMemberId: '',
  );
  final bIdsBefore = seatB.runtime.messages.map((m) => m.id).toList();
  // Mutate loader so next A load returns an extra assistant tip, then:
  await seatA.softReload();
  expect(
    seatB.runtime.messages.map((m) => m.id).toList(),
    bIdsBefore,
  );
});

test('seedPendingUser for B while A loaded applies on B load only', () async {
  await cubit.load(session: sessionA, memberId: '', launchContext: launchA);
  cubit.seedPendingUser(
    sessionId: sessionB.sessionId,
    memberId: sessionB.sessionId, // shell id for simple
    text: 'hello-b',
  );
  expect(seatA.runtime.messages.any((m) => textHas(m, 'hello-b')), isFalse);
  await cubit.load(session: sessionB, memberId: '', launchContext: launchB);
  expect(seatB.runtime.messages.any((m) => textHas(m, 'hello-b')), isTrue);
});

test('disposeSeatsForSession removes seats and closes runtimes', () async {
  await cubit.load(...A...);
  cubit.disposeSeatsForSession(sessionA.sessionId);
  expect(cubit.seatOf(sessionId: sessionA.sessionId, selectedMemberId: ''), isNull);
});
```

Reuse fixtures / scripted locator patterns from `client/test/cubits/ai_history_cubit_test.dart`.

- [ ] **Step 2: Run test — expect FAIL** (no `ensureSeat` / shared runtime)

Run: `cd client && flutter test test/cubits/ai_history_seat_isolation_test.dart`

Do **not** implement production code until Task 3.

---

### Task 3: Extract `AiHistorySeat` + facade registry

**Files:**
- Create: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/cubits/ai_history_cubit.dart`
- Modify: `client/test/cubits/ai_history_cubit_test.dart` (point seat-specific asserts at `ensureSeat` / seat.runtime where needed)
- Keep exporting `AiHistoryState` / `AiHistoryViewStatus` from cubit file or seat file — one public home; update imports if moved

- [ ] **Step 1: Move per-seat fields/methods into `AiHistorySeat extends Cubit<AiHistoryState>`**

Seat owns:
- `runtime`, `_loadGeneration`, `_allMessages`, pendings, sticky, tip-hold, `_last*`
- `load`, `softReload`, `softReloadOrLoad`, `enqueuePendingUser`, `appendStickyLocalUser`, `removePendingMatching`, `setAwaitingAssistant`, `flushHeldTip`, `clearPendings`, `loadOlder`, `invalidateAndReload` (seat-local), `hasHeldAssistantTip`
- `close()` cancels timers + `runtime.close()`

Facade `AiHistoryCubit`:
- `final _seats = <String, AiHistorySeat>{}`
- `AiHistoryLoader loader` getter unchanged
- `ensureSeat({sessionId, selectedMemberId})` — create if missing
- `seatOf(...)` — nullable lookup
- `load` / `softReloadOrLoad` — resolve seat via `historySeatKey`, delegate
- `seedPendingUser` / `cancelSeedPendingUser` — key via `historySeatKey(sessionId, memberId)` so landing’s empty simple `memberId` still matches `sessionId|sessionId`; apply seed on that seat’s load completion
- `softReloadIfSession(sessionId)` — softReload every seat whose key starts with `sessionId|` (or matches session) and is ready
- `disposeSeatsForSession(sessionId)` — close+remove matching seats
- `clear()` — dispose all seats + clear seeds (for tests)
- **Remove** top-level `runtime` getter; fix all references including `client/test/integration/support/chat_thread_assertions.dart` and matrix harness callers
- Facade may stop extending meaningful `Cubit<AiHistoryState>` for UI — options:
  - **Preferred:** Facade remains `Cubit` but emits a cheap `AiHistoryRegistryState` (seat count / version) **or** keeps emitting last-focused seat state for backward compat during migration.
  - **Simplest for SessionChatView:** Facade is still `Cubit` but UI listens to **seat** via `BlocProvider.value`. Landing/`seedPending` keep using facade. Existing `BlocBuilder<AiHistoryCubit>` in SessionChatView migrates in Task 5.

Recommended transition in this task:
1. Extract seat class with all logic.
2. Facade methods create/get seat and delegate.
3. Temporary: facade `state` mirrors the seat that was last `load`ed (compat for old tests). Isolation tests use `ensureSeat`.
4. Task 5 removes UI dependence on facade state.

- [ ] **Step 2: Make isolation tests PASS**

Run: `cd client && flutter test test/cubits/ai_history_seat_isolation_test.dart test/cubits/ai_history_cubit_test.dart`

- [ ] **Step 3: Fix any broken unit tests** that still use `cubit.runtime` — use `cubit.ensureSeat(...).runtime` or last-loaded seat helper for single-seat tests.

- [ ] **Step 4: Commit** (if requested)

```bash
git commit -m "$(cat <<'EOF'
feat(history): isolate AiHistory per seat runtime

EOF
)"
```

---

### Task 4: Seat-bound live refresh

**Files:**
- Modify: `client/lib/services/session/ai_history_live_refresh_controller.dart`
- Modify: `client/test/services/session/ai_history_live_refresh_controller_test.dart`

- [ ] **Step 1: Write failing test** — controller calls `seat.softReload()`, not a shared facade softReload that could target another seat.

```dart
test('refreshNow softReloads bound seat only', () async {
  // Two seats loaded; controller constructed with seatA;
  // trigger onChanged; assert seatA loader force count++, seatB unchanged
});
```

- [ ] **Step 2: Run — expect FAIL** if controller still uses facade `softReload()` against last-loaded.

- [ ] **Step 3: Change constructor**

```dart
AiHistoryLiveRefreshController({
  required AiHistorySeat seat,
  required Filesystem Function() fs,
  required Future<AiHistoryWatchMeta?> Function() resolveWatchMeta,
  ...
});
```

Replace `_cubit.softReload()` with `_seat.softReload()`. Keep optional facade reference only if needed for loader — prefer seat’s loader via injected callback or `seat` owning softReload which uses shared loader from construction.

- [ ] **Step 4: Update unit tests now; wire `SessionChatView` construction in Task 6. Fix any compile breaks with temporary adapters if needed.**

- [ ] **Step 5: Commit** (if requested)

---

### Task 5: ChatCubit session-scoped running + history eviction

**Files:**
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart` (wire dispose callback if not injecting cubit)
- Create/modify: `client/test/cubits/chat_cubit_workspace_scope_test.dart` or new `chat_cubit_member_running_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('isMemberRunning finds shell on non-active workspace tab', () {
  // open tab in ws-a and ws-b; set active workspace to a;
  // mark member shell running on b's tab;
  // expect chat.isMemberRunning(sessionId: bSession, memberId: shellId) == true
});

test('closeTab disposes history seats for that session', () async {
  // with onHistorySeatsDispose spy or real AiHistoryCubit
});
```

- [ ] **Step 2: Implement**

```dart
bool isMemberRunning({
  required String sessionId,
  required String memberId,
}) {
  final tab = _tabStore.openTabBySessionId(sessionId);
  final shell = tab?.memberShells[memberId];
  return shell?.isRunning ?? false;
}
```

Remove or deprecate the old `isMemberRunning(String memberId)` that only checks `_activeTab`. Fix **all** compile errors from the signature change (search: `isMemberRunning`), including `chat_cubit_test.dart`, `chat_cubit_session_launch_test.dart`, integration harnesses, and UI call sites.

Add:

```dart
void Function(String sessionId)? onHistorySeatsDispose;
```

In `_tearDownTab`, after gathering `sessionId`:

```dart
onHistorySeatsDispose?.call(sessionId);
```

In `app_shell.dart`:

```dart
chatCubit.onHistorySeatsDispose = aiHistoryCubit.disposeSeatsForSession;
```

Keep:

```dart
chatCubit.onSessionHistoryStale = (id) {
  unawaited(aiHistoryCubit.softReloadIfSession(id));
};
```

- [ ] **Step 3: Run tests PASS**

- [ ] **Step 4: Commit** (if requested)

---

### Task 6: SessionChatView seat binding + scoped member + hot/warm

**Files:**
- Modify: `client/lib/pages/chat/session_chat_view.dart`
- Modify: `client/lib/pages/chat/agent_permission_attention_banner.dart`
- Modify: `client/test/pages/chat/agent_permission_attention_banner_test.dart`
- Optionally: widget test for scoped member if easy

- [ ] **Step 1: Banner API**

```dart
const AgentPermissionAttentionBanner({
  required this.session,
  required this.selectedMemberId,
  super.key,
});
```

Remove internal `context.select` of `ChatCubit.state.selectedMemberId`. Update call site:

```dart
AgentPermissionAttentionBanner(
  session: widget.session,
  selectedMemberId: widget.selectedMemberId,
),
```

- [ ] **Step 2: SessionChatView**

- On init / seat change: `final seat = context.read<AiHistoryCubit>().ensureSeat(...)` and keep `_seat` field; dispose live refresh on seat change.
- Replace `BlocBuilder<AiHistoryCubit, AiHistoryState>` with `BlocBuilder<AiHistorySeat, AiHistoryState>` via `BlocProvider.value(value: _seat!, child: ...)` **or** `BlocBuilder` with `bloc: _seat`.
- Pass `runtime: _seat!.runtime` into review messages.
- `_handleSubmit` / permission checks: use `widget.selectedMemberId` only (delete foreground `context.select` / `read` of `selectedMemberId`).
- `_maybeStartLiveRefreshForRunningPty` / awaiting path:

```dart
final running = chat.isMemberRunning(
  sessionId: widget.session.sessionId,
  memberId: _shellMemberId,
);
final hot = widget.routeActive || running; // add routeActive prop if needed
if (!hot) {
  await _liveRefresh?.stop();
  return;
}
```

Add `routeActive` to `SessionChatView` (default `true` for tests) plumbed from workbench/shell.

- Construct `AiHistoryLiveRefreshController(seat: _seat!, ...)`.
- Migrate **all** History mutations in this file off the facade state/runtime onto `_seat`: `clearPendings`, `flushHeldTip`, `appendStickyLocalUser`, `enqueuePendingUser`, `setAwaitingAssistant`, reads of `history.state.awaitingAssistant` / `state.status`. Facade remains only for `ensureSeat` / landing seed from other files.

- [ ] **Step 3: Run banner + relevant chat tests**

Run: `cd client && flutter test test/pages/chat/agent_permission_attention_banner_test.dart test/cubits/ai_history_cubit_test.dart test/cubits/ai_history_seat_isolation_test.dart`

- [ ] **Step 4: Commit** (if requested)

---

### Task 7: Wire `routeActive` from workspace scope → SessionChatView

**Files:**
- Modify: `client/lib/pages/chat_page.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart` (verify buildWhen / pass-through to `ChatWorkbench`)
- Modify: `client/lib/pages/chat_workbench.dart` — **must** pass `routeActive` into `SessionChatView` in `_buildSessionChatView` (default `true` alone leaves background seats permanently hot)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_route_active_scope.dart` (read API if needed)

- [x] **Step 1: In `ChatPage.build`**

```dart
final routeActive = WorkspaceRouteActiveScope.routeActiveOf(context);
return ChatPageShell(
  ...
  routeActive: routeActive,
);
```

- [x] **Step 2: Plumb `ChatPageShell.routeActive` → `ChatWorkbench.routeActive` → `SessionChatView(routeActive: widget.routeActive, ...)`**. Grep for `SessionChatView(` and ensure every production call site passes it.

- [x] **Step 3: Ensure `_scopedTabBuildWhen` skips heavy rebuilds when `routeActive == false`**.

- [x] **Step 4: Add a small unit/widget assertion that warm path stops live refresh when `routeActive == false` and member not running (can live next to Task 8 or as a `SessionChatView` harness test). Spec warm-seat case must not be manual-only.

- [ ] **Step 5: Commit** (if requested)

---

### Task 8: Widget isolation test + comment cleanup

**Files:**
- Modify: `client/test/pages/chat/session_history_thread_test.dart` (update comment)
- Create: `client/test/pages/chat/ai_history_multi_seat_widget_test.dart` (or extend isolation)

- [ ] **Step 1: Widget test**

Two `SessionHistoryThread` widgets, each with a different `ExternalStoreAiThreadRuntime` from two seats on one facade. SoftReload/update seat A → only A’s finder texts change; B unchanged.

- [ ] **Step 2: Update comment in `session_history_thread.dart`**

From “app-scoped” to “seat-scoped; sync notify may still fire during sibling deferred mount”.

- [ ] **Step 3: Run PASS**

- [ ] **Step 4: Commit** (if requested)

---

### Task 9: Verification

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Targeted tests**

```bash
cd client && flutter test \
  test/services/session/history_seat_key_test.dart \
  test/cubits/ai_history_cubit_test.dart \
  test/cubits/ai_history_seat_isolation_test.dart \
  test/services/session/ai_history_live_refresh_controller_test.dart \
  test/pages/chat/agent_permission_attention_banner_test.dart \
  test/pages/chat/session_history_thread_test.dart \
  test/pages/chat/ai_history_multi_seat_widget_test.dart
```

Also run any `chat_cubit_*` tests touched and `test/pages/home_workspace/workspace_isolation_widget_test.dart` if present.

- [ ] **Step 3: Broader unit suite (exclude integration)** if time:

```bash
cd client && flutter test --exclude-tags integration
```

- [ ] **Step 4: Success criteria check** (from spec)

1. Two seats cannot share one runtime message list.
2. Hot/warm behavior: live refresh only when `routeActive || isMemberRunning`.
3. Scoped member + banner + `isMemberRunning(sessionId:)`.
4. Tab close disposes seats.
5. Existing single-seat behaviors still pass `ai_history_cubit_test.dart`.

---

## Notes for implementers

- **TDD:** For each task, watch the new test fail before implementing.
- **Do not** leave a public `AiHistoryCubit.runtime` singleton after Task 3/6.
- **Integration harness** (`CliMessageMatrixHarness`): update to `ensureSeat` / seat.runtime when compile breaks; matrix cells remain single-seat.
- **Commits:** Only when the user explicitly asks; plan steps mark commit as optional.
- Prefer small diffs: move logic first (Task 3), then wire UI (Task 6–7).
