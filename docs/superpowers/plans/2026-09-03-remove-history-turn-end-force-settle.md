# Remove History turn-end force settle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete seat Layer-2 turn-end `softReload(force: true)` settle so late Cursor flushes are owned only by live watch + warm incremental reload.

**Architecture:** Keep JSONL EOF Layer 1. Remove `_scheduleTurnEndSettle` / delayed timer from `AiHistorySeat.flushHeldTip`. Prove late flush via `AiHistoryLiveRefreshController` change signal → `softReload(force: false)`. Do not add coalesce guards or replacement timers.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `AiHistoryCubit` / `AiHistoryLiveRefreshController` fakes in `client/test/`.

**Spec:** `docs/superpowers/specs/2026-09-03-remove-history-turn-end-force-settle-design.md`

## Global Constraints

- Warm incremental-only after first parse: `force` must not mean full JSONL reparse.
- No defensive programming: no “if live running skip settle”, no post-frame deferral, no new fixed delay.
- No CLI `if (cli == cursor)` branches.
- Do not call `softReloadIfSession` / `invalidate` on turn end.
- `softReload({force})` API may remain for manual/explicit callers; seat turn-end must not use it.
- Commits only when the user asks (skip Step “Commit” unless requested).

## File map

| File | Role |
|------|------|
| `client/lib/cubits/ai_history_seat.dart` | Delete settle timer + schedule/cancel; stop calling settle from `flushHeldTip` / `enqueuePendingUser` / `close` |
| `client/lib/services/session/history_awaiting_working_sync.dart` | Remove `historyTurnEndSettleDelay` |
| `client/test/cubits/ai_history_seat_turn_end_settle_test.dart` | Replace settle-positive tests with negative “flushHeldTip does not reload” |
| `client/test/services/session/ai_history_live_refresh_controller_test.dart` | Add late-flush-via-watch regression |
| `docs/superpowers/specs/2026-08-19-history-turn-end-settle-design.md` | Mark Layer 2 superseded |
| `docs/superpowers/specs/2026-09-03-remove-history-turn-end-force-settle-design.md` | Status → Approved |
| `docs/cli-formats/cursor.md` | Drop force-settle sentence |

---

### Task 1: Live-watch late-flush regression

**Files:**
- Modify: `client/test/services/session/ai_history_live_refresh_controller_test.dart`
- Test: same file

**Interfaces:**
- Consumes: existing `buildController`, `_FakeSignal.fire()`, `pumpEventQueue`, advancing `resolveCacheToken` in this file’s `setUp`
- Produces: test name `live change reveals late assistant flush without flushHeldTip`

- [ ] **Step 1: Write the regression test**

Append inside `main()` (reuse helpers already in the file — `simpleSession`, `launchCtx`, `seatFor`, `buildController`, `messagesBySession`):

```dart
  test(
    'live change reveals late assistant flush without flushHeldTip',
    () async {
      locator.emitBundle = true;
      final session = simpleSession();
      messagesBySession[session.sessionId] = [
        const AiMessage(
          id: 'u-A',
          role: AiRole.user,
          parts: [AiTextPart(text: 'ask-A')],
        ),
        const AiMessage(
          id: 'a-A',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'tools-A')],
        ),
      ];
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = seatFor(session);
      expect(seat.state.totalMessageCount, 2);

      // Simulate turn chrome clear without seat settle reload.
      seat.enqueuePendingUser('ask-A');
      seat.applyWorkingSessionSync(sessionWorking: true);
      seat.applyWorkingSessionSync(sessionWorking: false);
      await pumpEventQueue();
      expect(seat.state.awaitingAssistant, isFalse);

      final controller = buildController(
        seat: seat,
        reloadMinInterval: Duration.zero,
      );
      await controller.start(skipInitialRefresh: true);

      messagesBySession[session.sessionId] = [
        const AiMessage(
          id: 'u-A',
          role: AiRole.user,
          parts: [AiTextPart(text: 'ask-A')],
        ),
        const AiMessage(
          id: 'a-A',
          role: AiRole.assistant,
          parts: [
            AiTextPart(text: 'tools-A'),
            AiTextPart(text: 'final-A'),
          ],
        ),
      ];
      lastSignal!.fire();
      await pumpEventQueue();

      expect(
        seat.loadedMessages
            .where((m) => m.role == AiRole.assistant)
            .expand(
              (m) => m.parts.whereType<AiTextPart>().map((p) => p.text),
            ),
        contains('final-A'),
        reason: 'late flush must arrive via live softReload(force: false)',
      );
      await controller.stop();
    },
  );
```

- [ ] **Step 2: Run test — expect PASS (documents existing watch path)**

Run: `cd client && dart run tool/run_tests.dart test/services/session/ai_history_live_refresh_controller_test.dart`

