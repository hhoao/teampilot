# History Live Continue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep History as the default continue surface after submit (preference-gated Terminal switch), and near-real-time refresh the conversation from on-disk CLI transcripts while the seat PTY runs.

**Architecture:** Preference gates the existing PTY inject path. A `TranscriptChangeSignal` (local `FsWatcher` or cache-token poll) drives `AiHistoryCubit.softReload` with tip-Δ pagination and optimistic pending user bubbles. `AiHistoryLiveRefreshController` owns lifecycle while History is visible.

**Tech Stack:** Dart / Flutter (`flutter_bloc`, existing `Filesystem` / `FsWatcher`, `ai_message_core`, `ai_message_ui`); no new packages.

**Spec:** [`docs/superpowers/specs/2026-07-18-history-live-continue-design.md`](../specs/2026-07-18-history-live-continue-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Modify: `client/lib/models/session_preferences.dart` | `historySubmitSwitchesToTerminal` (default `false`) |
| Modify: `client/lib/cubits/session_preferences_cubit.dart` | Setter + persist |
| Modify: `client/lib/pages/config/session_config_section.dart` | Settings switch |
| Modify: `client/lib/utils/ui/app_keys.dart` | Switch key |
| Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb` | Strings (+ regenerate / warmup glyphs if required by repo habit) |
| Modify: `client/test/models/session_preferences_test.dart` | Default + JSON |
| Create: `client/lib/services/session/ai_history_watch_meta.dart` | Parse/build watch roots + token paths from bundle hints |
| Modify: `client/lib/services/cli/registry/capabilities/history/claude_ai_transcript.dart` (and flashskyai / codex / opencode / cursor) | Emit `changeWatchRoot` + `cacheTokenPaths` hints from locate |
| Modify: stale-history hook wiring (e.g. `client/lib/app/app_shell.dart` or wherever `onSessionHistoryStale` → `invalidateAndReload`) | Return-to-History uses softReload when already ready for same seat |
| Create: `client/lib/services/session/transcript_change_signal.dart` | Watch or poll → `Stream<void>` / callback |
| Create: `client/test/services/session/transcript_change_signal_test.dart` | Watch vs poll |
| Modify: `client/lib/cubits/ai_history_cubit.dart` | `softReload`, pending queue, tip-Δ, no loading flash |
| Modify: `client/test/cubits/ai_history_cubit_test.dart` | softReload + pending tests |
| Create: `client/lib/services/session/ai_history_live_refresh_controller.dart` | Start/stop, coalesce, call softReload |
| Create: `client/test/services/session/ai_history_live_refresh_controller_test.dart` | Lifecycle |
| Modify: `client/lib/pages/chat_workbench.dart` | Gate Terminal switch on preference |
| Modify: `client/lib/pages/chat/session_history_review.dart` | Wire controller, pending on submit, running footer |
| Modify: `client/lib/pages/chat/session_history_thread.dart` | New-messages chip (host chrome) |
| Create/Modify tests under `client/test/pages/chat/` | Submit stay/switch; chip smoke |

**Not in this plan:** stream-json runtime, incremental parsers, WebView, permission auto-detect (optional jump banner can be a stub button later — skip unless trivial).

---

### Task 1: Preference `historySubmitSwitchesToTerminal`

**Files:**
- Modify: `client/lib/models/session_preferences.dart`
- Modify: `client/lib/cubits/session_preferences_cubit.dart`
- Modify: `client/lib/pages/config/session_config_section.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/test/models/session_preferences_test.dart`
- Mirror any `_SessionConfigSnapshot` fields / equality in `session_config_section.dart`

- [ ] **Step 1: Write failing preference tests**

Extend `session_preferences_test.dart`:

```dart
test('historySubmitSwitchesToTerminal defaults false', () {
  expect(SessionPreferences().historySubmitSwitchesToTerminal, isFalse);
});

test('historySubmitSwitchesToTerminal JSON round-trip', () {
  final prefs = SessionPreferences(historySubmitSwitchesToTerminal: true);
  final again = SessionPreferences.fromJson(prefs.toJson());
  expect(again.historySubmitSwitchesToTerminal, isTrue);
});
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/models/session_preferences_test.dart
```

Expected: compile/runtime fail — field missing.

- [ ] **Step 3: Implement field end-to-end**

In `SessionPreferences`: constructor default `false`, `fromJson` (`?? false`), `copyWith`, `toJson`.

In `SessionPreferencesCubit`: `setHistorySubmitSwitchesToTerminal(bool)` mirroring `setOpenExistingSessionStartsTerminal`.

In `session_config_section.dart`: new `TpPreferenceRow` **immediately below** the open-existing-session switch:

- EN title: `Switch to Terminal after continue`
- EN description: `When off (default), submitting from History keeps the conversation view and refreshes from the transcript while the terminal runs in the background. When on, switch to the terminal after submit (previous behavior).`
- ZH: 对等文案（开启则提交后切到终端；关闭默认留在 History）
- Bind switch **directly** to `historySubmitSwitchesToTerminal` (ON = switch; no inverted UI).

Add `AppKeys.historySubmitSwitchesToTerminalSwitch`.

Run `flutter gen-l10n` if ARB alone does not update generated files in this repo’s workflow; if `warmup_glyphs` is required after ARB changes, run `dart run tool/gen_warmup_glyphs.dart`.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/models/session_preferences_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_preferences.dart \
  client/lib/cubits/session_preferences_cubit.dart \
  client/lib/pages/config/session_config_section.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/test/models/session_preferences_test.dart
git commit -m "$(cat <<'EOF'
feat(history): add preference to switch to Terminal on continue

Default stays on History; settings toggle restores legacy submit behavior.
EOF
)"
```

---

### Task 2: Watch metadata hints on locate

**Files:**
- Create: `client/lib/services/session/ai_history_watch_meta.dart`
- Create: `client/test/services/session/ai_history_watch_meta_test.dart`
- Modify: `claude_ai_transcript.dart`, `flashskyai_ai_transcript.dart`, `codex_ai_transcript.dart`, `opencode_ai_transcript.dart`, `cursor_ai_transcript.dart` (locate only)

- [ ] **Step 1: Write failing meta helper tests**

```dart
test('reads changeWatchRoot and cacheTokenPaths from hints', () {
  final meta = AiHistoryWatchMeta.fromHints({
    'changeWatchRoot': '/proj',
    'cacheTokenPaths': '/proj/a.jsonl\n/proj/b.jsonl',
  });
  expect(meta?.changeWatchRoot, '/proj');
  expect(meta?.cacheTokenPaths, ['/proj/a.jsonl', '/proj/b.jsonl']);
});

test('returns null when root missing', () {
  expect(AiHistoryWatchMeta.fromHints({'cacheToken': 'x'}), isNull);
});
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/session/ai_history_watch_meta_test.dart
```

- [ ] **Step 3: Implement helper + emit hints from each locate**

```dart
class AiHistoryWatchMeta {
  const AiHistoryWatchMeta({
    required this.changeWatchRoot,
    required this.cacheTokenPaths,
  });
  final String changeWatchRoot;
  final List<String> cacheTokenPaths;

  static const hintRoot = 'changeWatchRoot';
  static const hintPaths = 'cacheTokenPaths';

  static AiHistoryWatchMeta? fromHints(Map<String, String> hints) { /* ... */ }

  Map<String, String> toHints() => {
    hintRoot: changeWatchRoot,
    hintPaths: cacheTokenPaths.join('\n'),
  };
}
```

For each locate success path, merge into `hints`:

| CLI | `changeWatchRoot` | `cacheTokenPaths` |
|-----|-------------------|-------------------|
| Claude / flashskyai / Codex | `dirname(matchedPath)` | `[matchedPath]` |
| Cursor | dirname of agent transcript jsonl (same as matched file parent) | `[matchedPath]` |
| OpenCode | session storage directory used for fragments | **Collect the absolute paths of every file actually `readBytes`'d during locate** into `cacheTokenPaths` (fragments alone have no absolute paths) |

Keep existing `cacheToken` hint. Prefer spreading `...AiHistoryWatchMeta(...).toHints()`.

- [ ] **Step 4: Run locate/unit tests for history adapters + new meta test**

```bash
cd client && flutter test \
  test/services/session/ai_history_watch_meta_test.dart \
  test/services/cli/registry/capabilities/history/
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): emit watch roots from transcript locate

Give live refresh a shared changeWatchRoot + cacheTokenPaths hint.
EOF
)"
```

---

### Task 3: `TranscriptChangeSignal`

**Files:**
- Create: `client/lib/services/session/transcript_change_signal.dart`
- Create: `client/test/services/session/transcript_change_signal_test.dart`

- [ ] **Step 1: Write failing tests with fake clock + mock fs**

Cover:

1. When `fs is FsWatcher`: `watchTree(root)` event → debounced notify (~150ms).
2. When fs is not `FsWatcher`: poll `stat` on `cacheTokenPaths`; token change → notify (~750ms interval injectable).
3. `close()` cancels watch/timer; no further notifies.
4. Empty/missing paths: poll still ticks; notify only when token string changes (including first non-empty).

Use constructor injection:

```dart
class TranscriptChangeSignal {
  TranscriptChangeSignal({
    required Filesystem fs,
    required String? Function() watchRoot,
    required List<String> Function() cacheTokenPaths,
    required void Function() onChanged,
    Duration watchDebounce = const Duration(milliseconds: 150),
    Duration pollInterval = const Duration(milliseconds: 750),
    Duration Function()? sftpPollInterval, // or bool isRemote → 1200ms
  });
  Future<void> start();
  Future<void> stop();
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/session/transcript_change_signal_test.dart
```

- [ ] **Step 3: Implement**

- Feature-detect `fs is FsWatcher`.
- Watch: `watchTree(root)`, debounce coalesced `onChanged`.
- Poll: compute token via `aiHistoryPathCacheToken` (or path|mtime|size join across paths); compare to last; on change call `onChanged`.
- If `watchRoot()` is null: poll-only using paths; if both empty, still poll on interval but re-invoke getters so late locate can populate (controller will refresh getters after softReload/locate).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): add TranscriptChangeSignal watch/poll

