import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/ai_history_message_dedup.dart';

AiMessage _msg(
  String id, {
  AiRole role = AiRole.assistant,
  List<String> texts = const [],
  List<AiToolCallPart> tools = const [],
  List<String> reasoning = const [],
}) {
  return AiMessage(
    id: id,
    role: role,
    parts: [
      for (final t in texts) AiTextPart(text: t),
      for (final r in reasoning) AiReasoningPart(text: r),
      ...tools,
    ],
  );
}

AiToolCallPart _tool(
  String callId, {
  Object? result,
  String name = 'question',
}) {
  return AiToolCallPart(
    toolCallId: callId,
    toolName: name,
    status: result == null
        ? AiToolCallStatus.incomplete
        : AiToolCallStatus.complete,
    result: result,
  );
}

void main() {
  test('same id twice keeps the last occurrence', () {
    final pending = _msg('asst-1', texts: ['prose'], tools: [_tool('c1')]);
    final completed = _msg(
      'asst-1',
      texts: ['prose'],
      tools: [_tool('c1', result: 'answer')],
    );
    final result = dedupeAiHistoryMessages([pending, completed]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-1');
    expect(
      (result.messages.single.parts.whereType<AiToolCallPart>().single).result,
      'answer',
      reason: '同 id 保留最后一次（内容最新）',
    );
    expect(result.removed, [pending]);
  });

  test('same text, different ids, tool result asymmetry keeps the completed one',
      () {
    final pending = _msg('asst-a', texts: ['prose'], tools: [_tool('c1')]);
    final completed = _msg(
      'asst-b',
      texts: ['prose'],
      tools: [_tool('c1', result: 'answer')],
    );
    final result = dedupeAiHistoryMessages([pending, completed]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-b');
    expect(result.removed, [pending]);
  });

  test('same text, different ids, part superset keeps the larger message', () {
    final small = _msg(
      'asst-a',
      texts: ['prose'],
      reasoning: ['r1'],
      tools: [_tool('c1', result: 'o1')],
    );
    final large = _msg(
      'asst-b',
      texts: ['prose'],
      reasoning: ['r1', 'r2'],
      tools: [_tool('c1', result: 'o1'), _tool('c2', result: 'o2')],
    );
    final result = dedupeAiHistoryMessages([small, large]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-b');
    expect(result.removed, [small]);
  });

  test('completely identical assistant messages keep the first', () {
    final a = _msg('asst-a', texts: ['prose'], tools: [_tool('c1')]);
    final b = _msg('asst-b', texts: ['prose'], tools: [_tool('c1')]);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-a');
    expect(result.removed, [b]);
  });

  test('legitimate duplicate USER messages are kept', () {
    final a = _msg(
      'u1',
      role: AiRole.user,
      texts: ['没问题'],
    );
    final b = _msg(
      'u2',
      role: AiRole.user,
      texts: ['没问题'],
    );
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });

  test('tool-only assistant messages are never deduped (empty text signature)',
      () {
    final a = _msg('asst-a', tools: [_tool('c1')]);
    final b = _msg('asst-b', tools: [_tool('c2')]);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });

  test('messages with different text parts are kept', () {
    final a = _msg('asst-a', texts: ['prose one']);
    final b = _msg('asst-b', texts: ['prose two']);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });

  test('same text, equal results, no superset keeps both and reports the pair',
      () {
    final a = _msg(
      'asst-a',
      texts: ['prose'],
      tools: [_tool('c1', result: 'o1')],
    );
    final b = _msg(
      'asst-b',
      texts: ['prose'],
      tools: [_tool('c2', result: 'o2')],
    );
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
    expect(result.undecidedPairs, hasLength(1));
    expect(
      result.undecidedPairs.single.$1.id,
      'asst-a',
      reason: 'pair 按原列表顺序（前一条在 \$1）',
    );
    expect(result.undecidedPairs.single.$2.id, 'asst-b');
  });

  test('resolved pair reports no undecided pairs', () {
    final pending = _msg('asst-a', texts: ['prose'], tools: [_tool('c1')]);
    final completed = _msg(
      'asst-b',
      texts: ['prose'],
      tools: [_tool('c1', result: 'answer')],
    );
    final result = dedupeAiHistoryMessages([pending, completed]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-b');
    expect(result.undecidedPairs, isEmpty);
  });

  test('3+ group records each undecided unordered pair once', () {
    final a = _msg(
      'asst-a',
      texts: ['prose'],
      tools: [_tool('c1', result: 'o1')],
    );
    final b = _msg(
      'asst-b',
      texts: ['prose'],
      tools: [_tool('c2', result: 'o2')],
    );
    final c = _msg(
      'asst-c',
      texts: ['prose'],
      tools: [_tool('c3', result: 'o3')],
    );
    final result = dedupeAiHistoryMessages([a, b, c]);

    expect(result.messages, hasLength(3));
    expect(result.removed, isEmpty);
    expect(
      result.undecidedPairs.map((p) => '${p.$1.id},${p.$2.id}').toList(),
      ['asst-a,asst-b', 'asst-a,asst-c', 'asst-b,asst-c'],
      reason: '每组无序对只记录一次，按原列表顺序',
    );
  });
}
