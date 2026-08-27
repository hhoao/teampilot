import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/services/session/failed_message_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  group('FailedMessageRecord', () {
    test('round-trips its JSON representation', () {
      final record = FailedMessageRecord(
        id: 'message-1',
        text: 'Please try again',
        createdAt: DateTime.utc(2026, 8, 27, 10, 30),
        status: FailedMessageStatus.failed,
      );

      expect(FailedMessageRecord.fromJson(record.toJson()), record);
    });

    test('copies status through delivery transitions', () {
      final sending = FailedMessageRecord(
        id: 'message-1',
        text: 'Please try again',
        createdAt: DateTime.utc(2026, 8, 27, 10, 30),
      );

      expect(
        sending
            .copyWith(status: FailedMessageStatus.failed)
            .copyWith(status: FailedMessageStatus.sent)
            .status,
        FailedMessageStatus.sent,
      );
    });
  });

  group('FailedMessageStore', () {
    late InMemoryFilesystem fs;
    late FailedMessageStore store;

    setUp(() {
      fs = InMemoryFilesystem();
      store = FailedMessageStore(fs: fs, rootPath: '/teampilot');
    });

    test('reloads saved records from a fresh store instance', () async {
      final record = FailedMessageRecord(
        id: 'message-1',
        text: 'Retry this prompt',
        createdAt: DateTime.utc(2026, 8, 27, 10, 30),
        status: FailedMessageStatus.failed,
      );

      await store.save('workspace-1', 'session-1', record);

      final reloaded = FailedMessageStore(fs: fs, rootPath: '/teampilot');
      expect(await reloaded.load('workspace-1', 'session-1'), [record]);
    });

    test('updates a saved record status', () async {
      final sending = FailedMessageRecord(
        id: 'message-1',
        text: 'Retry this prompt',
        createdAt: DateTime.utc(2026, 8, 27, 10, 30),
      );

      await store.save('workspace-1', 'session-1', sending);
      await store.save(
        'workspace-1',
        'session-1',
        sending.copyWith(status: FailedMessageStatus.failed),
      );

      expect(
        (await store.load('workspace-1', 'session-1')).single.status,
        FailedMessageStatus.failed,
      );
    });

    test('keeps records isolated to their session directory', () async {
      final first = FailedMessageRecord(
        id: 'message-1',
        text: 'First session prompt',
        createdAt: DateTime.utc(2026, 8, 27, 10, 30),
      );
      final second = FailedMessageRecord(
        id: 'message-2',
        text: 'Second session prompt',
        createdAt: DateTime.utc(2026, 8, 27, 10, 31),
      );

      await store.save('workspace-1', 'session-1', first);
      await store.save('workspace-1', 'session-2', second);

      expect(await store.load('workspace-1', 'session-1'), [first]);
      expect(await store.load('workspace-1', 'session-2'), [second]);
      expect(
        jsonDecode(
          fs.files['/teampilot/workspace/workspaces/workspace-1/sessions/'
              'session-1/failed-messages.json']!,
        ),
        isA<Map>(),
      );
    });
  });
}
