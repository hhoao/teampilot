import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/history/history_isolate_transport.dart';

void main() {
  test('transfer bundle materializes ordered fragment bytes and hints', () {
    final source = AiTranscriptBundle(
      adapterId: 'claude',
      hints: const {'path': '/tmp/a.jsonl'},
      fragments: [
        AiTranscriptFragment(name: 'a', bytes: [1, 2]),
        AiTranscriptFragment(name: 'b', bytes: [3, 4, 5]),
      ],
    );

    final restored = HistoryTransferBundle.fromBundle(source).materialize();

    expect(restored.adapterId, 'claude');
    expect(restored.hints, const {'path': '/tmp/a.jsonl'});
    expect(restored.fragments.map((f) => f.name), ['a', 'b']);
    expect(restored.fragments.map((f) => f.bytes), [
      [1, 2],
      [3, 4, 5],
    ]);
  });
}
