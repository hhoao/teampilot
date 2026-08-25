import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');

  test('file store preserves records across reopening', () async {
    final fs = InMemoryFilesystem();
    final first = FilePromptDeliveryStore(root: '/runtime/deliveries', fs: fs);
    final delivery = PromptDelivery(
      id: 'd1',
      seat: seat,
      cli: CliTool.codex,
      text: '  hello\nworld ',
      normalizedText: 'hello world',
      promptEpoch: 3,
      state: PromptDeliveryState.staged,
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25, 1),
    );

    await first.save(delivery);
    final reopened = FilePromptDeliveryStore(
      root: '/runtime/deliveries',
      fs: fs,
    );

    final read = await reopened.read('d1');
    expect(read?.text, '  hello\nworld ');
    expect(read?.normalizedText, 'hello world');
    expect(read?.promptEpoch, 3);
    expect((await reopened.activeFor(seat)).single.id, 'd1');
  });
}