Local FsWatcher with debounce; remote backends poll cache tokens.
EOF
)"
```

---

### Task 4: `AiHistoryCubit.softReload` + optimistic pendings

**Files:**
- Modify: `client/lib/cubits/ai_history_cubit.dart`
- Modify: `client/test/cubits/ai_history_cubit_test.dart`
- Optional small helper: `client/lib/services/session/ai_history_pending_text.dart` for normalize + text extract

- [ ] **Step 1: Write failing tests**

```dart
test('softReload grows visibleCount by tip delta and preserves start', () async {
  // load 40 msgs → visible = kSessionHistoryInitialTurns (30)
  // loadOlder once → visible 50 capped to 40
  // then softReload with 42 msgs → visible 42, start = 0 still? 
  // Actually: oldLength=40, oldVisible=40, tipDelta=2 → visible=42, start=0
});

test('softReload does not emit loading when already ready', () async {
  // listen states; softReload; never see loading
});

test('softReload truncate clamps visibleCount', () async { /* newLength < old */ });

test('pending user merges then drops on matching tip user text', () async {
  cubit.enqueuePendingUser('hello world');
  // softReload messages include user "hello world" → pending gone from runtime tip
});

test('multi pending drops independently by normalized text', () async {
  cubit.enqueuePendingUser('a');
  cubit.enqueuePendingUser('b');
  // reload with only "a" → one pending remains
});

