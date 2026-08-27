# User-message rail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible left-edge user-message tick rail on session chat that previews on hover and jumps to that bubble via a shared, wait-for-id locator.

**Architecture:** Pure `buildChatOutline` indexes user turns from `AiHistorySeat.loadedMessages`. `ChatMessageLocator` expands the render window, waits until the id is in `runtime.messages`, then `ChatRevealController.reveal`s (find uses the same locator). `VirtualThreadViewport` reports the **viewport-visible** turn range (overscan 0, before `retainMountedTurns`). `SessionHistoryThread` writes the owning user-turn id to a `ValueNotifier`. `ChatOutlineRail` is one `CustomPaint` plus one overlay card.

**Tech Stack:** Flutter/Dart, `ai_message_core`, `ai_message_ui` (`VirtualThreadViewport`, `TurnVisibleRange`, `buildTurns`), `ChatRevealController`, `flutter_test`, ARB l10n.

**Spec:** `docs/superpowers/specs/2026-08-28-user-message-rail-design.md`

## File map

| File | Role |
|------|------|
| `client/lib/pages/chat/chat_outline.dart` | `ChatOutlineEntry`, chrome, `buildChatOutline`, `owningUserTurnId`, `shouldShowChatOutline` |
| `client/lib/pages/chat/chat_message_locator.dart` | Shared locate |
| `client/lib/pages/chat/chat_outline_rail.dart` | Geometry + CustomPaint rail + preview overlay |
| `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` | `onVisibleRange` (ideal viewport range) |
| `client/lib/pages/chat/session_history_thread.dart` | Writes `visibleOwnerId` |
| `client/lib/pages/chat/session_history_review_messages.dart` | Pass `visibleOwnerId` through |
| `client/lib/pages/chat/session_chat_message_area.dart` | Stack rail; hide on subagent |
| `client/lib/pages/chat/session_chat_view.dart` | Own locator + notifier + highlight; find calls locator |
| `client/lib/l10n/app_en.arb`, `app_zh.arb` | Placeholder + semantics |
| tests next to each unit | TDD per task |

## Global Constraints

- Compact directory rail: one tick per `AiRole.user` in `loadedMessages`, evenly spaced, oldest at top. Not a document-height minimap.
- No duration / git chrome in v1 (`ChatOutlineChrome` fields stay null; footer builder returns null).
- No new cubit, no `shared_ui` primitive, no global shortcut (Mod+F stays find).
- Locator resolves **by id**, then index; missing id is a silent no-op; wait timeout **450ms** then do not reveal.
- `onVisibleRange` fires when viewport **turn indices** change, using `visibleRange(..., overscan: 0)` **before** `_retainUnion`. Do not report the retained mount window (with `retainMountedTurns: true` that window is eventually the whole list).
- Rail is one `CustomPaint` + one overlay card. Hover must not rebuild the thread.
- Hide rail when history is not showable, entries are empty, or subagent preview is open (`top != null`).
- Preview is truncated plain `AiTextPart` text (160 chars), never markdown, never `plainTextForCopy`.
- Index and locator have no `Widgets` dependency (locator may use `foundation` via `ChatRevealController`).
- Chat-only UI stays under `client/lib/pages/chat/`. Viewport callback stays in `ai_message_ui`.
- l10n: edit `app_en.arb` / `app_zh.arb` only, then `flutter gen-l10n`.
- Commands run from `client/` unless noted.

---

### Task 1: Chat outline index

**Files:**
- Create: `client/lib/pages/chat/chat_outline.dart`
- Test: `client/test/pages/chat/chat_outline_test.dart`

**Interfaces:**
- Consumes: `AiMessage`, `AiRole`, `AiTextPart`, `AiToolCallPart` from `package:ai_message_core/ai_message_core.dart`; `buildTurns` from `package:ai_message_ui/ai_message_ui.dart`
- Produces:
  - `enum ChatOutlineKind { userTurn }`
  - `class ChatOutlineChrome { const ChatOutlineChrome({this.worked, this.gitSha}); final Duration? worked; final String? gitSha; }`
  - `class ChatOutlineEntry { required String id; required int messageIndex; required String preview; ChatOutlineKind kind; ChatOutlineChrome chrome; }`
  - `const int kChatOutlinePreviewLimit = 160;`
  - `List<ChatOutlineEntry> buildChatOutline(List<AiMessage> all, {required String emptyPreview, List<ChatOutlineEntry> previous = const []})`
  - `String? owningUserTurnId(List<AiMessage> messages, int firstVisibleTurnIndex)`
  - `bool shouldShowChatOutline({required bool threadVisible, required bool subagentPreviewOpen, required List<ChatOutlineEntry> entries})`

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/chat/chat_outline_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_outline.dart';

AiMessage _user(String id, String text) => AiMessage(
  id: id,
  role: AiRole.user,
  parts: [AiTextPart(text: text)],
);

AiMessage _assistant(String id, String text) => AiMessage(
  id: id,
  role: AiRole.assistant,
  parts: [AiTextPart(text: text)],
);

