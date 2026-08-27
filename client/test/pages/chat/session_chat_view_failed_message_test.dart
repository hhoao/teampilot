import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/failed_message_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late FailedMessageStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    store = FailedMessageStore(fs: fs, rootPath: '/teampilot');
  });

  AiHistorySeat seat() => AiHistorySeat(
    loader: AiHistoryLoader(
      resolveWorkContext: (_, {String? memberId}) async =>
          throw UnimplementedError(),
    ),
  );

  test('persists a sending bubble before compose delivery clears', () async {
    final history = seat();

    final record = await history.persistPendingUser(
      store: store,
      workspaceId: 'workspace-a',
      sessionId: 'session-a',
      text: 'keep this visible',
    );

    expect(await store.load('workspace-a', 'session-a'), [record]);
    expect(history.runtime.messages.single.id, record.id);
    expect(
      history.pendingDeliveryStatusFor(record.id),
      FailedMessageStatus.sending,
    );
  });

  test('hydrates a failed bubble into a fresh history seat', () async {
    final record = FailedMessageRecord(
      id: 'failed-1',
      text: 'restore this',
      createdAt: DateTime.utc(2026),
      status: FailedMessageStatus.failed,
    );
    await store.save('workspace-a', 'session-a', record);
    final history = seat();

    await history.hydratePendingUsers(
      store: store,
      workspaceId: 'workspace-a',
      sessionId: 'session-a',
    );

    expect(history.runtime.messages.single.id, record.id);
    expect(history.runtime.messages.single.parts.single, isA<AiTextPart>());
    expect(
      history.pendingDeliveryStatusFor(record.id),
      FailedMessageStatus.failed,
    );
  });

  test('does not hydrate records from another session', () async {
    await store.save(
      'workspace-a',
      'session-a',
      FailedMessageRecord(
        id: 'only-a',
        text: 'session a',
        createdAt: DateTime.utc(2026),
      ),
    );
    final history = seat();

    await history.hydratePendingUsers(
      store: store,
      workspaceId: 'workspace-a',
      sessionId: 'session-b',
    );

    expect(history.runtime.messages, isEmpty);
  });
}
