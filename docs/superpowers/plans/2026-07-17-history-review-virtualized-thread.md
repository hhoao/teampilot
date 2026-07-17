# History Review Turn Virtualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `SessionHistoryThread`'s eager `Column` with a spacer-based turn virtual viewport so history review mounts only nearby turns (+ overscan) without mid-scroll extent jumps.

**Architecture:** Pure `buildTurns` + `TurnHeightCache` in `ai_message_ui`; `VirtualThreadViewport` mounts a window of turns between top/bottom spacers sized from cached/estimated heights. `SessionHistoryThread` keeps scroll ownership (stick, load-older, hover gate, SelectionArea, thread chrome) and embeds the viewport. Phase 2 slims collapsed tool/reasoning trees on mounted rows.

**Tech Stack:** Dart / Flutter (`ai_message_ui`, `ai_message_core`, `flutter_test`); no third-party scroll package.

**Spec:** [`docs/superpowers/specs/2026-07-17-history-review-virtualized-thread-design.md`](../specs/2026-07-17-history-review-virtualized-thread-design.md)

**Supersedes plan:** [`2026-07-16-history-review-virtualized-thread.md`](2026-07-16-history-review-virtualized-thread.md) (that plan targeted `AiThread`; this one targets the current host).

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/packages/ai_message_ui/lib/src/thread_turns.dart` | `ThreadTurn`, `buildTurns`, content-identity helpers |
| Create: `client/packages/ai_message_ui/lib/src/turn_height_cache.dart` | Estimate / measure / invalidate / cumulative / visible range |
| Create: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` | Spacers + mounted turns + measure callbacks |
| Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export new types |
| Modify: `client/lib/pages/chat/session_history_thread.dart` | Replace Column body with `VirtualThreadViewport`; keep stick/load-older/hover/SelectionArea/chrome |
| Create: `client/packages/ai_message_ui/test/thread_turns_test.dart` | Turn grouping + identity |
| Create: `client/packages/ai_message_ui/test/turn_height_cache_test.dart` | Range / estimate math |
| Create: `client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart` | Mount cap + measure |
| Create: `client/test/pages/chat/session_history_thread_test.dart` | Host: SelectionArea, stick, load-older anchor smoke |
| Modify (Phase 2): `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Collapsed = trigger only |
| Modify (Phase 2): `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Collapsed = trigger only |
| Modify (Phase 2): `client/packages/ai_message_ui/lib/src/parts/tool_group_view.dart` | Same lean collapse if it builds expanded body when closed |

**Not in this plan:** `AiHistoryLoader`, renaming `kSessionHistoryInitialTurns`, wiring `AiThread` to the viewport (optional later), third-party virtualizers.

**ActionBar note:** `message_action_bar.dart` already defers icon mount until hover and avoids Material `IconButton`. Phase 2 does **not** rework ActionBar unless profiling still shows chrome cost after virtualization.

**Perf reproduce (manual):** Profile build → open long history session → scroll + load older → export DevTools JSON → `cd client && dart run tool/analyze_performance_json.dart <file> --format summary`. Compare to Column baseline `~/Downloads/Chrome/dart_devtools_2026-07-17_15_11_00.868.json` (worst ~143 ms build) and Flyer `test35.json` (~527 ms). Success: mount count ≈ viewport+overscan; worst build ≪ Column on comparable session; no mid-scroll extent jumps.

---

## Phase 1 — Virtualization

### Task 1: `buildTurns` + content identity

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/thread_turns.dart`
- Create: `client/packages/ai_message_ui/test/thread_turns_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/src/thread_turns.dart';
import 'package:flutter_test/flutter_test.dart';

AiMessage user(String id, String t) => AiMessage(
  id: id,
  role: AiRole.user,
  parts: [AiTextPart(text: t)],
);
AiMessage asst(String id, String t) => AiMessage(
  id: id,
  role: AiRole.assistant,
  parts: [AiTextPart(text: t)],
);

