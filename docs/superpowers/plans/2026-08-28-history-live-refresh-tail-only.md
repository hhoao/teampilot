# History Live Refresh Tail-Only Hot Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make History live-refresh ticks only annotate, sign, and merge the changed message suffix so streaming no longer sorts, fingerprints, or rebuilds the whole timeline on the UI isolate.

**Architecture:** Add cheap content equality in `ai_message_core` and use it on the timeline/pagination hot path instead of `messageContentIdentity`. Extend CLI timeline deltas so last-replace plus append (and last-replace plus mailbox append) stay incremental and never call `mergeTimeline` except on invalidation. Extract suffix annotate + task-call signature update helpers and call them from `_finishIncremental` so prefix messages are not visited.

**Tech Stack:** Dart, Flutter, `ai_message_core`, `flutter_test` / `dart test`, existing `AiHistoryLoader` incremental path.

## Global Constraints

- Live incremental refresh does not annotate or signature-scan prefix messages.
- Live append / last-replace / last-replace-plus-append do not allocate a full `allEvents` list or rebuild every `AiMessage` via `mergeTimeline`.
- Hot path does not call `messageContentIdentity`.
- Do not change `messageContentIdentity` itself (UI widget keys keep it).
- Compact, truncate, and prefix rewrite still rebuild.
- Do not change JSONL tailer replace detection or `force` semantics.
- Do not skip mailbox IO on each `softReload`.
- Do not change last-bubble markdown relayout.
- Do not use fixed-millisecond CI budgets.
- Do not commit or modify pre-existing unrelated worktree changes (managed provider, l10n, `shared_ui`, perf dump tools).
- Every production behavior change starts with a failing test.

## File Map

- `client/packages/ai_message_core/lib/src/message_content_identity.dart`: add `cheapStringEqual` and `messagesCheapEqual`; leave `messageContentIdentity` unchanged.
- `client/packages/ai_message_core/test/message_content_identity_test.dart`: cheap-equality tests.
- `client/lib/services/conversation_timeline/conversation_timeline.dart`: `computeCliTimelineDelta` uses cheap equality; emits `CliTimelineLastReplacedAndAppended`; builder stops pre-building `allEvents`.
- `client/lib/services/conversation_timeline/timeline_merge.dart`: new delta type; last-replace + append / mailbox insert; drop append checksum; build full events only on fallback.
- `client/lib/services/session/session_history_pagination.dart`: `_reuseUnchangedMessage` uses `messagesCheapEqual`.
- `client/lib/services/session/ai_history_incremental.dart`: `identicalPrefixLength`, `annotateChangedSuffix`, `updateTaskCallSignatures`, `collectTaskCallSignatures`, `taskCallSignature`.
- `client/lib/services/session/ai_history_loader.dart`: `_finishIncremental` and `_subagentAttachmentsFor` consume suffix helpers.
- `client/test/services/conversation_timeline/timeline_merge_test.dart`
- `client/test/services/session/session_history_pagination_test.dart`
- `client/test/services/session/ai_history_incremental_test.dart`

---

### Task 1: Cheap message equality on the live hot path

**Files:**
- Modify: `client/packages/ai_message_core/lib/src/message_content_identity.dart`
- Modify: `client/packages/ai_message_core/test/message_content_identity_test.dart`
- Modify: `client/lib/services/conversation_timeline/conversation_timeline.dart` (`computeCliTimelineDelta`)
- Modify: `client/lib/services/session/session_history_pagination.dart` (`_reuseUnchangedMessage`)
- Test: `client/test/services/session/session_history_pagination_test.dart`

**Interfaces:**
- Consumes: existing `AiMessage`, `AiTextPart`, `AiReasoningPart`, `AiToolCallPart`, `subagentAgentIdFromPart`.
- Produces:
  - `bool cheapStringEqual(String a, String b)`
  - `bool messagesCheapEqual(AiMessage a, AiMessage b)`
  - Hot path call sites use `messagesCheapEqual` only (not `messageContentIdentity`).

- [ ] **Step 1: Write failing cheap-equality tests**

Append to `client/packages/ai_message_core/test/message_content_identity_test.dart`:

