import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/shared_state/hlc.dart';
import 'package:teampilot/services/shared_state/or_set.dart';
import 'package:teampilot/services/shared_state/shared_state_document.dart';
import 'package:teampilot/services/shared_state/shared_state_store.dart';

import '../../support/in_memory_filesystem.dart';

const _path = '/tp/shared-state.json';
const _deviceA = 'a';
const _deviceB = 'b';

Object? _mergeFavorites(Object? local, Object? remote) =>
    OrSet.fromJson(local).merge(OrSet.fromJson(remote)).toJson();

OrSet _favorites(SharedStateDocument document) =>
    OrSet.fromJson(document.sections['favorites']);

SharedStateDocument _addFavorite(
  SharedStateDocument document,
  String workspaceId,
  Hlc stamp,
) => document.withSection(
  'favorites',
  _favorites(document).add(workspaceId, stamp).toJson(),
);

String Function() _revisions() {
  var next = 0;
  return () => 'r${++next}';
}

void main() {
  late SharedStateMergeRegistry registry;
  late HlcClock clock;

  setUp(() {
    registry = SharedStateMergeRegistry({'favorites': _mergeFavorites});
    clock = HlcClock(
      nodeId: _deviceA,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
    );
  });

  SharedStateStore storeOn(InMemoryFilesystem fs) => SharedStateStore(
    fs: fs,
    path: _path,
    clock: clock,
    mergeRegistry: registry,
    revisionFactory: _revisions(),
  );

  test('missing document reads as empty', () async {
    final store = storeOn(InMemoryFilesystem());

    final document = await store.read();

    expect(document.sections, isEmpty);
    expect(document.revision, isEmpty);
  });

  test('update writes a revision and the section', () async {
    final fs = InMemoryFilesystem();
    final store = storeOn(fs);

    final written = await store.update(
      (document) => _addFavorite(
        document,
        'ws1',
        const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceA),
      ),
    );

    expect(written.revision, isNotEmpty);
    final readBack = await store.read();
    expect(readBack.revision, written.revision);
    expect(_favorites(readBack).contains('ws1'), isTrue);
    expect(fs.files[_path], isNotNull);
  });

  test('a concurrent writer is detected and both changes survive', () async {
    late InMemoryFilesystem racing;
    var injected = false;
    racing = _RacingFilesystem(
      path: _path,
      onRead: (readCount, fs) {
        if (readCount != 2 || injected) return;
        injected = true;
        final other = SharedStateDocument(
          schemaVersion: 1,
          revision: 'other',
          updatedAt: const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceB),
          sections: {
            'favorites': const OrSet()
                .add(
                  'ws2',
                  const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceB),
                )
                .toJson(),
          },
        );
        fs.files[_path] = jsonEncode(other.toJson());
      },
    );
    final store = storeOn(racing);

    await store.update(
      (document) => _addFavorite(
        document,
        'ws1',
        const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceA),
      ),
    );

    final readBack = await store.read();
    expect(_favorites(readBack).contains('ws1'), isTrue);
    expect(_favorites(readBack).contains('ws2'), isTrue);
  });

  test('unknown sections are preserved through an update', () async {
    final fs = InMemoryFilesystem();
    final store = storeOn(fs);
    await store.update((document) => document.withSection('future', {'x': 1}));

    await store.update(
      (document) => _addFavorite(
        document,
        'ws1',
        const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceA),
      ),
    );

    final readBack = await store.read();
    expect(readBack.sections['future'], {'x': 1});
    expect(_favorites(readBack).contains('ws1'), isTrue);
  });

  test('corrupt documents throw instead of being overwritten', () async {
    final fs = InMemoryFilesystem()..files[_path] = 'not json';
    final store = storeOn(fs);

    expect(store.read, throwsA(isA<SharedStateFormatException>()));
  });

  test('gives up after maxAttempts with a conflict', () async {
    final racing = _RacingFilesystem(
      path: _path,
      onRead: (readCount, fs) {
        if (readCount < 2) return;
        final other = SharedStateDocument(
          schemaVersion: 1,
          revision: 'other-$readCount',
          updatedAt: Hlc(wallMillis: readCount, counter: 0, nodeId: _deviceB),
          sections: const {},
        );
        fs.files[_path] = jsonEncode(other.toJson());
      },
    );
    final store = storeOn(racing);

    expect(
      () => store.update(
        (document) => _addFavorite(
          document,
          'ws1',
          const Hlc(wallMillis: 1, counter: 0, nodeId: _deviceA),
        ),
        maxAttempts: 2,
      ),
      throwsA(isA<SharedStateConflictException>()),
    );
  });

  test('revision stamp changes on every write', () async {
    final store = storeOn(InMemoryFilesystem());

    final first = await store.update(
      (document) => document.withSection('a', 1),
    );
    final second = await store.update(
      (document) => document.withSection('b', 2),
    );

    expect(first.revision, isNot(second.revision));
    expect(second.updatedAt.compareTo(first.updatedAt), greaterThan(0));
  });
}

class _RacingFilesystem extends InMemoryFilesystem {
  _RacingFilesystem({required this.path, required this.onRead});

  final String path;
  final void Function(int readCount, _RacingFilesystem fs) onRead;
  int _reads = 0;

  @override
  Future<String?> readString(String path) async {
    if (path == this.path) {
      _reads++;
      onRead(_reads, this);
    }
    return super.readString(path);
  }
}
