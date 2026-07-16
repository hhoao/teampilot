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

  test('reuseTurnsIfSameMembership returns identical previous list', () {
    final msgs = [user('u1', 'hi'), asst('a1', 'yo')];
    final previous = buildTurns(msgs);
    final reused = reuseTurnsIfSameMembership(
      previous: previous,
      messages: msgs,
    );
    expect(identical(reused, previous), isTrue);
  });

  test('reuseTurnsIfSameMembership returns new list when membership changes', () {
    final previous = buildTurns([user('u1', 'hi'), asst('a1', 'yo')]);
    final next = reuseTurnsIfSameMembership(
      previous: previous,
      messages: [user('u1', 'hi'), asst('a1', 'yo'), asst('a2', 'more')],
    );
    expect(identical(next, previous), isFalse);
    expect(next.single.messageIds, ['u1', 'a1', 'a2']);
  });

  test('messageContentIdentity changes when tool args change', () {
    AiMessage tool(Map<String, Object?> args) => AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [
        AiToolCallPart(
          toolCallId: 'tc1',
          toolName: 'search',
          args: args,
        ),
      ],
    );
    final a = tool({'q': 'hi'});
    final b = tool({'q': 'bye'});
    expect(messageContentIdentity(a), isNot(messageContentIdentity(b)));
  });
}