```dart
  test('cheapStringEqual uses full compare at or under 128 chars', () {
    expect(cheapStringEqual('a' * 64 + 'MID' + 'b' * 61, 'a' * 64 + 'XXX' + 'b' * 61),
        isFalse);
  });

  test('cheapStringEqual ignores middle of strings longer than 128', () {
    final a = 'h' * 64 + 'AAAA' + 't' * 64;
    final b = 'h' * 64 + 'BBBB' + 't' * 64;
    expect(a.length, greaterThan(128));
    expect(cheapStringEqual(a, b), isTrue);
  });

  test('messagesCheapEqual matches large tool results by length and head/tail', () {
    final result = 'HEAD'.padRight(64, 'H') + ('x' * 8000) + 'TAIL'.padLeft(64, 'T');
    final a = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [
        AiToolCallPart(
          toolCallId: 't1',
          toolName: 'Bash',
          result: result,
          status: AiToolCallStatus.complete,
        ),
      ],
    );
    final b = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [
        AiToolCallPart(
          toolCallId: 't1',
          toolName: 'Bash',
          result: StringBuffer(result).toString(),
          status: AiToolCallStatus.complete,
        ),
      ],
    );
    expect(identical(a, b), isFalse);
    expect(messagesCheapEqual(a, b), isTrue);
    expect(
      messagesCheapEqual(
        a,
        AiMessage(
          id: 'm',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Bash',
              result: '${result}!',
              status: AiToolCallStatus.complete,
            ),
          ],
        ),
      ),
      isFalse,
    );
  });

  test('messagesCheapEqual treats streaming text append as different', () {
    const a = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'hello')],
    );
    const b = AiMessage(
      id: 'm',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'hello world')],
    );
    expect(messagesCheapEqual(a, b), isFalse);
  });

  test('messagesCheapEqual ignores tool category', () {
    const base = AiToolCallPart(toolCallId: '1', toolName: 'bash');
    final other = base.copyWith(category: AiToolCallCategory.command);
    const m1 = AiMessage(id: 'm', role: AiRole.assistant, parts: [base]);
    final m2 = AiMessage(id: 'm', role: AiRole.assistant, parts: [other]);
    expect(messagesCheapEqual(m1, m2), isTrue);
  });
```

Add to `client/test/services/session/session_history_pagination_test.dart`:

```dart
  test('reuseHistoryMessageIdentity uses cheap equality for large tool results', () {
    final result = 'HEAD'.padRight(64, 'H') + ('x' * 4000) + 'TAIL'.padLeft(64, 'T');
    AiMessage tool(String payload) => AiMessage(
          id: 'a',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Bash',
              result: payload,
              status: AiToolCallStatus.complete,
            ),
          ],
        );
    final previous = [tool(result)];
    final next = [tool(StringBuffer(result).toString())];
    final reused = reuseHistoryMessageIdentity(previous: previous, next: next);
    expect(identical(reused.single, previous.single), isTrue);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client/packages/ai_message_core && dart test test/message_content_identity_test.dart
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/services/session/session_history_pagination_test.dart --name 'large tool results'
```

Expected: FAIL because `cheapStringEqual` / `messagesCheapEqual` are undefined.

- [ ] **Step 3: Implement cheap equality and switch hot-path call sites**

In `message_content_identity.dart`, keep `messageContentIdentity` as-is. Add:

```dart
bool cheapStringEqual(String a, String b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  if (a.length <= 128) return a == b;
  return a.substring(0, 64) == b.substring(0, 64) &&
      a.substring(a.length - 64) == b.substring(b.length - 64);
}

String _toolResultText(Object? result) =>
    result is String ? result : (result?.toString() ?? '');

bool _toolCallsCheapEqual(AiToolCallPart a, AiToolCallPart b) {
  if (a.toolCallId != b.toolCallId ||
      a.toolName != b.toolName ||
      a.status != b.status ||
      a.isError != b.isError ||
      subagentAgentIdFromPart(a) != subagentAgentIdFromPart(b)) {
    return false;
  }
  final aArgsText = a.argsText ?? '';
  final bArgsText = b.argsText ?? '';
  if (a.argsText != null || b.argsText != null) {
    if (!cheapStringEqual(aArgsText, bArgsText)) return false;
  } else if ((a.args?.length ?? 0) != (b.args?.length ?? 0)) {
    return false;
  }
  return cheapStringEqual(_toolResultText(a.result), _toolResultText(b.result));
}

bool messagesCheapEqual(AiMessage a, AiMessage b) {
  if (identical(a, b)) return true;
  if (a.id != b.id ||
      a.role != b.role ||
      a.status != b.status ||
      a.deliveryChannel != b.deliveryChannel ||
      a.parts.length != b.parts.length) {
    return false;
  }
  for (var i = 0; i < a.parts.length; i++) {
    final pa = a.parts[i];
    final pb = b.parts[i];
    if (pa.runtimeType != pb.runtimeType) return false;
    switch (pa) {
      case AiTextPart(:final text):
        if (!cheapStringEqual(text, (pb as AiTextPart).text)) return false;
      case AiReasoningPart(:final text):
        if (!cheapStringEqual(text, (pb as AiReasoningPart).text)) return false;
      case AiToolCallPart():
        if (!_toolCallsCheapEqual(pa, pb as AiToolCallPart)) return false;
    }
  }
  return true;
}
```

