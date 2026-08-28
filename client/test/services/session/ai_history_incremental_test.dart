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
    final previousSigs = collectTaskCallSignatures([prefix, oldLast], names);
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
    final previousSigs = collectTaskCallSignatures([prefix, oldLast], names);
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
    expect(collectTaskCallSignatures([a], names).keys, ['t1']);
    expect(collectTaskCallSignatures([a, b], names).keys.toList()..sort(), [
      't1',
      't2',
    ]);
  });
}
