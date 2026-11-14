import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';

import '../../support/in_memory_filesystem.dart';

/// [InMemoryFilesystem] whose reads throw while [failRead] is set.
final class _FlakyReadFilesystem extends InMemoryFilesystem {
  bool failRead = false;

  @override
  Future<String?> readString(String path) async {
    if (failRead) throw StateError('read failed for $path');
    return super.readString(path);
  }
}

/// Counts reads so a test can prove concurrent loads share one read.
final class _CountingReadFilesystem extends InMemoryFilesystem {
  int reads = 0;

  @override
  Future<String?> readString(String path) {
    reads++;
    return super.readString(path);
  }
}

String _cursorFile({
  Map<String, Map<String, Object?>> cursors = const {},
  List<String> seenEventIds = const [],
}) => const JsonEncoder.withIndent(
  '  ',
).convert({'version': 1, 'cursors': cursors, 'seenEventIds': seenEventIds});

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

  test(
    'a failed load does not let the next write clobber disk state',
    () async {
      final fs = _FlakyReadFilesystem()..failRead = true;
      const path = '/tp/attention/cursors.json';
      final original = _cursorFile(
        cursors: {
          'ssh:p1': {'authorityId': 'desk', 'epoch': 3, 'seq': 4},
        },
        seenEventIds: ['e-old'],
      );
      fs.files[path] = original;

      final store = AttentionCursorStore(fs: fs, path: path);
      await store.load();
      expect(store.cursorFor('ssh:p1'), isNull);
      expect(store.hasSeen('e-old'), isFalse);

      await store.remember(
        'local',
        const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
        ['e-new'],
      );
      // The queued save retried the read, failed again, and must not write.
      expect(fs.files[path], original);

      fs.failRead = false;
      await store.load();
      await store.remember(
        'local',
        const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 2),
        const [],
      );

      final saved = jsonDecode(fs.files[path]!) as Map;
      final cursors = saved['cursors'] as Map;
      expect(cursors['ssh:p1'], isA<Map>());
      expect((cursors['local'] as Map)['seq'], 2);
      expect(saved['seenEventIds'], containsAll(['e-old', 'e-new']));
      expect(store.cursorFor('ssh:p1')?.seq, 4);
    },
  );

  test('loading caps an oversized legacy seen event id list', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/attention/cursors.json';
    fs.files[path] = _cursorFile(seenEventIds: ['e1', 'e2', 'e3', 'e4', 'e5']);

    final store = AttentionCursorStore(fs: fs, path: path, maxSeenEventIds: 3);
    await store.load();

    // Oldest ids are dropped, newest kept.
    expect(store.hasSeen('e1'), isFalse);
    expect(store.hasSeen('e2'), isFalse);
    expect(store.hasSeen('e3'), isTrue);
    expect(store.hasSeen('e4'), isTrue);
    expect(store.hasSeen('e5'), isTrue);
  });

  test(
    'clearing before the first load is not undone by the lazy load',
    () async {
      final fs = InMemoryFilesystem();
      const path = '/tp/attention/cursors.json';
      fs.files[path] = _cursorFile(
        cursors: {
          'local': {'authorityId': 'desk', 'epoch': 7, 'seq': 4},
          'ssh:p1': {'authorityId': 'desk', 'epoch': 7, 'seq': 5},
        },
      );

      final store = AttentionCursorStore(fs: fs, path: path);
      await store.clearCursor('local');

      expect(store.cursorFor('local'), isNull);
      expect(store.cursorFor('ssh:p1')?.seq, 5);

      final reloaded = AttentionCursorStore(fs: fs, path: path);
      await reloaded.load();

      expect(reloaded.cursorFor('local'), isNull);
      expect(reloaded.cursorFor('ssh:p1')?.seq, 5);
    },
  );

  test('a cleared cursor stays gone after reload', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/attention/cursors.json';
    final first = AttentionCursorStore(fs: fs, path: path);
    await first.load();
    await first.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
      const [],
    );
    await first.clearCursor('local');
    expect(first.cursorFor('local'), isNull);

    final second = AttentionCursorStore(fs: fs, path: path);
    await second.load();

    expect(second.cursorFor('local'), isNull);
  });

  test('a corrupt cursor file self-heals on the next write', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/attention/cursors.json';
    fs.files[path] = 'not json';

    final store = AttentionCursorStore(fs: fs, path: path);
    await store.load();
    expect(store.cursorFor('local'), isNull);

    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 4),
      ['e4'],
    );

    final saved = jsonDecode(fs.files[path]!) as Map;
    final cursors = saved['cursors'] as Map;
    expect((cursors['local'] as Map)['seq'], 4);
    expect(saved['seenEventIds'], ['e4']);
  });

  test('rejects a non-positive seen event id cap', () {
    expect(
      () => AttentionCursorStore(maxSeenEventIds: 0),
      throwsA(isA<AssertionError>()),
    );
  });

  test('concurrent load callers share one read', () async {
    final fs = _CountingReadFilesystem();
    const path = '/tp/attention/cursors.json';
    fs.files[path] = _cursorFile(
      cursors: {
        'local': {'authorityId': 'desk', 'epoch': 7, 'seq': 5},
      },
      seenEventIds: ['e5'],
    );

    final store = AttentionCursorStore(fs: fs, path: path);
    await Future.wait([store.load(), store.load()]);

    expect(fs.reads, 1);
    expect(store.cursorFor('local')?.seq, 5);
    expect(store.hasSeen('e5'), isTrue);
  });
}