Import `subagent_attachment.dart` from this file (same package). Do not `jsonEncode` maps.

In `computeCliTimelineDelta`, replace both `messageContentIdentity(...)` comparisons with `messagesCheapEqual(previous[i], next[i])`. Remove the unused identity import if it becomes unused in that file (the library already exports it via `ai_message_core`).

In `session_history_pagination.dart`, change `_reuseUnchangedMessage` to:

```dart
  if (messagesCheapEqual(previous, next)) {
    return previous;
  }
```

Remove the `messageContentIdentity` import usage from that file.

- [ ] **Step 4: Run focused tests**

```bash
cd client/packages/ai_message_core && dart test test/message_content_identity_test.dart
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/services/session/session_history_pagination_test.dart \
  test/services/conversation_timeline/timeline_merge_test.dart
```

Expected: PASS. Existing last-replaced tests still pass because short strings use full `==`.

- [ ] **Step 5: Commit**

```bash
git add \
  client/packages/ai_message_core/lib/src/message_content_identity.dart \
  client/packages/ai_message_core/test/message_content_identity_test.dart \
  client/lib/services/conversation_timeline/conversation_timeline.dart \
  client/lib/services/session/session_history_pagination.dart \
  client/test/services/session/session_history_pagination_test.dart
git commit -m "$(cat <<'EOF'
perf(history): compare live ticks without full content fingerprints

EOF
)"
```

---

### Task 2: Incremental last-replace plus append (no hot-path full merge)

**Files:**
- Modify: `client/lib/services/conversation_timeline/timeline_merge.dart`
- Modify: `client/lib/services/conversation_timeline/conversation_timeline.dart`
- Test: `client/test/services/conversation_timeline/timeline_merge_test.dart`

**Interfaces:**
- Consumes: `messagesCheapEqual` from Task 1; existing `_insertIndexForEvent` / `_messageFromEvent`.
- Produces:
  - `class CliTimelineLastReplacedAndAppended extends CliTimelineDelta { final AiMessage message; final List<TimelineEvent> events; }`
  - `computeCliTimelineDelta`: last content change + longer list → that delta (not `Invalidated`)
  - `mergeTimelineIncremental({ required SeatTimelineSnapshot previous, required CliTimelineDelta cliDelta, required MailboxTimelineDelta mailboxDelta, required List<UnreadUserMail> unread, required List<AiMessage> nextCliMessages, required List<TimelineEvent> mailboxEvents })` — **remove** `allEvents`
  - Full `mergeTimeline` only for `Invalidated` or duplicate-id / missing-replace-id fallback, building CLI events internally from `nextCliMessages`

- [ ] **Step 1: Write failing tests for combined delta and mailbox last-replace**

Add to `timeline_merge_test.dart` (reuse the existing `cliEvent` / `mailboxEvent` helpers):