Expected: PASS (including the new test). If FAIL, fix the test harness first — do not reintroduce settle.

- [ ] **Step 3: Commit** (only if user requested commits)

```bash
git add client/test/services/session/ai_history_live_refresh_controller_test.dart
git commit -m "$(cat <<'EOF'
test(history): cover late flush via live watch without seat settle

EOF
)"
```

---

### Task 2: Failing seat test — flushHeldTip must not reload

**Files:**
- Modify: `client/test/cubits/ai_history_seat_turn_end_settle_test.dart`

**Interfaces:**
- Consumes: same frozen-token loader harness already in this file
- Produces: test asserting `final-A` is **absent** after `clearAwaiting` / `flushHeldTip`

- [ ] **Step 1: Replace the three settle-positive tests with one negative test**

Delete the three existing tests. Keep the harness (`messagesBySession`, frozen `resolveCacheToken: (_) async => 'frozen'`, `_SessionMapAdapter`, etc.). Add:

```dart
  test(
    'flushHeldTip endAwaiting does not softReload under frozen cache token',
    () async {
      locator.emitBundle = true;
      final session = simpleSession();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = cubit.ensureSeat(
        sessionId: session.sessionId,
        selectedMemberId: '',
      );
      expect(seat.state.totalMessageCount, 2);

      messagesBySession['sess-a'] = transcript('A', withFinal: true);

      seat.enqueuePendingUser('ask-A');
      seat.applyWorkingSessionSync(sessionWorking: true);
      expect(
        seat.applyWorkingSessionSync(sessionWorking: false),
        HistoryAwaitingWorkingAction.clearAwaiting,
      );
      await pumpEventQueue();
      // Allow any legacy delayed settle timer to fire if still present.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await pumpEventQueue();

      expect(
        seat.loadedMessages
            .where((m) => m.role == AiRole.assistant)
            .expand(
              (m) => m.parts.whereType<AiTextPart>().map((p) => p.text),
            ),
        ['tools-A'],
        reason:
            'turn-end chrome must not force-reload; live watch owns late flush',
      );
      expect(seat.state.awaitingAssistant, isFalse);
    },
  );
```

Remove the import of `history_awaiting_working_sync.dart` **only if** `HistoryAwaitingWorkingAction` is no longer needed — keep it because the test still uses `HistoryAwaitingWorkingAction.clearAwaiting`. Do **not** import / use `historyTurnEndSettleDelay`.

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && dart run tool/run_tests.dart test/cubits/ai_history_seat_turn_end_settle_test.dart`

Expected: FAIL — `final-A` still appears (or list is not `['tools-A']`) because `_scheduleTurnEndSettle` still force-reloads.

- [ ] **Step 3: Commit** (only if user requested) — optional red checkpoint; otherwise continue to Task 3.

---

### Task 3: Delete seat settle implementation

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart`
- Modify: `client/lib/services/session/history_awaiting_working_sync.dart`
- Test: `client/test/cubits/ai_history_seat_turn_end_settle_test.dart`

**Interfaces:**
- Consumes: Task 2 failing expectation
- Produces: `flushHeldTip(endAwaiting: true)` with no softReload; no `historyTurnEndSettleDelay`

- [ ] **Step 1: Remove settle from `AiHistorySeat`**

In `client/lib/cubits/ai_history_seat.dart`:

1. Delete field `Timer? _turnEndSettleTimer;`.
2. In `enqueuePendingUser`, remove the `_cancelTurnEndSettle();` call (keep `_sawWorkingWhileAwaiting = false` when latching).
3. In `flushHeldTip` `endAwaiting` branch, delete `_scheduleTurnEndSettle();` — emit and return only.
4. Delete methods `_cancelTurnEndSettle` and `_scheduleTurnEndSettle` entirely.
5. In `close()`, remove `_cancelTurnEndSettle();`.
6. Update `softReload` dartdoc: remove the sentence that turn-end settle uses `force` to pick up a last line. Keep: `force` skips mtime token cache; warm tail stays incremental.

`flushHeldTip` endAwaiting branch should look like:

```dart
    if (endAwaiting) {
      if (!hadHeld && !state.awaitingAssistant) return;
      if (state.status == AiHistoryViewStatus.ready ||
          state.status == AiHistoryViewStatus.empty) {
        _remergePendingsOntoRuntime();
      }
      _sawWorkingWhileAwaiting = false;
      emit(
        state.copyWith(
          awaitingAssistant: false,
          totalMessageCount: _committedLength,
          hasOlder: _hasOlder(),
          isLoadingOlder: false,
        ),
      );
      return;
    }
```

- [ ] **Step 2: Remove `historyTurnEndSettleDelay`**