void main() {
  test('keeps only user turns with loadedMessages indices', () {
    final all = [
      _user('u0', 'hello'),
      _assistant('a0', 'hi'),
      _user('u1', 'next'),
    ];
    final entries = buildChatOutline(all, emptyPreview: 'Empty message');
    expect(entries.map((e) => (e.id, e.messageIndex)).toList(), [
      ('u0', 0),
      ('u1', 2),
    ]);
    expect(entries.every((e) => e.kind == ChatOutlineKind.userTurn), isTrue);
    expect(entries.every((e) => e.chrome.worked == null), isTrue);
  });

  test('preview concatenates text parts, collapses whitespace, truncates', () {
    final long = 'ab' * 100;
    final entries = buildChatOutline(
      [
        _user('u0', '  hello   \n  world  '),
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: [
            const AiTextPart(text: 'alpha'),
            AiToolCallPart(toolCallId: 't', toolName: 'bash'),
            const AiTextPart(text: 'beta'),
          ],
        ),
        _user('u2', long),
      ],
      emptyPreview: 'Empty message',
    );
    expect(entries[0].preview, 'hello world');
    expect(entries[1].preview, 'alpha beta');
    expect(entries[1].preview.contains('bash'), isFalse);
    expect(entries[2].preview.length, kChatOutlinePreviewLimit);
    expect(entries[2].preview, long.substring(0, kChatOutlinePreviewLimit));
  });

  test('empty text uses injected placeholder', () {
    final entries = buildChatOutline(
      [
        const AiMessage(id: 'u0', role: AiRole.user, parts: []),
        _user('u1', '   '),
      ],
      emptyPreview: 'Empty message',
    );
    expect(entries[0].preview, 'Empty message');
    expect(entries[1].preview, 'Empty message');
  });

  test('prefix-preserving append reuses previous entry instances', () {
    final first = [_user('u0', 'a'), _assistant('a0', 'x')];
    final previous = buildChatOutline(first, emptyPreview: 'Empty message');
    final appended = [...first, _user('u1', 'b')];
    final next = buildChatOutline(
      appended,
      emptyPreview: 'Empty message',
      previous: previous,
    );
    expect(identical(next[0], previous[0]), isTrue);
    expect(next[1].id, 'u1');
    expect(next[1].messageIndex, 2);
  });

  test('owningUserTurnId is the user turn at firstVisibleTurnIndex', () {
    final messages = [
      _user('u0', 'a'),
      _assistant('a0', 'b'),
      _user('u1', 'c'),
      _assistant('a1', 'd'),
    ];
    expect(owningUserTurnId(messages, 0), 'u0');
    expect(owningUserTurnId(messages, 1), 'u1');
    expect(owningUserTurnId(messages, -1), isNull);
    expect(owningUserTurnId(messages, 99), isNull);
  });

  test('owningUserTurnId is null for a leading assistant-only turn', () {
    final messages = [_assistant('a0', 'orphan'), _user('u0', 'later')];
    expect(owningUserTurnId(messages, 0), isNull);
    expect(owningUserTurnId(messages, 1), 'u0');
  });

  test('shouldShowChatOutline hides empty, subagent, and non-thread', () {
    final entries = buildChatOutline([_user('u0', 'a')], emptyPreview: 'x');
    expect(
      shouldShowChatOutline(
        threadVisible: true,
        subagentPreviewOpen: false,
        entries: entries,
      ),
      isTrue,
    );
    expect(
      shouldShowChatOutline(
        threadVisible: true,
        subagentPreviewOpen: true,
        entries: entries,
      ),
      isFalse,
    );
    expect(
      shouldShowChatOutline(
        threadVisible: false,
        subagentPreviewOpen: false,
        entries: entries,
      ),
      isFalse,
    );
    expect(
      shouldShowChatOutline(
        threadVisible: true,
        subagentPreviewOpen: false,
        entries: const [],
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/chat_outline_test.dart`

Expected: FAIL compiling (`chat_outline.dart` does not exist).

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/pages/chat/chat_outline.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';

const int kChatOutlinePreviewLimit = 160;

enum ChatOutlineKind { userTurn }

class ChatOutlineChrome {
  const ChatOutlineChrome({this.worked, this.gitSha});

  final Duration? worked;
  final String? gitSha;
}

class ChatOutlineEntry {
  const ChatOutlineEntry({
    required this.id,
    required this.messageIndex,
    required this.preview,
    this.kind = ChatOutlineKind.userTurn,
    this.chrome = const ChatOutlineChrome(),
  });

  final String id;
  final int messageIndex;
  final String preview;
  final ChatOutlineKind kind;
  final ChatOutlineChrome chrome;
}

List<ChatOutlineEntry> buildChatOutline(
  List<AiMessage> all, {
  required String emptyPreview,
  List<ChatOutlineEntry> previous = const [],
}) {
  final users = <({int index, AiMessage message})>[];
  for (var i = 0; i < all.length; i++) {
    if (all[i].role == AiRole.user) {
      users.add((index: i, message: all[i]));
    }
  }
  var reuse = 0;
  while (reuse < previous.length &&
      reuse < users.length &&
      previous[reuse].id == users[reuse].message.id &&
      previous[reuse].messageIndex == users[reuse].index &&
      previous[reuse].preview ==
          _previewFor(users[reuse].message, emptyPreview)) {
    reuse++;
  }
  return [
    ...previous.take(reuse),
    for (var i = reuse; i < users.length; i++)
      ChatOutlineEntry(
        id: users[i].message.id,
        messageIndex: users[i].index,
        preview: _previewFor(users[i].message, emptyPreview),
      ),
  ];
}

String? owningUserTurnId(List<AiMessage> messages, int firstVisibleTurnIndex) {
  if (firstVisibleTurnIndex < 0) return null;
  final turns = buildTurns(messages);
  if (firstVisibleTurnIndex >= turns.length) return null;
  final id = turns[firstVisibleTurnIndex].id;
  for (final m in messages) {
    if (m.id == id) {
      return m.role == AiRole.user ? id : null;
    }
  }
  return null;
}

bool shouldShowChatOutline({
  required bool threadVisible,
  required bool subagentPreviewOpen,
  required List<ChatOutlineEntry> entries,
}) {
  return threadVisible && !subagentPreviewOpen && entries.isNotEmpty;
}

String _previewFor(AiMessage message, String emptyPreview) {
  final buf = StringBuffer();
  for (final part in message.parts) {
    if (part is! AiTextPart) continue;
    final t = part.text.trim();
    if (t.isEmpty) continue;
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(t.replaceAll(RegExp(r'\s+'), ' '));
  }
  var text = buf.toString().trim();
  if (text.isEmpty) return emptyPreview;
  if (text.length > kChatOutlinePreviewLimit) {
    text = text.substring(0, kChatOutlinePreviewLimit);
  }
  return text;
}
```

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/pages/chat/chat_outline_test.dart`

Expected: PASS (all 7 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/chat_outline.dart client/test/pages/chat/chat_outline_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): index user turns for the outline rail

EOF
)"
```

---

### Task 2: Shared message locator

**Files:**
- Create: `client/lib/pages/chat/chat_message_locator.dart`
- Test: `client/test/pages/chat/chat_message_locator_test.dart`

**Interfaces:**
- Consumes: `ChatOutlineEntry` is not required. `AiThreadRuntime` / `ExternalStoreAiThreadRuntime` from `ai_message_core`. `ChatRevealController` from `client/lib/pages/chat/chat_reveal_controller.dart`.
- Produces:
  - `class ChatMessageLocator`
  - `ChatMessageLocator({required List<AiMessage> Function() loadedMessages, required AiThreadRuntime Function() runtime, required void Function(int index) revealInWindow, required ChatRevealController revealController, required void Function(String? id) onHighlight, Duration timeout = const Duration(milliseconds: 450), Future<void> Function()? waitFrame})`
  - `Future<void> locate({required String id, int? index})`
  - `void cancel()` — bump generation so an in-flight wait does not reveal

Locator must **not** take `AiHistorySeat` (tests inject functions). `SessionChatView` will pass `() => _seat?.loadedMessages ?? const []` and `(i) => _seat?.revealMessage(i)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/chat/chat_message_locator_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_message_locator.dart';
import 'package:teampilot/pages/chat/chat_reveal_controller.dart';

AiMessage _user(String id) => AiMessage(
  id: id,
  role: AiRole.user,
  parts: const [AiTextPart(text: 'x')],
);

void main() {
  test('reveals after id is already in the runtime', () async {
    final runtime = ExternalStoreAiThreadRuntime()
      ..setMessages([_user('u0'), _user('u1')]);
    final loaded = [_user('u0'), _user('u1'), _user('u2')];
    final revealed = <int>[];
    final controller = ChatRevealController();
    String? highlight;
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: revealed.add,
      revealController: controller,
      onHighlight: (id) => highlight = id,
      waitFrame: () async {},
    );

    await locator.locate(id: 'u1', index: 99);

    expect(revealed, [1]);
    expect(controller.targetMessageId, 'u1');
    expect(highlight, 'u1');
  });

  test('waits for runtime then reveals', () async {
    final runtime = ExternalStoreAiThreadRuntime();
    final loaded = [_user('u0')];
    final controller = ChatRevealController();
    final locator = ChatMessageLocator(
      loadedMessages: () => loaded,
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (_) {},
      waitFrame: () async {},
    );

    final pending = locator.locate(id: 'u0');
    runtime.setMessages([_user('u0')]);
    await pending;

    expect(controller.targetMessageId, 'u0');
  });

  test('missing id does not reveal', () async {
    final runtime = ExternalStoreAiThreadRuntime()..setMessages([_user('u0')]);
    final controller = ChatRevealController();
    var highlightCalls = 0;
    final locator = ChatMessageLocator(
      loadedMessages: () => [_user('u0')],
      runtime: () => runtime,
      revealInWindow: (_) {},
      revealController: controller,
      onHighlight: (_) => highlightCalls++,
      waitFrame: () async {},
    );

    await locator.locate(id: 'missing');

    expect(controller.targetMessageId, isNull);
    expect(highlightCalls, 0);
  });

  test('timeout does not reveal', () {
    FakeAsync().run((async) {
      final runtime = ExternalStoreAiThreadRuntime();
      final controller = ChatRevealController();
      final locator = ChatMessageLocator(
        loadedMessages: () => [_user('u0')],
        runtime: () => runtime,
        revealInWindow: (_) {},
        revealController: controller,
        onHighlight: (_) {},
        timeout: const Duration(milliseconds: 450),
        waitFrame: () async {},
      );

      locator.locate(id: 'u0');
      async.elapse(const Duration(milliseconds: 451));

      expect(controller.targetMessageId, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/chat_message_locator_test.dart`

Expected: FAIL compiling (`chat_message_locator.dart` does not exist).

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/pages/chat/chat_message_locator.dart`:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import 'chat_reveal_controller.dart';

class ChatMessageLocator {
  ChatMessageLocator({
    required this.loadedMessages,
    required this.runtime,
    required this.revealInWindow,
    required this.revealController,
    required this.onHighlight,
    this.timeout = const Duration(milliseconds: 450),
    Future<void> Function()? waitFrame,
  }) : waitFrame = waitFrame ?? (() => Future<void>.value());

  final List<AiMessage> Function() loadedMessages;
  final AiThreadRuntime Function() runtime;
  final void Function(int index) revealInWindow;
  final ChatRevealController revealController;
  final void Function(String? id) onHighlight;
  final Duration timeout;
  final Future<void> Function() waitFrame;

  int _generation = 0;

  void cancel() {
    _generation++;
  }

  Future<void> locate({required String id, int? index}) async {
    final gen = ++_generation;
    final all = loadedMessages();
    final resolved = all.indexWhere((m) => m.id == id);
    if (resolved < 0) return;
    revealInWindow(resolved);
    if (!_contains(id)) {
      final appeared = Completer<void>();
      final sub = runtime().changes.listen((_) {
        if (_contains(id) && !appeared.isCompleted) {
          appeared.complete();
        }
      });
      try {
        await appeared.future.timeout(timeout);
      } on TimeoutException {
        await sub.cancel();
        return;
      } finally {
        await sub.cancel();
      }
    }
    if (gen != _generation) return;
    await waitFrame();
    if (gen != _generation) return;
    revealController.reveal(id);
    onHighlight(id);
  }

  bool _contains(String id) {
    for (final m in runtime().messages) {
      if (m.id == id) return true;
    }
    return false;
  }
}
```

If the wait-for-runtime test races (setMessages before subscribe), call `setMessages` after `locate` is listening: keep the test as written; in `locate`, subscribe **before** the contains check’s wait path, and if `setMessages` already happened after `revealInWindow` the contains check on the next line handles it. Order in implementation: `revealInWindow` then `if (!_contains)` subscribe. The test starts `locate` then `setMessages` — good.

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/pages/chat/chat_message_locator_test.dart`

Expected: PASS.

If the timeout test fails because `timeout` uses real timers inside FakeAsync, keep `timeout` on `appeared.future.timeout(timeout)` — `fake_async` intercepts it. If `wait-for-runtime` hangs, add `if (_contains(id) && !appeared.isCompleted)` immediately after subscribe.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/chat_message_locator.dart client/test/pages/chat/chat_message_locator_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): wait for message id before reveal

EOF
)"
```

---

### Task 3: Viewport visible-range callback

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart` (constructor ~line 12–80, field list, `_syncVisibleRange` ~321–423)
- Test: `client/packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart`

**Interfaces:**
- Consumes: existing `TurnVisibleRange`, `TurnHeightCache.visibleRange`
- Produces: `final ValueChanged<TurnVisibleRange>? onVisibleRange` on `VirtualThreadViewport`. Invoked when `firstIndex`/`lastIndex` of the **viewport-visible** range change. Compute with `overscan: 0` from current scroll pixels, **before** `_retainUnion`. Do not include padding in the equality check. Do not fire on the first seed frame if lastIndex < firstIndex (empty).

- [ ] **Step 1: Write the failing test**

Create `client/packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<AiMessage> _messages(int count) => [
  for (var i = 0; i < count; i++)
    AiMessage(
      id: 'm-$i',
      role: AiRole.user,
      parts: [AiTextPart(text: 'msg-$i')],
    ),
];

void main() {
  testWidgets('scroll reports a new viewport turn range', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ranges = <TurnVisibleRange>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 120,
          child: SingleChildScrollView(
            controller: controller,
            child: VirtualThreadViewport(
              messages: _messages(20),
              scrollController: controller,
              estimateHeight: 40,
              mountTurns: true,
              retainMountedTurns: true,
              fillDataWindow: true,
              overscan: 5,
              onVisibleRange: ranges.add,
              messageBuilder: (context, message) => SizedBox(
                height: 40,
                child: Text(message.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ranges, isNotEmpty);
    final afterOpen = ranges.length;
    final firstOpen = ranges.last.firstIndex;

    controller.jumpTo(400);
    await tester.pumpAndSettle();

    expect(ranges.length, greaterThan(afterOpen));
    expect(ranges.last.firstIndex, greaterThan(firstOpen));
    // Must not be the retained full window (0..19) just because retain is on.
    expect(ranges.last.lastIndex - ranges.last.firstIndex, lessThan(19));
  });

  testWidgets('unchanged turn range does not spam callbacks', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final ranges = <TurnVisibleRange>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: SingleChildScrollView(
            controller: controller,
            child: VirtualThreadViewport(
              messages: _messages(8),
              scrollController: controller,
              estimateHeight: 40,
              mountTurns: true,
              retainMountedTurns: true,
              fillDataWindow: true,
              overscan: 0,
              onVisibleRange: ranges.add,
              messageBuilder: (context, message) => SizedBox(
                height: 40,
                child: Text(message.id),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final afterOpen = ranges.length;

    controller.jumpTo(4);
    await tester.pump();
    controller.jumpTo(8);
    await tester.pump();

    expect(ranges.length, afterOpen);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart`

Expected: FAIL (`onVisibleRange` is not a parameter).

- [ ] **Step 3: Write minimal implementation**

In `VirtualThreadViewport`:

1. Add to constructor (after `onRevealOffset`):
```dart
this.onVisibleRange,
```
2. Add field:
```dart
/// Viewport-visible turn range (overscan 0), not the retained mount window.
final ValueChanged<TurnVisibleRange>? onVisibleRange;
```
3. In `_VirtualThreadViewportState` add:
```dart
int _notifiedVisibleFirst = 0;
int _notifiedVisibleLast = -1;
```
4. At the start of the `hasClients && hasViewportDimension` branch in `_syncVisibleRange`, after `scrollPixels` is finalized, compute and notify:

```dart
final viewportVisible = _cache.visibleRange(
  turns: _turns,
  scrollPixels: _scrollPixelsInTurnSpace(scrollPixels),
  viewportHeight: position.viewportDimension,
  overscan: 0,
);
_notifyVisibleRange(viewportVisible);
```

Keep the existing `range = _cache.clampUnmeasuredMounts(..., overscan: widget.overscan)` path for mounting unchanged.

5. Add method:

```dart
void _notifyVisibleRange(TurnVisibleRange visible) {
  final cb = widget.onVisibleRange;
  if (cb == null) return;
  if (visible.firstIndex == _notifiedVisibleFirst &&
      visible.lastIndex == _notifiedVisibleLast) {
    return;
  }
  _notifiedVisibleFirst = visible.firstIndex;
  _notifiedVisibleLast = visible.lastIndex;
  cb(visible);
}
```

Call `_notifyVisibleRange` also for the empty-turns branch (`lastIndex: -1`) so hosts can clear.

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart packages/ai_message_ui/test/virtual_thread_viewport_reveal_test.dart`

Expected: PASS. If the spam test still increments because firstIndex moves on a 4px jump, increase the jump to stay inside the same 40px turn (`jumpTo(1)` then `jumpTo(2)`).

- [ ] **Step 5: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/virtual_thread_viewport.dart \
  client/packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart
git commit -m "$(cat <<'EOF'
feat(ai_message_ui): publish viewport-visible turn range

EOF
)"
```

---

### Task 4: Thread visible-owner notifier

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart` (constructor ~41–73, `VirtualThreadViewport` ~596–636)
- Modify: `client/lib/pages/chat/session_history_review_messages.dart` (pass-through)
- Test: `client/test/pages/chat/session_history_thread_test.dart`

**Interfaces:**
- Consumes: `owningUserTurnId` from Task 1; `onVisibleRange` from Task 3
- Produces: `SessionHistoryThread.visibleOwnerId` → `ValueNotifier<String?>?`. On `onVisibleRange`, set `visibleOwnerId.value = owningUserTurnId(_displayMessages, range.firstIndex)` (same list the viewport uses). Do not `setState` for this.

- [ ] **Step 1: Write the failing test**

Append to `client/test/pages/chat/session_history_thread_test.dart`:

```dart
testWidgets('visibleOwnerId follows the first visible user turn', (tester) async {
  final store = ExternalStoreAiThreadRuntime()
    ..setMessages([
      ...List.generate(
        12,
        (i) => AiMessage(
          id: 'u$i',
          role: AiRole.user,
          parts: [AiTextPart(text: 'msg $i')],
        ),
      ),
    ]);
  final owner = ValueNotifier<String?>(null);
  addTearDown(owner.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(extensions: [AiMessageTheme.test()]),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 160,
          child: SessionHistoryThread(
            runtime: store,
            hasOlder: false,
            isLoadingOlder: false,
            visibleOwnerId: owner,
          ),
        ),
      ),
    ),
  );
  await pumpUntilSettled(tester);

  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, -800));
  await tester.pumpAndSettle();

  expect(owner.value, isNotNull);
  expect(owner.value, isNot('u0'));
});
```

Add `visibleOwnerId` to the existing `_harness` as an optional named param defaulting to null so old tests keep compiling.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/session_history_thread_test.dart --plain-name 'visibleOwnerId follows'`

Expected: FAIL compiling (`visibleOwnerId` is not a parameter).

- [ ] **Step 3: Write minimal implementation**

`SessionHistoryThread`: add `this.visibleOwnerId` (`ValueNotifier<String?>?`). On `VirtualThreadViewport`:

```dart
onVisibleRange: (range) {
  final notifier = widget.visibleOwnerId;
  if (notifier == null) return;
  notifier.value = owningUserTurnId(_displayMessages, range.firstIndex);
},
```

Import `chat_outline.dart`.

`SessionHistoryReviewMessages`: add the same optional `visibleOwnerId` and pass it into `SessionHistoryThread`.

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/pages/chat/session_history_thread_test.dart`

Expected: PASS. If owner stays `u0` because stick-to-end keeps the last turn visible, assert `owner.value == 'u11'` after open (anchor end) and a different id after dragging to top (`u0`). Adjust the assertion to: after settle, `owner.value` is a user id from the list; after `jumpTo(0)`, `owner.value == 'u0'`.

Use the thread’s `ScrollController` via `tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0)` if drag is flaky.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/session_history_thread.dart \
  client/lib/pages/chat/session_history_review_messages.dart \
  client/test/pages/chat/session_history_thread_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): publish owning user turn from history thread

EOF
)"
```

---

### Task 5: Outline rail widget

**Files:**
- Create: `client/lib/pages/chat/chat_outline_rail.dart`
- Test: `client/test/pages/chat/chat_outline_rail_test.dart`

**Interfaces:**
- Consumes: `ChatOutlineEntry` from Task 1
- Produces:
  - `const double kChatOutlineRailWidth = 20;`
  - `const double kChatOutlineMinTickGap = 10;`
  - `const double kChatOutlineTickSlop = 16;`
  - `const Key kChatOutlineRailKey = ValueKey('chat-outline-rail');`
  - `const Key kChatOutlinePreviewCardKey = ValueKey('chat-outline-preview-card');`
  - `double chatOutlineStride({required double height, required int count})` → `count <= 0 ? 0 : max(kChatOutlineMinTickGap, height / count)`
  - `int? chatOutlineTickAt({required Offset local, required Size size, required int count})` — nearest tick if distance to center ≤ slop and `local.dx` is inside the rail (or within slop of the track)
  - `class ChatOutlineRail extends StatefulWidget` with `entries`, `activeId` (`ValueListenable<String?>`), `onLocate(ChatOutlineEntry entry)`, `emptyPreview` unused (preview is on the entry), optional `Widget? Function(BuildContext, ChatOutlineEntry)? footerBuilder` (v1 callers pass null)
  - Hover (mouse): show card; click tick or card → `onLocate` and close card
  - Tap (touch): `onLocate` immediately
  - Long-press: show card
  - Focus + ArrowDown/Up + Enter locate; Escape closes card and unfocuses
  - New `entries` without the hovered id closes the overlay
  - Independent scroll when `count * minGap > viewport height` (content height = `count * stride` with stride = minGap)

- [ ] **Step 1: Write the failing tests**

Create `client/test/pages/chat/chat_outline_rail_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_outline.dart';
import 'package:teampilot/pages/chat/chat_outline_rail.dart';

List<ChatOutlineEntry> _entries() => const [
  ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'first prompt'),
  ChatOutlineEntry(id: 'u1', messageIndex: 2, preview: 'second prompt'),
  ChatOutlineEntry(id: 'u2', messageIndex: 4, preview: 'third prompt'),
];

Widget _harness({
  required List<ChatOutlineEntry> entries,
  required ValueNotifier<String?> activeId,
  required List<String> located,
}) {
  return TpTheme(
    data: TpThemeData.fromColorScheme(ColorScheme.fromSeed(seedColor: Colors.blue)),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: ChatOutlineRail(
            entries: entries,
            activeId: activeId,
            onLocate: (e) => located.add(e.id),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('tick hit testing maps y to nearest index inside slop', () {
    const size = Size(20, 300);
    expect(
      chatOutlineTickAt(local: const Offset(10, 50), size: size, count: 3),
      0,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 150), size: size, count: 3),
      1,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 250), size: size, count: 3),
      2,
    );
    expect(
      chatOutlineTickAt(local: const Offset(10, 150), size: size, count: 0),
      isNull,
    );
  });

  testWidgets('empty entries paint nothing', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    await tester.pumpWidget(_harness(entries: const [], activeId: active, located: []));
    expect(find.byKey(kChatOutlineRailKey), findsNothing);
  });

  testWidgets('click tick locates that entry', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    await tester.tapAt(tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(10, 50));
    await tester.pump();
    expect(located, ['u0']);
  });

  testWidgets('hover shows preview card; click card locates', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(10, 150),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsOneWidget);
    expect(find.text('second prompt'), findsOneWidget);
    await tester.tap(find.byKey(kChatOutlinePreviewCardKey));
    await tester.pump();
    expect(located, ['u1']);
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
  });

  testWidgets('ArrowDown then Enter locates the next entry', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    await tester.tap(find.byKey(kChatOutlineRailKey));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(located, ['u1']);
  });

  testWidgets('replacing entries without hovered id closes overlay', (tester) async {
    final active = ValueNotifier<String?>(null);
    addTearDown(active.dispose);
    final located = <String>[];
    await tester.pumpWidget(
      _harness(entries: _entries(), activeId: active, located: located),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(
      location: tester.getTopLeft(find.byKey(kChatOutlineRailKey)) + const Offset(10, 50),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        entries: const [
          ChatOutlineEntry(id: 'other', messageIndex: 0, preview: 'gone'),
        ],
        activeId: active,
        located: located,
      ),
    );
    await tester.pump();
    expect(find.byKey(kChatOutlinePreviewCardKey), findsNothing);
  });
}
```

Wrap with `TpTheme` as shown so `TpTextStyles.of(context)` works if the card uses it. If tests fail on theme, use `Theme.of(context).textTheme.bodyMedium` instead in the card (still fine). Prefer `TpTextStyles.of(context).sm`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/chat_outline_rail_test.dart`