```dart
    test('last grow plus new message is LastReplacedAndAppended', () {
      final first = AiMessage(
        id: 'u',
        role: AiRole.user,
        parts: [AiTextPart(text: 'q')],
      );
      final a1 = AiMessage(
        id: 'a',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'h')],
      );
      final a2 = AiMessage(
        id: 'a',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hello')],
      );
      final extra = AiMessage(
        id: 'a2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'next')],
      );

      final delta = computeCliTimelineDelta(
        previous: [first, a1],
        next: [first, a2, extra],
      );

      expect(delta, isA<CliTimelineLastReplacedAndAppended>());
      final combined = delta as CliTimelineLastReplacedAndAppended;
      expect(identical(combined.message, a2), isTrue);
      expect(combined.events.single.id, 'a2');
    });

    test('LastReplacedAndAppended keeps prefix instances', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);
      final t3 = DateTime.utc(2026, 1, 1, 12);
      final initialEvents = [
        cliEvent(id: 'cli-1', text: 'first', createdAt: t1, cliOrder: 0),
        cliEvent(
          id: 'cli-2',
          text: 'h',
          createdAt: t2,
          cliOrder: 1,
          role: AiRole.assistant,
        ),
      ];
      final initial = mergeTimeline(events: initialEvents, unread: const []);
      final previous = SeatTimelineSnapshot(
        cliMessages: initial.messages,
        mailboxRecords: const [],
        snapshot: initial,
      );
      final nextLast = AiMessage(
        id: 'cli-2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hello')],
        createdAt: t2,
      );
      final appended = cliEvent(
        id: 'cli-3',
        text: 'third',
        createdAt: t3,
        cliOrder: 2,
        role: AiRole.assistant,
      );
      final nextCli = [
        initial.messages[0],
        nextLast,
        AiMessage(
          id: 'cli-3',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'third')],
          createdAt: t3,
        ),
      ];
      final merged = mergeTimelineIncremental(
        previous: previous,
        cliDelta: CliTimelineLastReplacedAndAppended(
          message: nextLast,
          events: [appended],
        ),
        mailboxDelta: const MailboxTimelineUnchanged(),
        unread: const [],
        nextCliMessages: nextCli,
        mailboxEvents: const [],
      );
      expect(merged.messages.map((m) => m.id), ['cli-1', 'cli-2', 'cli-3']);
      expect(identical(merged.messages[0], initial.messages[0]), isTrue);
      expect(identical(merged.messages[1], nextLast), isTrue);
      expect(
        mergeTimeline(
          events: [...initialEvents, appended],
          unread: const [],
        ).messages.map((m) => m.id),
        merged.messages.map((m) => m.id),
      );
    });

    test('LastReplaced plus mailbox append keeps prefix instances', () {
      final t1 = DateTime.utc(2026, 1, 1, 10);
      final t2 = DateTime.utc(2026, 1, 1, 11);
      final t3 = DateTime.utc(2026, 1, 1, 12);
      final initialEvents = [
        cliEvent(id: 'cli-1', text: 'first', createdAt: t1, cliOrder: 0),
        cliEvent(
          id: 'cli-2',
          text: 'h',
          createdAt: t2,
          cliOrder: 1,
          role: AiRole.assistant,
        ),
      ];
      final initial = mergeTimeline(events: initialEvents, unread: const []);
      final previous = SeatTimelineSnapshot(
        cliMessages: initial.messages,
        mailboxRecords: const [],
        snapshot: initial,
      );
      final nextLast = AiMessage(
        id: 'cli-2',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hello')],
        createdAt: t2,
      );
      final mailbox = mailboxEvent(
        id: 'mail-1',
        text: 'mailbox user',
        createdAt: t3,
      );
      final merged = mergeTimelineIncremental(
        previous: previous,
        cliDelta: CliTimelineLastReplaced(message: nextLast),
        mailboxDelta: MailboxTimelineAppended(
          events: [mailbox],
          unread: const [],
        ),
        unread: const [],
        nextCliMessages: [initial.messages[0], nextLast],
        mailboxEvents: [mailbox],
      );
      expect(merged.messages.map((m) => m.id), [
        'cli-1',
        'cli-2',
        'mailbox:mail-1',
      ]);
      expect(identical(merged.messages[0], initial.messages[0]), isTrue);
      expect(identical(merged.messages[1], nextLast), isTrue);
    });

    test('incremental builder last-grow plus append does not rewrite prefix', () {
      final first = AiMessage(
        id: 'u',
        role: AiRole.user,
        parts: [AiTextPart(text: 'q')],
        createdAt: DateTime.utc(2026, 1, 1, 10),
      );
      final a1 = AiMessage(
        id: 'a',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'h')],
        createdAt: DateTime.utc(2026, 1, 1, 11),
      );
      final initial = buildConversationTimelineIncremental(
        cliMessages: [first, a1],
        mailboxRecords: const [],
      );
      final a2 = AiMessage(
        id: 'a',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'hello')],
        createdAt: DateTime.utc(2026, 1, 1, 11),
      );
      final extra = AiMessage(
        id: 'b',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'next')],
        createdAt: DateTime.utc(2026, 1, 1, 12),
      );
      final next = buildConversationTimelineIncremental(
        previous: initial,
        cliMessages: [first, a2, extra],
        mailboxRecords: const [],
      );
      expect(next.snapshot.messages.map((m) => m.id), ['u', 'a', 'b']);
      expect(
        identical(next.snapshot.messages[0], initial.snapshot.messages[0]),
        isTrue,
      );
      expect(
        (next.snapshot.messages[1].parts.single as AiTextPart).text,
        'hello',
      );
    });
```