In `client/lib/services/session/history_awaiting_working_sync.dart`, delete:

```dart
/// Delay before the second force-reload after a turn ends, so a CLI that
/// flushes transcript after PTY quiet is still picked up. Immediate settle
/// already ran; this is the late-write catch. Not used while awaiting.
const historyTurnEndSettleDelay = Duration(milliseconds: 800);
```

Grep the repo for `historyTurnEndSettleDelay` — must be zero hits after this step.

- [ ] **Step 3: Run seat + live-refresh tests — expect PASS**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/cubits/ai_history_seat_turn_end_settle_test.dart \
  test/services/session/ai_history_live_refresh_controller_test.dart
```

Expected: PASS.

- [ ] **Step 4: Rename test file (optional clarity)**

```bash
git mv client/test/cubits/ai_history_seat_turn_end_settle_test.dart \
  client/test/cubits/ai_history_seat_no_turn_end_force_reload_test.dart
```

- [ ] **Step 5: Commit** (only if user requested)

```bash
git add client/lib/cubits/ai_history_seat.dart \
  client/lib/services/session/history_awaiting_working_sync.dart \
  client/test/cubits/ai_history_seat_turn_end_settle_test.dart \
  client/test/cubits/ai_history_seat_no_turn_end_force_reload_test.dart
git commit -m "$(cat <<'EOF'
fix(history): drop turn-end force settle; live watch owns late flush

EOF
)"
```

---

### Task 4: Docs sync

**Files:**
- Modify: `docs/superpowers/specs/2026-08-19-history-turn-end-settle-design.md`
- Modify: `docs/superpowers/specs/2026-09-03-remove-history-turn-end-force-settle-design.md`
- Modify: `docs/cli-formats/cursor.md`
- Modify: `docs/superpowers/specs/2026-08-28-history-live-refresh-tail-only-design.md`

- [ ] **Step 1: Amend 2026-08-19**

At top of `2026-08-19-history-turn-end-settle-design.md`, change status and add:

```markdown
**Status:** Layer 1 approved; Layer 2 **superseded** by
[2026-09-03-remove-history-turn-end-force-settle-design](2026-09-03-remove-history-turn-end-force-settle-design.md)
```

In § Layer 2, add: `**Superseded 2026-09-03 — seat force settle removed.**`

- [ ] **Step 2: Mark 2026-09-03 Approved**

In `2026-09-03-remove-history-turn-end-force-settle-design.md`:

`**Status:** Approved`

- [ ] **Step 3: Fix cursor.md trap bullet**

Replace the “回合结束的最后一行” bullet with:

```markdown
- **回合结束的最后一行**：真实 agent-transcript 常在 PTY quiet 之后才追加最终 assistant 文本，且文件末行可能没有 `\n`。增量 tailer 在 EOF 把完整 JSON 当一行消费（半行仍推迟）；late flush 由 History live watch → `softReload(force: false)` 拾取，不再在 `flushHeldTip` 上 force settle。见 [remove-history-turn-end-force-settle-design](../superpowers/specs/2026-09-03-remove-history-turn-end-force-settle-design.md)。
```

- [ ] **Step 4: Fix 2026-08-28 tail-only doc mention**

Where it says turn-end settle tests stay green, retarget to the no-force-reload / live-watch late-flush tests.

- [ ] **Step 5: Grep cleanup**

```bash
rg -n 'historyTurnEndSettleDelay|_scheduleTurnEndSettle|turn-end settle force' \
  client docs
```

Expected: only historical mentions inside `2026-08-19` (superseded Layer 2) and the new remove-settle spec problem statement.

- [ ] **Step 6: Commit** (only if user requested)

```bash
git add docs/superpowers/specs/2026-08-19-history-turn-end-settle-design.md \
  docs/superpowers/specs/2026-09-03-remove-history-turn-end-force-settle-design.md \
  docs/cli-formats/cursor.md \
  docs/superpowers/specs/2026-08-28-history-live-refresh-tail-only-design.md
git commit -m "$(cat <<'EOF'
docs(history): supersede turn-end force settle with live-watch ownership

EOF
)"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| Delete Layer 2 settle (immediate + delayed) | Task 3 |
| Late flush via live watch + `force: false` | Task 1 |
| Keep Layer 1 EOF | untouched |
| Keep `softReload({force})` API, not from flushHeldTip | Task 3 |
| No coalesce / timer guards | Global + Task 3 |
| Rewrite/remove settle-positive tests | Task 2 |
| Update 2026-08-19 + cursor.md | Task 4 |
| Manual Cursor check | After Task 3 (manual) |

**Placeholder scan:** none.  
**Type consistency:** `flushHeldTip` / `HistoryAwaitingWorkingAction.clearAwaiting` / `AiHistoryLiveRefreshController` match current code.