Expected: FAIL compiling.

- [ ] **Step 3: Write the rail**

Create `client/lib/pages/chat/chat_outline_rail.dart` implementing:

Geometry:

```dart
double chatOutlineStride({required double height, required int count}) {
  if (count <= 0) return 0;
  return math.max(kChatOutlineMinTickGap, height / count);
}

int? chatOutlineTickAt({
  required Offset local,
  required Size size,
  required int count,
}) {
  if (count <= 0) return null;
  final stride = chatOutlineStride(height: size.height, count: count);
  final i = (local.dy / stride).floor().clamp(0, count - 1);
  final centerY = stride * i + stride / 2;
  final dx = (local.dx - size.width / 2).abs();
  final dy = (local.dy - centerY).abs();
  if (dy > kChatOutlineTickSlop && dx > kChatOutlineTickSlop) return null;
  if (dy > stride / 2 + 0.01) return null;
  return i;
}
```

Widget outline:

- If `entries.isEmpty` → `SizedBox.shrink()` (no key).
- Else `SizedBox(width: kChatOutlineRailWidth, key: kChatOutlineRailKey)` with `Focus` + `Shortcuts`/`Actions` for arrows/enter/escape.
- `LayoutBuilder` → if `count * minGap > height`, wrap paint in `SingleChildScrollView` with inner height `count * minGap`; else paint at viewport height.
- `Listener` (`onPointerHover`, `onPointerDown`) + `GestureDetector` (`onTap` for mouse/touch locate from `tickAt`, `onLongPress` show preview).
- `CustomPaint` painter draws the track (`onSurfaceVariant` alpha ~0.35) and ticks. Longer/darker tick when id == hover or focus or `activeId.value` or last located. Hover wins over active.
- `hitTestBehavior`: in a custom `RenderBox` or by returning false from `Listener` when `tickAt` is null — use a wrapper `RenderPointerListener` subclass **or** simpler: `MouseRegion` only on the rail width and ignore misses in `onPointerDown` (do not call locate). To let the thread receive events in the gutter, wrap paint in `_TickHitTarget` extending `SingleChildRenderObjectWidget` whose `hitTest` returns false when `chatOutlineTickAt` is null.
- Overlay: `OverlayPortal` or a `Stack` in the rail’s parent is awkward because the card must sit to the **right** of the 20px rail (into the thread). Use `OverlayPortal` / `CompositedTransformFollower` with a `LayerLink`, card `left: 24`, vertically aligned to the hovered tick. Card: `Material` elevation 2, radius 8, padding, `Text(preview, maxLines: 4, overflow: ellipsis)`, key `kChatOutlinePreviewCardKey`, `InkWell` onTap locate. `footerBuilder?.call(context, entry)` under the text if non-null.
- Mouse leave rail **and** card → close (use a small `Timer(120ms)` cancel on card `onEnter`).
- `didUpdateWidget`: if hovered id not in new entries, close overlay.