Update every existing `mergeTimelineIncremental(` call in this file: drop `allEvents: ...` and add `mailboxEvents: const []` (or the mailbox events list used in that test). Keep the separate `mergeTimeline(events: allEvents, ...)` **test-side** comparisons — those are allowed.

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/services/conversation_timeline/timeline_merge_test.dart \
  --name 'LastReplacedAndAppended'
```

Expected: FAIL — type missing, and current `computeCliTimelineDelta` returns `CliTimelineInvalidated` when last content changes and the list grows.

- [ ] **Step 3: Implement delta + merge**

In `timeline_merge.dart`, after `CliTimelineLastReplaced`:

```dart
class CliTimelineLastReplacedAndAppended extends CliTimelineDelta {
  const CliTimelineLastReplacedAndAppended({
    required this.message,
    required this.events,
  });

  final AiMessage message;
  final List<TimelineEvent> events;
}
```

Replace `computeCliTimelineDelta`'s last-replaced length check:

```dart
  if (lastReplaced) {
    if (next.length == previous.length) {
      return CliTimelineLastReplaced(message: next.last);
    }
    return CliTimelineLastReplacedAndAppended(
      message: next[previous.length - 1],
      events: [
        for (var i = previous.length; i < next.length; i++)
          _cliMessageToEvent(next[i], cliOrder: i),
      ],
    );
  }
```

(`next.length < previous.length` already returned `Invalidated` at the top.)

Rewrite `mergeTimelineIncremental` to take `mailboxEvents` instead of `allEvents`. Add a private fallback:

```dart
TimelineSnapshot _fullTimelineMerge({
  required List<AiMessage> nextCliMessages,
  required List<TimelineEvent> mailboxEvents,
  required List<UnreadUserMail> unread,
}) {
  final cliEvents = [
    for (var i = 0; i < nextCliMessages.length; i++)
      TimelineEvent(
        id: nextCliMessages[i].id,
        role: nextCliMessages[i].role,
        parts: nextCliMessages[i].parts,
        createdAt: nextCliMessages[i].createdAt,
        source: 'cli',
        deliveryChannel: nextCliMessages[i].deliveryChannel,
        cliOrder: i,
      ),
  ];
  return mergeTimeline(
    events: [...cliEvents, ...mailboxEvents],
    unread: unread,
  );
}
```

Invalidated CLI or mailbox → return `_fullTimelineMerge(...)`.

Extract append insertion into a helper used by all incremental append paths:

```dart
TimelineSnapshot _tryAppendEvents({
  required List<AiMessage> messages,
  required List<TimelineEvent> newEvents,
  required List<AiMessage> nextCliMessages,
  required List<UnreadUserMail> unread,
  required List<TimelineEvent> mailboxEvents,
}) {
  if (newEvents.isEmpty) {
    return TimelineSnapshot(messages: messages, unreadUserMails: unread);
  }
  final existingIds = {for (final m in messages) m.id};
  for (final event in newEvents) {
    if (existingIds.contains(event.id)) {
      return _fullTimelineMerge(
        nextCliMessages: nextCliMessages,
        mailboxEvents: mailboxEvents,
        unread: unread,
      );
    }
  }
  final sorted = [...newEvents]..sort(_compareTimelineEvents);
  for (final event in sorted) {
    final insertAt = _insertIndexForEvent(messages, event, nextCliMessages);
    messages.insert(insertAt, _messageFromEvent(event));
  }
  return TimelineSnapshot(messages: messages, unreadUserMails: unread);
}
```

Last-replace handling:

```dart
  if (cliDelta is CliTimelineLastReplaced ||
      cliDelta is CliTimelineLastReplacedAndAppended) {
    final replaced = cliDelta is CliTimelineLastReplaced
        ? cliDelta.message
        : (cliDelta as CliTimelineLastReplacedAndAppended).message;
    final extraCli = cliDelta is CliTimelineLastReplacedAndAppended
        ? cliDelta.events
        : const <TimelineEvent>[];
    final messages = List<AiMessage>.of(previous.snapshot.messages);
    final index = messages.lastIndexWhere((m) => m.id == replaced.id);
    if (index < 0) {
      return _fullTimelineMerge(
        nextCliMessages: nextCliMessages,
        mailboxEvents: mailboxEvents,
        unread: unread,
      );
    }
    messages[index] = replaced;
    final mailboxAppend = switch (mailboxDelta) {
      MailboxTimelineAppended(:final events) => events,
      _ => const <TimelineEvent>[],
    };
    return _tryAppendEvents(
      messages: messages,
      newEvents: [...extraCli, ...mailboxAppend],
      nextCliMessages: nextCliMessages,
      unread: unread,
      mailboxEvents: mailboxEvents,
    );
  }
