import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/persistence/file_bus_message_log.dart';
import 'package:teampilot/services/team_bus/team_message.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  test('serializes concurrent appendMessage and appendRead per member',
      () async {
    final fs = InMemoryFilesystem();
    final log = FileBusMessageLog(mailRoot: '/mail', fs: fs);
    const memberId = 'team-lead';
    final message = TeamMessage(
      id: 'msg-1',
      from: 'user',
      to: memberId,
      content: 'hello',
    );

    await Future.wait([
      log.appendMessage(memberId, 0, message, 100),
      log.appendRead(memberId, [0], 200),
    ]);

    final records = await log.load(memberId);
    expect(records, hasLength(1));
    expect(records.single.message.content, 'hello');
    expect(records.single.read, isTrue);

    final raw = await fs.readString('/mail/team-lead.jsonl');
    expect(raw, isNotNull);
    for (final line in raw!.split('\n')) {
      if (line.trim().isEmpty) continue;
      expect(line.startsWith('{'), isTrue,
          reason: 'each jsonl line must start with {, got: $line');
    }
  });
}
