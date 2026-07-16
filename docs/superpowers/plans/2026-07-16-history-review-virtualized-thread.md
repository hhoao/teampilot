# History Review Virtualized Thread Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make history-review scrolling mount only nearby turns (+ overscan) with lean per-message chrome, matching assistant-ui’s virtualized-thread model in Flutter.

**Architecture:** Add pure turn indexing + height cache + visible-range math; replace `AiThread`’s idle `ListView.builder` with a spacer-based virtual viewport that self-owns sticky-bottom; slim ActionBar / collapsed tool·reasoning / markdown cache on mounted rows only.

**Tech Stack:** Dart / Flutter (`ai_message_ui`, `ai_message_core`, `flutter_test`); no new scroll package unless measure/anchor proves unsafe.

**Spec:** [`docs/superpowers/specs/2026-07-16-history-review-virtualized-thread-design.md`](../specs/2026-07-16-history-review-virtualized-thread-design.md)

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/packages/ai_message_ui/lib/src/thread_turns.dart` | `ThreadTurn`, `buildTurns`, content-identity helpers |
| Create: `client/packages/ai_message_ui/lib/src/turn_height_cache.dart` | Estimate / measure / invalidate / cumulative / visible range |
| Create: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` | Spacer + mounted turns + measure callbacks |
| Modify: `client/packages/ai_message_ui/lib/src/ai_thread.dart` | Idle path uses virtual viewport; keep sticky / load-older |
| Modify: `client/packages/ai_message_ui/lib/src/message_action_bar.dart` | Unload IconButtons when hidden |
| Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart` | Collapsed = trigger only |
| Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart` | Collapsed = trigger only |
| Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart` | Markdown subtree cache |
| Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart` | `RepaintBoundary`; drop `IntrinsicWidth` if needed |
| Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` | Export new public types if tests need them |
| Create: `client/packages/ai_message_ui/test/thread_turns_test.dart` | Turn grouping |
| Create: `client/packages/ai_message_ui/test/turn_height_cache_test.dart` | Range / estimate math |
| Create: `client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart` | Mount count / measure |
| Create: `client/packages/ai_message_ui/test/message_action_bar_test.dart` | Hidden has no IconButton |
| Modify: `client/packages/ai_message_ui/test/ai_thread_test.dart` | Update ListView assumptions; mount-cap test |
| Modify: existing part tests if any break | Collapsed tree expectations |

**Not in this plan:** `AiHistoryLoader`, `session_history_review.dart` host chrome, renaming `kSessionHistoryInitialTurns`, third-party virtualizer packages.

**Perf reproduce (manual):** Open a long session in history review (debug or profile), scroll and export DevTools Performance JSON; compare to local baseline `~/Downloads/test35.json` with `cd client && dart run tool/analyze_performance_json.dart <file> --format summary`. Success: worst build ≪ 527 ms; single-frame `AiMessageView` rebuilds ≈ visible+overscan, not ~39.

---

### Task 1: `buildTurns` + content identity

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/thread_turns.dart`
- Create: `client/packages/ai_message_ui/test/thread_turns_test.dart`
- Modify: `client/packages/ai_message_ui/lib/ai_message_ui.dart` (export)

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
}
```

- [ ] **Step 2: Run tests — expect FAIL (missing library)**

```bash
cd client && flutter test packages/ai_message_ui/test/thread_turns_test.dart
```

Expected: FAIL — `thread_turns.dart` not found / `buildTurns` undefined.

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

/// Returns [previous] if membership+roles+ids unchanged; else [buildTurns].
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

Export from `ai_message_ui.dart`: `export 'src/thread_turns.dart';`

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
    // viewport 0..250 → turns 0,1,2 visible; overscan 1 → 0..3
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
    // visible ~3..5, overscan → 2..6
    expect(range.firstIndex, 2);
    expect(range.lastIndex, 6);
    expect(range.paddingTop, 200); // turns 0..1
    expect(range.paddingBottom, 300); // turns 7..9
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
    final start = scrollPixels.clamp(0.0, double.infinity);
    final end = start + viewportHeight;
    var offset = 0.0;
    var first = 0;
    var last = turns.length - 1;
    var foundFirst = false;
    for (var i = 0; i < turns.length; i++) {
      final h = heightOf(turns[i].id);
      final top = offset;
      final bottom = offset + h;
      if (!foundFirst && bottom > start) {
        first = i;
        foundFirst = true;
      }
      if (top < end) last = i;
      offset = bottom;
    }
    first = (first - overscan).clamp(0, turns.length - 1);
    last = (last + overscan).clamp(0, turns.length - 1);

    var paddingTop = 0.0;
    for (var i = 0; i < first; i++) {
      paddingTop += heightOf(turns[i].id);
    }
    var paddingBottom = 0.0;
    for (var i = last + 1; i < turns.length; i++) {
      paddingBottom += heightOf(turns[i].id);
    }
    return TurnVisibleRange(
      firstIndex: first,
      lastIndex: last,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui/test/turn_height_cache_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/turn_height_cache.dart \
  client/packages/ai_message_ui/test/turn_height_cache_test.dart
git commit -m "feat(ai_message_ui): add turn height cache and visible range"
```