```

Keep the existing `CliTimelineAppended` / `MailboxTimelineAppended` path, but **delete** this checksum block and do not reintroduce it:

```dart
  final full = mergeTimeline(events: allEvents, unread: unread);
  if (full.messages.length != messages.length ||
      !_sameMessageIds(full.messages, messages)) {
    return full;
  }
```

After inserting, return `TimelineSnapshot(messages: messages, unreadUserMails: unread)` directly. Duplicate-id still falls back via `_tryAppendEvents`.

In `buildConversationTimelineIncremental`, stop allocating `allEvents`. Pass `mailbox.events` as `mailboxEvents`. Remove `skipAllEvents`.

- [ ] **Step 4: Run timeline tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/services/conversation_timeline/timeline_merge_test.dart
```

Expected: PASS, including rewrite → full merge and append identity tests.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/conversation_timeline/timeline_merge.dart \
  client/lib/services/conversation_timeline/conversation_timeline.dart \
  client/test/services/conversation_timeline/timeline_merge_test.dart
git commit -m "$(cat <<'EOF'
perf(history): keep last-replace-plus-append incremental

EOF
)"
```

---

### Task 3: Annotate and sign only the changed suffix

**Files:**
- Create: `client/lib/services/session/ai_history_incremental.dart`
- Create: `client/test/services/session/ai_history_incremental_test.dart`
- Modify: `client/lib/services/session/ai_history_loader.dart` (`_finishIncremental`, `_subagentAttachmentsFor`, full-parse signature assignment)
- Modify: `client/lib/services/ai_history/tool_call_category_annotator.dart` only if `annotateChangedSuffix` should live there — prefer the new file so the annotator stays category-only.

**Interfaces:**
- Consumes: `annotateToolCallCategories`, existing `_taskCallSignature` format.
- Produces (all top-level in `ai_history_incremental.dart`):

```dart
int identicalPrefixLength(List<AiMessage> previous, List<AiMessage> next)

List<AiMessage> annotateChangedSuffix({
  required List<AiMessage>? previous,
  required List<AiMessage> next,
  required AiToolCallCategoryResolver resolver,
})

String taskCallSignature(AiToolCallPart part)

Map<String, String> collectTaskCallSignatures(
  List<AiMessage> messages,
  Set<String> subagentToolNames, {
  int from = 0,
})

Map<String, String> updateTaskCallSignatures({
  required Map<String, String> previousSigs,
  required List<AiMessage> previousMessages,
  required List<AiMessage> nextMessages,
  required int suffixStart,
  required Set<String> subagentToolNames,
})