test('softReload no-ops after seat clear / generation bump', () async {
  // start softReload, clear() mid-flight, ensure no apply
});
```

Normalize helper:

```dart
String normalizeAiHistoryPendingText(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String aiHistoryUserPlainText(AiMessage m) => m.parts
    .whereType<AiTextPart>()
    .map((p) => p.text)
    .join('\n');
```

Drop rule per spec: tip window last `N` user turns, `N = max(pendingQueue.length + 2, 5)`.

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/cubits/ai_history_cubit_test.dart
```

- [ ] **Step 3: Implement**

API sketch:

```dart
Future<void> softReload() async {
  // MUST invalidate / force:true so AiHistoryLoader does not return a stale cache hit.
  /* tip-Δ apply via _applySoftReloadMessages */
}

void enqueuePendingUser(String text) { /* pending:<uuid> */ }

void clearPendings() { /* seat change */ }

void _applySoftReloadMessages(List<AiMessage> messages, ...) {
  final oldLength = _allMessages.length;
  final oldVisible = _visibleCount;
  // AFTER await returns — snapshot here
  _allMessages = messages;
  final newLength = messages.length;
  final tipDelta = math.max(0, newLength - oldLength);
  if (newLength < oldLength) {
    _visibleCount = math.min(oldVisible, newLength);
  } else {
    _visibleCount = math.min(newLength, oldVisible + tipDelta);
  }
  _dropMatchedPendings();
  _emitReadyWindow(...);
  _remergePendingsOntoRuntime();
}
```

Never call `runtime.setLoading()` / emit `loading` from softReload. On parse failure: keep prior messages/window; set a non-blocking error on state (add optional `softReloadError` / reuse a strip field — **must surface in UI**, not log-only) and retry on next change.

`enqueuePendingUser` / seat change in `load()` when sessionId/memberId changes → `clearPendings()`.

Also add both return-path APIs in this task (Task 6 wires them):

```dart
/// Review remount: soft when already ready for this seat, else cold load.
Future<void> softReloadOrLoad({
  required AppSession session,
  required String memberId,
  TeamProfile? team,
  String? workingDirectory,
}) async {
  if (state.status == AiHistoryViewStatus.ready &&
      state.sessionId == session.sessionId &&
      state.memberId == memberId) {
    await softReload();
    return;
  }
  await load(
    session: session,
    memberId: memberId,
    team: team,
    workingDirectory: workingDirectory,
  );
}

/// Stale hook from ChatCubit (`app_shell.dart`): soft when ready for sessionId.
Future<void> softReloadIfSession(String sessionId) async {
  if (state.status == AiHistoryViewStatus.ready &&
      state.sessionId == sessionId) {
    await softReload();
    return;
  }
  await invalidateAndReload(sessionId);
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): softReload with tip-Δ window and pending users

Live continue can refresh without loading flash or pagination yank.
EOF
)"
```

---

### Task 5: `AiHistoryLiveRefreshController`

**Files:**
- Create: `client/lib/services/session/ai_history_live_refresh_controller.dart`
- Create: `client/test/services/session/ai_history_live_refresh_controller_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('start attaches signal and softReloads on change', () async { ... });
test('second change while reload in flight coalesces to one follow-up', () async { ... });
test('stop cancels signal and ignores late callbacks', () async { ... });
```

Controller API:

```dart
class AiHistoryLiveRefreshController {
  AiHistoryLiveRefreshController({
    required AiHistoryCubit cubit,
    required Filesystem Function() fs,
    required Future<AiHistoryWatchMeta?> Function() resolveWatchMeta,
    // injectable signal factory for tests
  });

  Future<void> start();
  Future<void> stop();
  Future<void> refreshNow(); // force softReload once (return-to-History)
}
```

On start: `refreshNow()` once, then start signal. On change: coalesce (`_reloadQueued` flag).

`resolveWatchMeta`: call loader/locator path — simplest: cubit exposes last watch meta updated inside softReload/load from bundle hints; or controller calls a `AiHistoryLoader.peekWatchMeta(...)` added in this task.

Prefer: extend `AiHistoryLoader` with `Future<AiHistoryWatchMeta?> resolveWatchMeta({session, memberId, team, cwd})` that runs context+locate without full parse when possible (locate already reads bytes today — OK to reuse locate and read hints only).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement controller + `resolveWatchMeta` on loader**

Poll interval: if `fs is! FsWatcher` use 1200ms else 750ms (pass into signal).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): add AiHistoryLiveRefreshController