Keep this file focused: geometry functions + painter + stateful rail. If it exceeds ~400 lines, split `chat_outline_rail_painter.dart` in the same folder (still `pages/chat/`).

- [ ] **Step 4: Run tests and make sure they pass**

Run: `cd client && flutter test test/pages/chat/chat_outline_rail_test.dart`

Expected: PASS. If click Y=50 is wrong for 3 ticks in 300px (stride=100, centers 50/150/250), the geometry test already locks that. Keyboard: first hover/focus index defaults to 0 so ArrowDown selects index 1.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/chat/chat_outline_rail.dart client/test/pages/chat/chat_outline_rail_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): add user-message outline rail widget

EOF
)"
```

---

### Task 6: Wire chat view, l10n, and find

**Files:**
- Modify: `client/lib/l10n/app_en.arb` (after `chatFindUseRegex`)
- Modify: `client/lib/l10n/app_zh.arb` (after `chatFindUseRegex`)
- Modify: `client/lib/pages/chat/session_chat_view.dart` (~176–186, 341–362, 365–386 dispose, ~1371)
- Modify: `client/lib/pages/chat/session_chat_message_area.dart` (constructor, Stack ~236–326)
- Test: `client/test/pages/chat/session_chat_message_area_outline_test.dart`

**Interfaces:**
- Consumes: Tasks 1–5
- Produces: Rail visible on ready chat with user turns; find `_navigateFindTo` calls `ChatMessageLocator.locate`; shared highlight; subagent hides rail; seat change `locator.cancel()`, `visibleOwnerId.value = null`, `highlight = null`

l10n keys (exact):

`app_en.arb` after `chatFindUseRegex`:

```json
  "chatUserMessageRailEmptyPreview": "Empty message",
  "chatUserMessageRailSemanticLabel": "User message {index} of {total}",
  "@chatUserMessageRailSemanticLabel": {
    "placeholders": {
      "index": { "type": "int" },
      "total": { "type": "int" }
    }
  },