bool sameTaskSignatures(Map<String, String> a, Map<String, String> b)
```

`taskCallSignature` must keep the current string format: normalized status, `isError`, result length + head 64, subagent id (`AiHistoryLoader._taskCallSignature` today).

- [ ] **Step 1: Write failing helper tests**

Create `client/test/services/session/ai_history_incremental_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ai_history/tool_call_categories.dart';
import 'package:teampilot/services/session/ai_history_incremental.dart';

void main() {
  const names = {'agent', 'task'};

  AiMessage user(String id) => AiMessage(
        id: id,
        role: AiRole.user,
        parts: const [AiTextPart(text: 'q')],
      );

  AiMessage agentCall(String id, String result) => AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: id,
            toolName: 'agent',
            result: result,
            status: AiToolCallStatus.complete,
          ),
        ],
      );

  test('identicalPrefixLength stops at first new instance', () {
    final a = user('u');
    final b = agentCall('t1', 'old');
    final nextLast = agentCall('t1', 'new');
    expect(identicalPrefixLength([a, b], [a, nextLast]), 1);
    expect(identicalPrefixLength([a, b], [a, b, user('u2')]), 2);
  });

  test('annotateChangedSuffix keeps prefix instances', () {
    final prefix = user('u');
    final unannotated = AiMessage(
      id: 'a',
      role: AiRole.assistant,
      parts: const [AiToolCallPart(toolCallId: '1', toolName: 'Bash')],
    );
    final previous = [prefix];
    final next = [prefix, unannotated];
    final out = annotateChangedSuffix(
      previous: previous,
      next: next,
      resolver: defaultToolCallCategoryResolver,
    );
    expect(identical(out[0], prefix), isTrue);
    expect(
      (out[1].parts.single as AiToolCallPart).category,
      AiToolCallCategory.command,
    );
  });

  test('updateTaskCallSignatures does not drop prefix ids', () {
    final prefix = agentCall('keep', 'p');
    final oldLast = agentCall('gone', 'g');
    final newLast = agentCall('new', 'n');
    final previousSigs = collectTaskCallSignatures(
      [prefix, oldLast],
      names,
    );
    final updated = updateTaskCallSignatures(
      previousSigs: previousSigs,
      previousMessages: [prefix, oldLast],
      nextMessages: [prefix, newLast],
      suffixStart: 1,
      subagentToolNames: names,
    );
    expect(updated['keep'], previousSigs['keep']);
    expect(updated.containsKey('gone'), isFalse);
    expect(updated.containsKey('new'), isTrue);
  });

  test('updateTaskCallSignatures refreshes last-message result growth', () {
    final prefix = user('u');
    final oldLast = agentCall('t1', 'abc');
    final newLast = agentCall('t1', 'abcd');
    final previousSigs = collectTaskCallSignatures(
      [prefix, oldLast],
      names,
    );
    final updated = updateTaskCallSignatures(
      previousSigs: previousSigs,
      previousMessages: [prefix, oldLast],
      nextMessages: [prefix, newLast],
      suffixStart: 1,
      subagentToolNames: names,
    );
    expect(updated['t1'], isNot(previousSigs['t1']));
  });

  test('shorter next list uses full collect, not suffix update', () {
    final a = agentCall('t1', 'a');
    final b = agentCall('t2', 'b');
    expect(
      collectTaskCallSignatures([a], names).keys,
      ['t1'],
    );
    expect(
      collectTaskCallSignatures([a, b], names).keys.toList()..sort(),
      ['t1', 't2'],
    );
  });
}
```

- [ ] **Step 2: Run helper tests to verify they fail**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/services/session/ai_history_incremental_test.dart
```

Expected: FAIL — library missing.

- [ ] **Step 3: Implement helpers**

Create `client/lib/services/session/ai_history_incremental.dart`.

`identicalPrefixLength`: loop `i` from 0 to `min(prev,next)-1`; return first `!identical`; else return `min` length.

`annotateChangedSuffix`: if `previous == null` or `next.length < previous.length`, return `annotateToolCallCategories(next, resolver: resolver)`. Else `start = identicalPrefixLength(previous, next)`; if `start == 0` annotate all; if `start == next.length` return `next` (nothing new, already annotated); else `return [...next.sublist(0, start), ...annotateToolCallCategories(next.sublist(start), resolver: resolver)]`.

Move `taskCallSignature` verbatim from `AiHistoryLoader._taskCallSignature` (including incomplete/complete normalization and `subagentAgentIdFromPart`).