---

### Task 3: Lean ActionBar (unload when hidden)

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/message_action_bar.dart`
- Create: `client/packages/ai_message_ui/test/message_action_bar_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = AiMessage(
    id: '1',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'hello')],
  );

  testWidgets('hidden hover ActionBar has no IconButton', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.hover,
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('always reveal builds IconButtons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            reveal: AiActionBarReveal.always,
          ),
        ),
      ),
    );
    expect(find.byType(IconButton), findsWidgets);
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (today still builds IconButtons under `opacity: 0`)

```bash
cd client && flutter test packages/ai_message_ui/test/message_action_bar_test.dart
```

- [ ] **Step 3: Implement unload + fixed-height placeholder**

In `message_action_bar.dart`, when `!visible`, return a `SizedBox` with the same height as the button row (e.g. `40`) wrapped in `SelectionContainer.disabled` + `MouseRegion` so hover still works — **without** building `IconButton`s / `AnimatedOpacity` children. When `visible`, build the current Row of buttons (animation optional).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/message_action_bar.dart \
  client/packages/ai_message_ui/test/message_action_bar_test.dart
git commit -m "perf(ai_message_ui): unload ActionBar IconButtons when hidden"
```

---

### Task 4: Lean collapsed tool + reasoning

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`
- Modify: `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart`
- Create or extend: `client/packages/ai_message_ui/test/collapsed_parts_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
testWidgets('collapsed tool has no AnimatedSize body', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiToolCallPartView(
        part: AiToolCallPart(
          toolCallId: '1',
          toolName: 'Bash',
          status: AiToolCallStatus.complete,
          argsText: '{"x":1}',
        ),
      ),
    ),
  );
  expect(find.byType(AnimatedSize), findsNothing);
  expect(find.textContaining('{'), findsNothing);
});

testWidgets('collapsed reasoning has no markdown body', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AiReasoningPartView(
        part: const AiReasoningPart(text: 'secret thoughts'),
      ),
    ),
  );
  expect(find.byType(AnimatedSize), findsNothing);
  expect(find.text('secret thoughts'), findsNothing);
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- Collapsed: render trigger `InkWell`/`MouseRegion` only; use static `Icon(expand_more)` rotated via `Transform.rotate` **without** `AnimatedRotation` when closed, or plain icon.
- Drop wrapping `AnimatedSize` when `!_open` (use `if (_open) ...` only).
- Keep `AnimatedSize` / `AnimatedRotation` only on the expanded path if desired; simplest is: no animation widgets when collapsed, optional short animation when opening.

- [ ] **Step 4: Run — expect PASS** (+ existing part tests)

```bash
cd client && flutter test packages/ai_message_ui/test/collapsed_parts_test.dart \
  packages/ai_message_ui/test/ai_message_parts_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart \
  client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart \
  client/packages/ai_message_ui/test/collapsed_parts_test.dart
git commit -m "perf(ai_message_ui): lean collapsed tool and reasoning trees"
```

---

### Task 5: Markdown parse / subtree cache

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/text_part_view.dart`
- Create: `client/packages/ai_message_ui/test/markdown_cache_test.dart` (or extend `streaming_markdown_test.dart`)

- [ ] **Step 1: Write failing test for cache hit identity**

Prefer a small pure helper:

```dart
// In text_part_view.dart (or markdown_body_cache.dart)
class MarkdownBodyCache {
  MarkdownBodyCache({this.maxEntries = 64});
  final int maxEntries;
  final _map = <String, Widget>{};

  Widget getOrCreate(String key, Widget Function() build) {
    final hit = _map[key];
    if (hit != null) return hit;
    final w = build();
    if (_map.length >= maxEntries) _map.remove(_map.keys.first);
    _map[key] = w;
    return w;
  }

  @visibleForTesting
  int get debugLength => _map.length;
}
```

Test: two builds with same `(preparedText, styleGen)` key → `debugLength == 1`; different text → `2`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Wire `AiTextPartView` through cache**

Key = `'${prepareStreamingMarkdown(text)}|${sheet.hashCode}'` (or style sheet generation id from theme). Store the **built `MarkdownBody` widget** (immutable inputs). Clear is LRU via insert order.

Note: `MarkdownBody` must not capture a stale `BuildContext` beyond what Flutter already does for StatelessWidgets — cache at the widget instance level returned from `build` is OK if style sheet is recomputed into the key.