```

`app_zh.arb`:

```json
  "chatUserMessageRailEmptyPreview": "空消息",
  "chatUserMessageRailSemanticLabel": "用户消息第 {index} 条，共 {total} 条",
```

Then `cd client && flutter gen-l10n`.

- [ ] **Step 1: Write the failing widget test for hide rules**

Create `client/test/pages/chat/session_chat_message_area_outline_test.dart` that does **not** pump the full `SessionChatMessageArea` (too many cubits). Instead test the host helper you will add next to the area file **or** re-use `shouldShowChatOutline` plus a thin wrapper:

Add `const Key kChatOutlineHostKey = ValueKey('chat-outline-host');` on the `Positioned` rail in `SessionChatMessageArea`.

Because `SessionChatMessageArea` needs `ChatCubit` / `LayoutCubit` / workspace tools, put a small `ChatOutlineHost` widget in `chat_outline_rail.dart` or `session_chat_message_area.dart`:

```dart
class ChatOutlineHost extends StatelessWidget {
  const ChatOutlineHost({
    required this.show,
    required this.entries,
    required this.activeId,
    required this.onLocate,
    super.key,
  });
  final bool show;
  final List<ChatOutlineEntry> entries;
  final ValueListenable<String?> activeId;
  final ValueChanged<ChatOutlineEntry> onLocate;
  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Positioned(
      key: kChatOutlineHostKey,
      left: 0,
      top: 0,
      bottom: 0,
      width: kChatOutlineRailWidth,
      child: ChatOutlineRail(
        entries: entries,
        activeId: activeId,
        onLocate: onLocate,
      ),
    );
  }
}
```

Test:

```dart
testWidgets('ChatOutlineHost is absent when show is false', (tester) async {
  final active = ValueNotifier<String?>(null);
  addTearDown(active.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          ChatOutlineHost(
            show: false,
            entries: const [
              ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'x'),
            ],
            activeId: active,
            onLocate: (_) {},
          ),
        ],
      ),
    ),
  );
  expect(find.byKey(kChatOutlineHostKey), findsNothing);
});