`collectTaskCallSignatures`: same loop as `_taskCallSignatures`, but start at `from`, and match `subagentToolNames` with `part.toolName.trim().toLowerCase()`.

`updateTaskCallSignatures`:

```dart
  final out = Map<String, String>.of(previousSigs);
  for (final id in collectTaskCallSignatures(
    previousMessages,
    subagentToolNames,
    from: suffixStart,
  ).keys) {
    out.remove(id);
  }
  out.addAll(
    collectTaskCallSignatures(
      nextMessages,
      subagentToolNames,
      from: suffixStart,
    ),
  );
  return out;
```

`sameTaskSignatures`: move `_sameTaskSignatures` as-is.

- [ ] **Step 4: Wire loader**

In `_finishIncremental`:

```dart
    final previous = _messages[cacheKey];
    final annotated = annotateChangedSuffix(
      previous: previous,
      next: messages,
      resolver: _categoryResolverFor(cli),
    );
    final capability = _registry.capability<AiHistoryCapability>(cli);
    Map<String, String>? suffixSigs;
    if (capability != null) {
      final names = capability.subagentToolNames;
      if (previous == null || messages.length < previous.length) {
        suffixSigs = collectTaskCallSignatures(annotated, names);
      } else {
        suffixSigs = updateTaskCallSignatures(
          previousSigs: _attachmentSigs[cacheKey] ?? const {},
          previousMessages: previous,
          nextMessages: annotated,
          suffixStart: identicalPrefixLength(previous, messages),
          subagentToolNames: names,
        );
      }
    }
    final attachments = await _subagentAttachmentsFor(
      cacheKey: cacheKey,
      cli: cli,
      ctx: ctx,
      messages: annotated,
      rootTranscriptPath: parentPath,
      cache: !indexOnly,
      currentSigs: suffixSigs,
    );
```

Keep `List<AiMessage>.of(annotated)`.

Change `_subagentAttachmentsFor` to accept `Map<String, String>? currentSigs`. When `currentSigs != null`, use it; otherwise `collectTaskCallSignatures(messages, capability.subagentToolNames)`. Replace `_sameTaskSignatures` / `_taskCallSignatures` / `_taskCallSignature` calls with the new top-level functions. Delete the private statics from the loader.

Full-parse path (`_attachmentSigs[cacheKey] = ...`) must call `collectTaskCallSignatures`.

- [ ] **Step 5: Run helper + related history tests**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test \
  test/services/session/ai_history_incremental_test.dart \
  test/services/ai_history/tool_call_category_annotator_test.dart \
  test/services/conversation_timeline/timeline_merge_test.dart \
  test/services/session/session_history_pagination_test.dart \
  test/cubits/ai_history_seat_turn_end_settle_test.dart
```

Expected: PASS.

Then:

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no issues in touched files.

- [ ] **Step 6: Commit**

```bash
git add \
  client/lib/services/session/ai_history_incremental.dart \
  client/test/services/session/ai_history_incremental_test.dart \
  client/lib/services/session/ai_history_loader.dart
git commit -m "$(cat <<'EOF'
perf(history): annotate and sign only the changed transcript suffix

EOF
)"
```

---

## Spec coverage

| Spec section | Task |
|--------------|------|
| Suffix index / annotate only suffix | Task 3 `identicalPrefixLength`, `annotateChangedSuffix` |
| Task signature suffix update; truncate full rebuild | Task 3 `updateTaskCallSignatures` / `collectTaskCallSignatures` |
| Keep `List.of` | Task 3 `_finishIncremental` |
| Drop append `mergeTimeline` checksum | Task 2 |
| `CliTimelineLastReplacedAndAppended` | Task 2 |
| LastReplaced + mailbox append incremental | Task 2 |
| `allEvents` only on invalidation | Task 2 (`mailboxEvents` + internal full merge) |
| Cheap equality; no `messageContentIdentity` on hot path | Task 1 |
| `messageContentIdentity` unchanged | Task 1 |
| Compact / prefix rewrite / shrink still full | Task 2 existing Invalidated tests; Task 3 shorter-list collect |
| Tests listed in spec §6 | Tasks 1–3 |
| No markdown / no mailbox skip / no tailer `force` change | not implemented (non-goals) |