- [ ] **Step 4: Run — expect PASS**

```bash
cd client && flutter test packages/ai_message_ui/test/streaming_markdown_test.dart \
  packages/ai_message_ui/test/markdown_cache_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/text_part_view.dart \
  client/packages/ai_message_ui/test/markdown_cache_test.dart
git commit -m "perf(ai_message_ui): cache MarkdownBody by content key"
```

---

### Task 6: `VirtualThreadViewport` widget

**Files:**
- Create: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart`
- Create: `client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart`

- [ ] **Step 1: Write failing mount-cap test**

Use a tiny fake turn child that increments a static counter in `initState`:

```dart
testWidgets('mounts only overscan window not all turns', (tester) async {
  _Probe.mountedIds.clear();
  final turns = List.generate(
    40,
    (i) => ThreadTurn(id: 't$i', messageIds: ['t$i']),
  );
  final cache = TurnHeightCache(estimate: 80);
  final controller = ScrollController();

  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        height: 240,
        child: VirtualThreadViewport(
          turns: turns,
          heightCache: cache,
          scrollController: controller,
          overscan: 2,
          turnBuilder: (context, turn) => _Probe(id: turn.id),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Jump near bottom so sticky hosts can start there later; for this unit
  // test start at 0 and assert mount count << 40.
  expect(_Probe.mountedIds.length, lessThan(15));
  expect(_Probe.mountedIds.length, greaterThan(0));
});
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement viewport**

Lock production overscan in this file (tests may pass a smaller value):

```dart
/// Spec default: 3 turns above and below the viewport.
const int kThreadOverscan = 3;
```

Structure:

```dart
class VirtualThreadViewport extends StatefulWidget {
  // turns, heightCache, scrollController,
  // overscan (default kThreadOverscan),
  // padding (default EdgeInsets.fromLTRB(0, 16, 0, 24) — match old AiThread),
  // headerBuilder?, turnBuilder, stickIntent, onScrollMetrics?
}
```

Build tree:

```dart
NotificationListener<ScrollNotification>(
  onNotification: (_) {
    _recomputeRange(); // setState when first/last/paddings change
    return false;
  },
  child: ListView(
    controller: scrollController,
    padding: padding,
    // IMPORTANT: spacer children — NOT itemBuilder for all turns
    children: [
      if (header != null) header,
      SizedBox(height: range.paddingTop),
      for (i in first..last)
        _MeasuredTurn(
          key: ValueKey(turns[i].id),
          onHeight: (h) => heightCache.setMeasured(turns[i].id, h),
          child: turnBuilder(context, turns[i]),
        ),
      SizedBox(height: range.paddingBottom),
    ],
  ),
)
```

Also listen to `scrollController` (in addition to notifications) so programmatic `jumpTo` recomputes the window. Recompute `range` after measure (`setState`). While parent reports stick-intent, skip scroll corrections from measure that would move away from bottom (`stickIntent` / `suppressMeasureScroll`).

`_MeasuredTurn`: `NotificationListener<SizeChangedLayoutNotification>` or post-frame `context.size!.height`.

**Do not** use `ListView.builder` with one item per turn — that reintroduces the old model. One scrollable with spacers + mounted subset.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart \
  client/packages/ai_message_ui/test/virtual_thread_viewport_test.dart
git commit -m "feat(ai_message_ui): add spacer-based virtual thread viewport"
```

---

### Task 7: Wire `AiThread` + `RepaintBoundary` + sticky guard

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_thread.dart`
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart`
- Modify: `client/packages/ai_message_ui/test/ai_thread_test.dart`
- Modify: `client/packages/ai_message_ui/test/selection_area_test.dart` if needed

- [ ] **Step 1: Add failing mount-cap + load-older anchor tests on `AiThread`**

```dart
testWidgets('AiThread idle mounts far fewer messages than window', (tester) async {
  final store = ExternalStoreAiThreadRuntime();
  // 40 user messages = 40 turns of ~3 lines each
  store.setMessages(List.generate(
    40,
    (i) => AiMessage(
      id: 'm$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'line $i\n' * 3)],
    ),
  ));
  await tester.pumpWidget(/* AiThread in 400px height */);
  await tester.pumpAndSettle();
  expect(find.byType(AiMessageView), findsWidgets);
  expect(find.byType(AiMessageView).evaluate().length, lessThan(20));
});

testWidgets('AiThread load-older prepend preserves scroll anchor', (tester) async {
  final store = ExternalStoreAiThreadRuntime();
  final newer = List.generate(
    20,
    (i) => AiMessage(
      id: 'n$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'newer $i\n' * 4)],
    ),
  );
  store.setMessages(newer);
  final scrollController = ScrollController();
  var hasOlder = true;

  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) {
          return SizedBox(
            height: 400,
            child: AiThread(
              runtime: store,
              scrollController: scrollController,
              hasOlder: hasOlder,
              isLoadingOlder: false,
              onLoadOlder: () {
                final older = List.generate(
                  10,
                  (i) => AiMessage(
                    id: 'o$i',
                    role: AiRole.user,
                    parts: [AiTextPart(text: 'older $i\n' * 4)],
                  ),
                );
                setState(() {
                  hasOlder = false;
                  store.setMessages([...older, ...newer]);
                });
              },
              loadOlderHeaderBuilder: (context, {required isLoadingOlder}) {
                return const SizedBox(height: 24, child: Text('OLDER'));
              },
              loadingBuilder: (_) => const Text('LOADING'),
              emptyBuilder: (_) => const Text('EMPTY'),
              errorBuilder: (_, msg, retry) => Text('ERR:$msg'),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Park near top (triggers load-older) but not necessarily 0 — AiThread
  // snapshots pixels/extent immediately before onLoadOlder.
  const park = 40.0;
  scrollController.jumpTo(park);
  await tester.pump();
  final beforeExtent = scrollController.position.maxScrollExtent;
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pumpAndSettle();

  final afterExtent = scrollController.position.maxScrollExtent;
  expect(afterExtent, greaterThan(beforeExtent));
  final delta = afterExtent - beforeExtent;
  // Content that was under [park] stays under the viewport after top prepend.
  expect(scrollController.offset, closeTo(park + delta, 5.0));
});
```

- [ ] **Step 2: Run — expect FAIL** (mount-cap must fail on current ListView; anchor may already pass — keep both as regression net after virtualization)
- [ ] **Step 3: Replace idle `ListView.builder` with `VirtualThreadViewport`**

In `_AiThreadState`:

1. Keep sticky / load-older / opacity reveal logic (`_restoreScrollAfterOlderLoad` must still run after prepend).
2. On message sync: `turns = reuseTurnsIfSameMembership(...)`; for each turn whose `turnContentIdentity` changed vs previous snapshot, `heightCache.invalidate(turn.id)`.
3. Build message map `id → AiMessage`.
4. `turnBuilder`: for each `messageId`, resolve message; skip null; wrap:

```dart
RepaintBoundary(
  child: Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: aiTheme.threadHorizontalPadding),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: aiTheme.threadMaxWidth),
        child: _buildMessage(
          context,
          message,
          isLast: message.id == _messages.last.id,
        ),
      ),
    ),
  ),
)
```

5. Pass `stickIntent: _stickIntent`, `overscan: kThreadOverscan`, and the same list padding `EdgeInsets.fromLTRB(0, 16, 0, 24)` into viewport so measure updates call `_stickToBottomIfNeeded` instead of fighting scroll.
6. Header: existing load-older header when `hasOlder`.
7. In `ai_message_view.dart`: wrap role switch output in `RepaintBoundary`; remove user-bubble `IntrinsicWidth` (keep max-width `ConstrainedBox` + Align end) so measured heights stay stable.

- [ ] **Step 4: Run full package tests**

```bash
cd client && flutter test packages/ai_message_ui
```

Expected: PASS including mount-cap and load-older anchor. Fix any test that counted all `ListView` children or assumed full mount.

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/ai_thread.dart \
  client/packages/ai_message_ui/lib/src/ai_message_view.dart \
  client/packages/ai_message_ui/test/ai_thread_test.dart \
  client/packages/ai_message_ui/test/selection_area_test.dart
git commit -m "feat(ai_message_ui): virtualize AiThread idle path by turn"
```

---

### Task 8: Analyzer + manual perf note

**Files:** none required (verification)

- [ ] **Step 1: Analyze package**

```bash
cd client && dart analyze packages/ai_message_ui --fatal-infos
```

Expected: no issues.

- [ ] **Step 2: Manual perf (optional in CI)**

1. Run app (prefer profile).
2. Open the same long session history review used for `test35.json`.
3. Scroll up/down; export DevTools Performance JSON.
4. `dart run tool/analyze_performance_json.dart ~/Downloads/<new>.json --format summary`
5. Confirm worst build frame and `AiMessageView` rebuild counts dropped vs baseline.

- [ ] **Step 3: Commit only if docs/notes added; else skip**

If adding a short note under the plan’s Perf reproduce section with the new filename, commit docs only.

---

## Execution notes

- Prefer TDD order as written; do not skip mount-cap tests — they are the architectural guardrail.
- Sticky-bottom bugs are easy with spacers: always test open → at bottom, scroll up → button, load-older → anchor.
- Keep `messageBuilder` path in `_buildMessage`.
- Do not reinterpret `kSessionHistoryInitialTurns` as turn count in this plan.