Coalesce transcript change signals into softReload while History is live.
EOF
)"
```

---

### Task 6: Gate submit view switch + wire review lifecycle

**Files:**
- Modify: `client/lib/pages/chat_workbench.dart` (`onSubmit` ~593–596)
- Modify: `client/lib/pages/chat/session_history_review.dart`
- Modify: `client/lib/app/app_shell.dart` (`onSessionHistoryStale` ~935–936)
- Modify: `client/lib/cubits/ai_history_cubit.dart` (`softReloadOrLoad` if not done in Task 4)
- Create or modify: `client/test/pages/chat/session_history_continue_chrome_test.dart` (or new gated-switch test)

- [ ] **Step 1: Write failing tests for preference gate + return-to-History soft path**

Unit-test preference gate:

```dart
bool shouldSwitchToTerminalAfterHistorySubmit(
  bool historySubmitSwitchesToTerminal,
) => historySubmitSwitchesToTerminal;
```

Cubit/widget test: when status already `ready` for same seat, return-to-History path must call softReload (no `loading` emission), **not** `invalidateAndReload` / full `load()`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement wiring (locked return-to-History behavior)**

**Submit (`chat_workbench.dart`):**

```dart
final switchToTerminal = context
    .read<SessionPreferencesCubit>()
    .state
    .preferences
    .historySubmitSwitchesToTerminal;
