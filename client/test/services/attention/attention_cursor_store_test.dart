import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('remembers cursors and caps the seen event id list', () async {
    final fs = InMemoryFilesystem();
    final store = AttentionCursorStore(
      fs: fs,
      path: '/tp/attention/cursors.json',
      maxSeenEventIds: 2,
    );
    await store.load();

    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 2),
      ['e1', 'e2'],
    );
    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 3),
      ['e3'],
    );

    expect(store.cursorFor('local')?.seq, 3);
    expect(store.hasSeen('e1'), isFalse);
    expect(store.hasSeen('e2'), isTrue);
    expect(store.hasSeen('e3'), isTrue);
    expect(fs.files['/tp/attention/cursors.json'], contains('"seq": 3'));
  });

  test('reloads cursors from disk', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/cursors.json';
    final first = AttentionCursorStore(fs: fs, path: path);
    await first.load();
    await first.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 9),
      ['e9'],
    );

    final second = AttentionCursorStore(fs: fs, path: path);
    await second.load();

    expect(second.cursorFor('local')?.seq, 9);
    expect(second.hasSeen('e9'), isTrue);
  });

  test('clearCursor removes only that home', () async {
    final fs = InMemoryFilesystem();
    final store = AttentionCursorStore(
      fs: fs,
      path: '/tp/attention/cursors.json',
    );
    await store.load();
    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
      const [],
    );
    await store.remember(
      'ssh:p1',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 2),
      const [],
    );

    await store.clearCursor('local');

    expect(store.cursorFor('local'), isNull);
    expect(store.cursorFor('ssh:p1')?.seq, 2);
  });
}