testWidgets('ChatOutlineHost mounts the rail when show is true', (tester) async {
  final active = ValueNotifier<String?>(null);
  addTearDown(active.dispose);
  await tester.pumpWidget(
    TpTheme(
      data: TpThemeData.fromColorScheme(ColorScheme.fromSeed(seedColor: Colors.blue)),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Stack(
          children: [
            ChatOutlineHost(
              show: true,
              entries: const [
                ChatOutlineEntry(id: 'u0', messageIndex: 0, preview: 'hello'),
              ],
              activeId: active,
              onLocate: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
  expect(find.byKey(kChatOutlineRailKey), findsOneWidget);
});
```

Also add a locator-wiring unit-style test in `session_chat_view` only if an existing session_chat_view test harness is easy; otherwise add this to `chat_message_locator_test` coverage (already done) and in this task replace `_navigateFindTo` body with locator.locate — verify by reading the call site in review.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/chat/session_chat_message_area_outline_test.dart`

Expected: FAIL (`ChatOutlineHost` / keys missing).

- [ ] **Step 3: Wire**

1. ARB + `flutter gen-l10n`.
2. `SessionChatViewState`:
   - `final _visibleOwnerId = ValueNotifier<String?>(null);`
   - `late final ChatMessageLocator _locator` created in `initState` with closures that always read the current seat:
     ```dart
     _locator = ChatMessageLocator(
       loadedMessages: () => _seat?.loadedMessages ?? const [],
       runtime: () => _seat?.runtime ?? _emptyRuntime,
       revealInWindow: (index) => _seat?.revealMessage(index),
       revealController: _revealController,
       onHighlight: (id) {
         if (mounted) setState(() => _locateHighlightId = id);
       },
       waitFrame: () {
         final done = Completer<void>();
         WidgetsBinding.instance.addPostFrameCallback((_) {
           if (!done.isCompleted) done.complete();
         });
         return done.future;
       },
     );
     ```
     `_emptyRuntime` is a long-lived `ExternalStoreAiThreadRuntime()` field used only when `_seat` is null (locate will no-op on missing ids).
   - `_locateHighlightId` (rename from `_findHighlightId`).
   - `_navigateFindTo`:
     ```dart
     unawaited(_locator.locate(id: hit.messageId, index: hit.messageIndex));
     ```
   - `_closeFind` still clears highlight via `setState(() => _locateHighlightId = null)` and `_revealController.clear()`. Do not `cancel()` a rail locate just because find closes.
   - On seat/member change: `_locator.cancel(); _visibleOwnerId.value = null; _locateHighlightId = null;`
   - `dispose`: `_visibleOwnerId.dispose(); _locator.cancel();`
3. `SessionChatMessageArea`: add `outlineEntries`, `visibleOwnerId`, `onLocateOutline`. Inside the thread `Stack` (sibling of `SessionHistoryReviewMessages`, **under** subagent `Positioned.fill` so subagent covers it — and also skip building it when `top != null`):

```dart
if (shouldShowChatOutline(
      threadVisible: true,
      subagentPreviewOpen: top != null,
      entries: outlineEntries,
    ))
  ChatOutlineHost(
    show: true,
    entries: outlineEntries,
    activeId: visibleOwnerId,
    onLocate: onLocateOutline,
  ),
```

Pass `visibleOwnerId` into `SessionHistoryReviewMessages`.

Compute `outlineEntries` in `SessionChatView` (has `l10n` and `_seat.loadedMessages`) with a field `List<ChatOutlineEntry> _outline = const []` updated when the history `BlocBuilder` rebuilds:

```dart
_outline = buildChatOutline(
  historySeat.loadedMessages,
  emptyPreview: context.l10n.chatUserMessageRailEmptyPreview,
  previous: _outline,
);
```

Do this in the view’s build where the seat is already available (the same place that constructs `SessionChatMessageArea`).

`onLocateOutline: (e) => unawaited(_locator.locate(id: e.id, index: e.messageIndex))`.

Pass `semanticLabel` into the rail using `l10n.chatUserMessageRailSemanticLabel(i + 1, entries.length)` per tick if you add semantics in Task 5; if Task 5 shipped without semantics, add `Semantics(label: ...)` on the rail in this task.

4. Pass `highlightMessageId: _locateHighlightId` (keep constructor name `findHighlightId` **or** rename to `highlightMessageId` in area + review messages; renaming is clearer — do it in this task and update call sites).

- [ ] **Step 4: Run tests**

Run:

```
cd client && flutter test \
  test/pages/chat/chat_outline_test.dart \
  test/pages/chat/chat_message_locator_test.dart \
  test/pages/chat/chat_outline_rail_test.dart \
  test/pages/chat/session_chat_message_area_outline_test.dart \
  test/pages/chat/session_history_thread_test.dart \
  packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart
```

Expected: PASS. Also run any existing find tests: `flutter test test/pages/chat --plain-name Find` (or `*find*` files under `test/pages/chat` / `test/services/session`).

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/pages/chat/session_chat_view.dart \
  client/lib/pages/chat/session_chat_message_area.dart \
  client/lib/pages/chat/session_history_review_messages.dart \
  client/lib/pages/chat/chat_message_locator.dart \
  client/test/pages/chat/session_chat_message_area_outline_test.dart \
  client/test/pages/chat/chat_message_locator_test.dart
git commit -m "$(cat <<'EOF'
feat(chat): wire user-message rail and shared locate

EOF
)"
```

Include generated l10n Dart files if `generate: true` updates them in-tree.

---

### Task 7: Format, analyze, full test gate

**Files:** all files from Tasks 1–6

- [ ] **Step 1: Format**

Run: `cd client && dart format lib/pages/chat packages/ai_message_ui/lib/src/virtual_thread_viewport.dart test/pages/chat packages/ai_message_ui/test/virtual_thread_viewport_visible_range_test.dart`

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

Expected: no issues in touched files.

- [ ] **Step 3: Focused + full tests**

Run focused suite from Task 6 Step 4, then `cd client && dart run tool/run_tests.dart`.

Record any unrelated baseline failures separately; do not “fix” them in this branch unless you caused them.

- [ ] **Step 4: Commit formatting/fixes if any**

```bash
git add -u
git commit -m "$(cat <<'EOF'
chore(chat): format user-message rail

EOF
)"
```

Skip this commit if the working tree is clean.

---

## Spec coverage (self-review)

| Spec item | Task |
|-----------|------|
| Compact tick rail, oldest at top | 5, 6 |
| Hover preview / click locate | 5 |
| Touch tap locate / long-press preview | 5 |
| Keyboard after focus | 5 |
| Shared wait-for-id locator; find uses it | 2, 6 |
| CustomPaint + one card | 5 |
| Active tick from viewport-visible owner | 3, 4 |
| Hide when empty / not ready / subagent | 1 (`shouldShowChatOutline`), 6 |
| Prefix-stable outline | 1 |
| Locate by id | 2 |
| Extensible chrome + footer slot | 1, 5 (`footerBuilder`) |
| l10n keys | 6 |
| No duration/git/minimap/cubit/shared_ui | throughout |
| Rail hit-test rejects gutter | 5 (`_TickHitTarget`) |
| Independent rail scroll when dense | 5 |
| 450ms timeout silent | 2 |