if (switchToTerminal) {
  chatCubit.setSessionWorkbenchView(
    appSession.sessionId,
    SessionWorkbenchView.terminal,
  );
}
final ok = await submitSessionHistoryReviewMessage(...);
// SessionHistoryReview handles pending + refresh when ok && !switchToTerminal
return ok;
```

In `SessionHistoryReview` after successful submit with stay:

```dart
context.read<AiHistoryCubit>().enqueuePendingUser(trimmed);
await _liveRefresh.ensureStarted();
```

**Return-to-History / remount (spec: force softReload once — no hard load flash):**

1. Change `app_shell.dart` stale hook from unconditional `invalidateAndReload` to:

```dart
chatCubit.onSessionHistoryStale = (sessionId) {
  unawaited(aiHistoryCubit.softReloadIfSession(sessionId));
  // softReloadIfSession: if last session matches and ready → softReload;
  // else invalidateAndReload (cold)
};
```

2. Change `SessionHistoryReview._loadHistory` / init: if cubit already `ready` for this session+member, call `softReload()` (or skip and `refreshNow()` via controller) instead of `load()` that emits loading.

3. Do **not** stack `invalidateAndReload` + `refreshNow()` on the same transition.

Lifecycle for live refresh:

- Start when History mounted AND (seat PTY running OR just submitted).
- `dispose` / leave History body: `stop()`.
- Seat change: `clearPendings()`, stop/start controller.

- [ ] **Step 4: Run related tests**

```bash
cd client && flutter test \
  test/pages/chat/session_history_review_submit_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart \
  test/cubits/ai_history_cubit_test.dart
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): stay on History after continue by default

Gate Terminal switch on preference; softReload on return; start live refresh.
EOF
)"
```

---

### Task 7: New-messages chip + running footer

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Modify: `client/lib/pages/chat/session_history_review.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Modify: `client/test/pages/chat/session_history_thread_test.dart`

- [ ] **Step 1: Write failing tests**

- When stick paused and messages grow, chip finder appears.
- Tapping chip scrolls to tip / resumes stick.
- Optional: running footer visible when `liveRefreshActive` flag passed into review.

Reuse existing stick-to-bottom machinery in `SessionHistoryThread` — add chip overlay; do not change cubit pagination.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement UX chrome**

l10n:

- `sessionHistoryNewMessages` → `New messages` / `新消息`
- `sessionHistoryRunning` → `Running…` / `运行中…`

Footer: slim text under thread / above compose when controller active.

- [ ] **Step 4: Run thread + review tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(history): new-messages chip and running footer for live continue

Keep scrolled-up reading stable while tip updates from softReload.
EOF
)"
```

---

### Task 8: Verification sweep

**Files:** none new (fix only)

- [ ] **Step 1: Analyze + unit tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration \
  test/models/session_preferences_test.dart \
  test/services/session/ \
  test/cubits/ai_history_cubit_test.dart \
  test/pages/chat/ \
  test/services/cli/registry/capabilities/history/
```

Expected: no new errors; listed tests PASS.

- [ ] **Step 2: Manual smoke (implementer)**

1. Open existing Claude session → History → submit with default prefs → stays History; pending bubble; assistant/tools appear within ~2s local.
2. Toggle preference on → submit switches to Terminal.
3. Scroll up during run → chip; tap → tip.
4. History ↔ Terminal toggle still works; return to History refreshes.

- [ ] **Step 3: Final commit if fixes needed**

```bash
git commit -m "$(cat <<'EOF'
fix(history): live continue verification follow-ups
EOF
)"
```

---

## Execution notes

- Follow TDD order inside each task; do not skip “run fail” when practical.
- SSH: rely on poll path; do not assume `FsWatcher`.
- Keep `AiHistoryRenderScope` on History thread — softReload must not switch to full live markdown.
- `@` skills when executing: `superpowers:subagent-driven-development` or `superpowers:executing-plans`; use `superpowers:test-driven-development` per task.
