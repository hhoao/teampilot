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
    final entries = buildChatOutline([
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
    ], emptyPreview: 'Empty message');
    expect(entries[0].preview, 'hello world');
    expect(entries[1].preview, 'alpha beta');
    expect(entries[1].preview.contains('bash'), isFalse);
    expect(entries[2].preview.length, kChatOutlinePreviewLimit);
    expect(entries[2].preview, long.substring(0, kChatOutlinePreviewLimit));
  });

  test('empty text uses injected placeholder', () {
    final entries = buildChatOutline([
      const AiMessage(id: 'u0', role: AiRole.user, parts: []),
      _user('u1', '   '),
    ], emptyPreview: 'Empty message');
    expect(entries[0].preview, 'Empty message');
    expect(entries[1].preview, 'Empty message');
  });

  test('no-op rebuild reuses previous list identity', () {
    final messages = [_user('u0', 'a'), _assistant('a0', 'x')];
    final previous = buildChatOutline(messages, emptyPreview: 'Empty message');
    final next = buildChatOutline(
      messages,
      emptyPreview: 'Empty message',
      previous: previous,
    );
    expect(identical(next, previous), isTrue);
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