void main() {
  test('buildTurns groups trailing assistants under user', () {
    final turns = buildTurns([
      user('u1', 'hi'),
      asst('a1', 'yo'),
      asst('a2', 'more'),
      user('u2', 'next'),
      asst('a3', 'ok'),
    ]);
    expect(turns.map((t) => t.id), ['u1', 'u2']);
    expect(turns[0].messageIds, ['u1', 'a1', 'a2']);
    expect(turns[1].messageIds, ['u2', 'a3']);
  });

  test('buildTurns starts orphan assistant as its own turn', () {
    final turns = buildTurns([asst('a0', 'lonely')]);
    expect(turns.single.id, 'a0');
    expect(turns.single.messageIds, ['a0']);
  });

  test('messageContentIdentity changes when text changes', () {
    final a = user('u1', 'hi');
    final b = user('u1', 'hi!');
    expect(messageContentIdentity(a), isNot(messageContentIdentity(b)));
  });

  test('turnContentIdentity stable when ids+parts unchanged', () {
    final msgs = [user('u1', 'hi'), asst('a1', 'yo')];
    final t = buildTurns(msgs).single;
    expect(turnContentIdentity(t, msgs), turnContentIdentity(t, msgs));
  });

  test('reuseTurnsIfSameMembership returns previous when ids unchanged', () {
    final msgs = [user('u1', 'hi'), asst('a1', 'yo')];
    final first = buildTurns(msgs);
    final reused = reuseTurnsIfSameMembership(
      previous: first,
      messages: [user('u1', 'CHANGED'), asst('a1', 'yo')],
    );
    expect(identical(reused, first), isTrue);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test packages/ai_message_ui/test/thread_turns_test.dart
```

Expected: FAIL — missing `thread_turns.dart` / undefined symbols.

- [ ] **Step 3: Implement**

```dart
// client/packages/ai_message_ui/lib/src/thread_turns.dart
import 'package:ai_message_core/ai_message_core.dart';

class ThreadTurn {
  const ThreadTurn({required this.id, required this.messageIds});
  final String id;
  final List<String> messageIds;
}

List<ThreadTurn> buildTurns(List<AiMessage> messages) {
  if (messages.isEmpty) return const [];
  final turns = <ThreadTurn>[];
  for (final m in messages) {
    if (m.role == AiRole.user || turns.isEmpty) {
      turns.add(ThreadTurn(id: m.id, messageIds: [m.id]));
    } else {
      final last = turns.removeLast();
      turns.add(
        ThreadTurn(id: last.id, messageIds: [...last.messageIds, m.id]),
      );
    }
  }
  return turns;
}

String messageContentIdentity(AiMessage m) {
  final buf = StringBuffer('${m.id}|${m.role.name}|${m.status.name}');
  for (final p in m.parts) {
    buf.write('|');
    switch (p) {
      case AiTextPart(:final text):
        buf.write('t:$text');
      case AiReasoningPart(:final text):
        buf.write('r:$text');
      case AiToolCallPart(
        :final toolCallId,
        :final toolName,
        :final argsText,
        :final status,
        :final isError,
        :final result,
      ):
        buf.write(
          'c:$toolCallId:$toolName:${argsText ?? ''}:'
          '${status.name}:$isError:${result ?? ''}',
        );
    }
  }
  return buf.toString();
}

String turnContentIdentity(ThreadTurn turn, List<AiMessage> messages) {
  final byId = {for (final m in messages) m.id: m};
  final buf = StringBuffer(turn.id);
  for (final id in turn.messageIds) {
    final m = byId[id];
    buf.write('|');
    buf.write(m == null ? 'missing:$id' : messageContentIdentity(m));
  }
  return buf.toString();
}

List<ThreadTurn> reuseTurnsIfSameMembership({
  required List<ThreadTurn> previous,
  required List<AiMessage> messages,
}) {
  final next = buildTurns(messages);
  if (previous.length != next.length) return next;
  for (var i = 0; i < next.length; i++) {
    if (previous[i].id != next[i].id) return next;
    final a = previous[i].messageIds;
    final b = next[i].messageIds;
    if (a.length != b.length) return next;
    for (var j = 0; j < a.length; j++) {
      if (a[j] != b[j]) return next;
    }
  }
  return previous;
}
```

Add `export 'src/thread_turns.dart';` to `ai_message_ui.dart`.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui/test/thread_turns_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/thread_turns.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart \
  client/packages/ai_message_ui/test/thread_turns_test.dart
git commit -m "feat(ai_message_ui): add thread turn indexing helpers"
```

---

### Task 2: Height cache + visible range

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/turn_height_cache.dart`
- Create: `client/packages/ai_message_ui/test/turn_height_cache_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export)

- [ ] **Step 1: Write failing tests**

```dart
import 'package:ai_message_ui/src/thread_turns.dart';
import 'package:ai_message_ui/src/turn_height_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimate used until measured', () {
    final cache = TurnHeightCache(estimate: 200);
    final turns = [
      const ThreadTurn(id: 'a', messageIds: ['a']),
      const ThreadTurn(id: 'b', messageIds: ['b']),
    ];
    expect(cache.heightOf('a'), 200);
    cache.setMeasured('a', 120);
    expect(cache.heightOf('a'), 120);
    expect(cache.totalExtent(turns), 320);
  });

  test('visibleRange covers pixels with overscan', () {
    final cache = TurnHeightCache(estimate: 100);
    final turns = List.generate(
      10,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final range = cache.visibleRange(
      turns: turns,
      scrollPixels: 0,
      viewportHeight: 250,
      overscan: 1,
    );
    expect(range.firstIndex, 0);
    expect(range.lastIndex, 3);
    expect(range.paddingTop, 0);
  });

  test('visibleRange mid-list pads top/bottom', () {
    final cache = TurnHeightCache(estimate: 100);
    for (var i = 0; i < 10; i++) {
      cache.setMeasured('t$i', 100);
    }
    final turns = List.generate(
      10,
      (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
    );
    final range = cache.visibleRange(
      turns: turns,
      scrollPixels: 350,
      viewportHeight: 200,
      overscan: 1,
    );
    expect(range.firstIndex, 2);
    expect(range.lastIndex, 6);
    expect(range.paddingTop, 200);
    expect(range.paddingBottom, 300);
  });

  test('invalidate drops measured height', () {
    final cache = TurnHeightCache(estimate: 200);
    cache.setMeasured('a', 50);
    cache.invalidate('a');
    expect(cache.heightOf('a'), 200);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test packages/ai_message_ui/test/turn_height_cache_test.dart
```

- [ ] **Step 3: Implement**

```dart
// client/packages/ai_message_ui/lib/src/turn_height_cache.dart
import 'thread_turns.dart';

class TurnVisibleRange {
  const TurnVisibleRange({
    required this.firstIndex,
    required this.lastIndex,
    required this.paddingTop,
    required this.paddingBottom,
  });
  final int firstIndex;
  final int lastIndex;
  final double paddingTop;
  final double paddingBottom;
}

class TurnHeightCache {
  TurnHeightCache({this.estimate = 200});

  final double estimate;
  final Map<String, double> _measured = {};

  double heightOf(String turnId) => _measured[turnId] ?? estimate;

  void setMeasured(String turnId, double height) {
    if (height <= 0) return;
    _measured[turnId] = height;
  }

  void invalidate(String turnId) => _measured.remove(turnId);

  void invalidateAll() => _measured.clear();

  double totalExtent(List<ThreadTurn> turns) {
    var sum = 0.0;
    for (final t in turns) {
      sum += heightOf(t.id);
    }
    return sum;
  }

  /// Cumulative height of turns[0..index) (exclusive end).
  double offsetBefore(List<ThreadTurn> turns, int index) {
    var sum = 0.0;
    final end = index.clamp(0, turns.length);
    for (var i = 0; i < end; i++) {
      sum += heightOf(turns[i].id);
    }
    return sum;
  }

  TurnVisibleRange visibleRange({
    required List<ThreadTurn> turns,
    required double scrollPixels,
    required double viewportHeight,
    required int overscan,
  }) {
    if (turns.isEmpty) {
      return const TurnVisibleRange(
        firstIndex: 0,
        lastIndex: -1,
        paddingTop: 0,
        paddingBottom: 0,
      );
    }
    final top = scrollPixels < 0 ? 0.0 : scrollPixels;
    final bottom = top + viewportHeight;
    var acc = 0.0;
    var first = 0;
    var last = turns.length - 1;
    var foundFirst = false;
    for (var i = 0; i < turns.length; i++) {
      final h = heightOf(turns[i].id);
      final turnBottom = acc + h;
      if (!foundFirst && turnBottom > top) {
        first = i;
        foundFirst = true;
      }
      if (acc < bottom) {
        last = i;
      }
      acc = turnBottom;
    }
    first = (first - overscan).clamp(0, turns.length - 1);
    last = (last + overscan).clamp(0, turns.length - 1);
    if (last < first) last = first;
    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: offsetBefore(turns, first),
      paddingBottom: totalExtent(turns) - offsetBefore(turns, last + 1),
    );
  }
}
```

Export from `ai_message_ui.dart`.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui/test/turn_height_cache_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/turn_height_cache.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart \
  client/packages/ai_message_ui/test/turn_height_cache_test.dart
git commit -m "feat(ai_message_ui): add turn height cache and visible range"
```

---

### Task 3: `VirtualThreadViewport` widget

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart`
- Create: `client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart`

**API sketch (lock this shape):**

```dart
class VirtualThreadViewport extends StatefulWidget {
  const VirtualThreadViewport({
    required this.messages,
    required this.scrollController,
    required this.messageBuilder,
    this.header,
    this.overscan = 3,
    this.estimateHeight = 200,
    /// When true, measurement must not request scroll corrections upward.
    this.suppressMeasureScrollCorrection = false,
    this.onMeasureScrollCorrection,
    super.key,
  });

  final List<AiMessage> messages;
  final ScrollController scrollController;
  final Widget Function(BuildContext context, AiMessage message) messageBuilder;
  final Widget? header;
  final int overscan;
  final double estimateHeight;
  final bool suppressMeasureScrollCorrection;
  /// Optional: host applies pixel delta after height cache changes (load-older
  /// / expand). Must be called post-frame — never from a scroll listener body
  /// that re-enters via jumpTo.
  final void Function(double deltaPixels)? onMeasureScrollCorrection;
}
```

Viewport builds a **Column** inside the host's existing `SingleChildScrollView` (host owns the scroll view) **or** owns an internal `ListView`/`CustomScrollView` with one child column of spacers+turns. Prefer: **viewport is the scrollable's child only** (Column of header + top spacer + turns + bottom spacer) so `SessionHistoryThread` keeps its `ScrollController` + notifications. Recalculate visible range on scroll notifications / controller listener via `setState` of mount window only — **do not** `jumpTo` inside the listener.

- [ ] **Step 1: Write failing widget test**

Use fixed-height `messageBuilder` (`SizedBox(height: 100, child: Text(message.id))`) so estimates match reality.

```dart
testWidgets('mounts at most viewport+overscan turns', (tester) async {
  final controller = ScrollController();
  final messages = List.generate(
    40,
    (i) => AiMessage(
      id: 'm$i',
      role: i.isEven ? AiRole.user : AiRole.assistant,
      parts: [AiTextPart(text: 't$i')],
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        height: 400,
        child: SingleChildScrollView(
          controller: controller,
          child: VirtualThreadViewport(
            messages: messages,
            scrollController: controller,
            overscan: 2,
            estimateHeight: 100,
            messageBuilder: (_, m) => SizedBox(
              height: 100,
              width: double.infinity,
              child: Text(m.id, key: ValueKey('msg-${m.id}')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // 40 messages → ~20 turns if paired; with height 100 and viewport 400
  // visible turns ~4 + overscan 2*2 → mount cap well under 20.
  final mounted = find.byWidgetPredicate(
    (w) => w is Text && (w.key as ValueKey<String>?)?.value.startsWith('msg-') == true,
  );
  expect(mounted.evaluate().length, lessThan(messages.length));
  expect(mounted.evaluate().length, lessThanOrEqualTo(20)); // generous cap
});
```

Also test: after `controller.jumpTo(mid)`, different message ids appear; measuring updates cache (optional assert via public `debugMountCount` if needed — prefer finders only).

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test packages/ai_message_ui/test/virtual_thread_viewport_test.dart
```

- [ ] **Step 3: Implement viewport**

Implementation notes:

1. Maintain `_turns`, `_cache`, `_identityByTurnId`.
2. On `messages` change: `reuseTurnsIfSameMembership`; for each turn, if `turnContentIdentity` changed → `cache.invalidate(turn.id)` and update stored identity.
3. Listen to `scrollController` (and/or wrap with `NotificationListener` in host — viewport can addListener in `initState`) to `setState` when visible range indices change.
4. Build: `[header?]`, `SizedBox(height: paddingTop)`, mounted turn columns, `SizedBox(height: paddingBottom)`.
5. Each mounted turn: `Key(ValueKey(turn.id))`, then a `Column` of `messageBuilder(context, message)` for each id in `turn.messageIds` (lookup message by id from `messages`; skip missing).
6. Visible range: use `scrollController.position.pixels` and `scrollController.position.viewportDimension` once `hasClients`; until then mount a small prefix (e.g. first `overscan*2+1` turns) so first layout can measure.
7. Each turn: `NotificationListener<SizeChangedLayoutNotification>` or post-frame measure → `cache.setMeasured`; if height delta ≠ 0 and turn starts above viewport, compute scroll correction delta for turns fully above `scrollPixels` — call `onMeasureScrollCorrection` **post-frame** only when `!suppressMeasureScrollCorrection`.
8. While `suppressMeasureScrollCorrection` (stick active): still update cache; skip correction (host will `jumpTo(max)`).

Keep file under ~300 lines; extract `_MeasuredTurn` private widget if needed.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui/test/virtual_thread_viewport_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart \
  client/packages/ai_message_ui/lib/ai_message_ui.dart \
  client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart
git commit -m "feat(ai_message_ui): add VirtualThreadViewport with height spacers"
```

---

### Task 4: Wire `SessionHistoryThread`

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`
- Create: `client/test/pages/chat/session_history_thread_test.dart`

- [ ] **Step 1: Write failing host tests**

Minimal pump with fake runtime (or a tiny in-test `AiThreadRuntime` stub). Cover:

1. `SelectionArea` is present.
2. With 30+ messages of fixed-height builders is hard without injecting builder — instead test via public behavior:
   - On pump, scroll controller attached.
   - Call `onLoadOlder` when scrolled near top (may need `tester.drag` with enough messages).

If injecting `messageBuilder` is awkward, keep host test smoke-level:

```dart
testWidgets('SessionHistoryThread builds SelectionArea and scrollable', (tester) async {
  // Use ExternalStoreAiThreadRuntime with 5 short messages + AiMessageTheme
  // Expect find.byType(SelectionArea), find.byType(Scrollable)
});
```

Add load-older: stub `onLoadOlder` increments a counter when dragged to top after pumping enough estimated extent.

- [ ] **Step 2: Run — expect FAIL or partial fail until wired**

```bash
cd client && flutter test test/pages/chat/session_history_thread_test.dart
```

- [ ] **Step 3: Replace Column body with VirtualThreadViewport**

Keep:

- `ScrollController`, stick frames, `_loadOlderAnchored`, hover `ValueNotifier`, `NotificationListener`, `SelectionArea`.
- Thread chrome: pass a `messageBuilder` that wraps `AiMessageView` with current `Align` / padding / `ConstrainedBox(maxWidth: threadMaxWidth)`.

Change `build` child of `SingleChildScrollView` from `Column(children: [...all messages])` to:

```dart
VirtualThreadViewport(
  messages: _messages,
  scrollController: _scrollController,
  header: /* existing hasOlder spinner widget or null */,
  suppressMeasureScrollCorrection: _stickToEnd,
  onMeasureScrollCorrection: (delta) {
    if (!_scrollController.hasClients || delta.abs() < 0.5) return;
    final next = (_scrollController.position.pixels + delta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    // Post-frame already guaranteed by viewport — jumpTo here is OK
    // if not inside scroll listener. Prefer scheduling if unsure.
    _jumpTo(next);
  },
  messageBuilder: (context, ai) { /* existing AiMessageView chrome */ },
)
```

Invalidate stick: when `_stickToEnd`, pass `suppressMeasureScrollCorrection: true` and keep existing `_scheduleStickFrames`.

Thread chrome in `messageBuilder`: keep `Align` / padding / `ConstrainedBox(maxWidth: threadMaxWidth)`, and:

```dart
actionBarReveal: ai.id == lastId
    ? AiActionBarReveal.always
    : AiActionBarReveal.hover,
actionBarHoverEnabled: _actionBarHoverEnabled,
```

Do **not** reintroduce probe logging.

- [ ] **Step 4: Run host + package tests**

```bash
cd client && flutter test packages/ai_message_ui/test/thread_turns_test.dart \
  packages/ai_message_ui/test/turn_height_cache_test.dart \
  packages/ai_message_ui/test/virtual_thread_viewport_test.dart \
  test/pages/chat/session_history_thread_test.dart
```

- [ ] **Step 5: Manual smoke (if Linux available)**

`flutter run -d linux --profile` → open long history → scroll up/down → load older → confirm no jump; check DevTools mount count optionally.

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/chat/session_history_thread.dart \
  client/test/pages/chat/session_history_thread_test.dart
git commit -m "feat(history): use VirtualThreadViewport in SessionHistoryThread"
```

---

### Task 5: Phase 1 verification gate

- [ ] **Step 1: Analyzer**

```bash
cd client && dart analyze packages/ai_message_ui lib/pages/chat/session_history_thread.dart \
  --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Full package UI tests**

```bash
cd client && flutter test packages/ai_message_ui
```

- [ ] **Step 3: Profile export comparison (manual checklist)**

- [ ] Mid-scroll: no large unexplained `maxScrollExtent` swings
- [ ] Open long session: worst build frame ≪ 143 ms Column baseline (same machine/session class)
- [ ] Stick-to-end on open still works
- [ ] Load-older preserves reading position
- [ ] Hover ActionBar still suppressed while scrolling

- [ ] **Step 4: Commit docs note if baselines recorded** (optional path under `docs/superpowers/` only if user asks)

Stop Phase 1 here if Phase 2 is a separate PR; otherwise continue.

---

## Phase 2 — Lean chrome (mounted rows)

### Task 6: Collapsed tool / reasoning lean trees

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_group_view.dart` (if closed still builds body)
- Update/create tests under `client/packages/ai_message_ui/test/`

- [ ] **Step 1: Write failing tests**

Assert collapsed tool view has no args/result panel widgets (finder by type or key). Same for reasoning body when closed.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

When `_open == false`: build trigger row only; no `AnimatedSize` wrapping an offstage body. When `_open == true`: allow animation.

- [ ] **Step 4: Run package tests — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui
```

- [ ] **Step 5: Commit**

```bash
git commit -m "perf(ai_message_ui): lean collapsed tool and reasoning trees"
```

---

### Task 7: Final verification

- [ ] **Step 1:** `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- [ ] **Step 2:** `cd client && flutter test packages/ai_message_ui test/pages/chat/session_history_thread_test.dart`
- [ ] **Step 3:** Manual profile export after Phase 2; confirm ActionBar already lean (no extra work unless needed)
- [ ] **Step 4:** Mark success criteria from spec checked in PR description

---

## Risk notes for implementers

1. **Never** `jumpTo` from inside a scroll listener that synchronously re-fires (prior freeze). Corrections = post-frame / host callback after measure.
2. Do **not** use `ListView.builder` for one item per turn without spacers — falsified by ablation.
3. Host owns thread chrome width; viewport only decides which turns exist in the tree.
4. `kSessionHistoryInitialTurns` is message count; overscan is turn count — do not conflate.
