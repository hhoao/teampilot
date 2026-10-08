import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_list_entry.dart';
import 'package:teampilot/repositories/session_list_index_store.dart';
import 'package:teampilot/repositories/session_repository_fs.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('session_list_index_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SessionListIndexStore store() => SessionListIndexStore(
    SessionRepositoryFs(teampilotRoot: tmp.path, fs: LocalFilesystem()),
    'ws-1',
  );

  SessionListEntry entry(String id) =>
      SessionListEntry(sessionId: id, display: id, createdAt: 1, updatedAt: 1);

  test('tryRead returns null when missing and writeAll round-trips', () async {
    final s = store();
    expect(await s.tryRead(), isNull);
    await s.writeAll([entry('a'), entry('b')]);
    final read = await s.tryRead();
    expect(read!.map((e) => e.sessionId), ['a', 'b']);
  });

  test('upsert inserts then replaces by sessionId', () async {
    final s = store();
    await s.upsert(entry('a'));
    await s.upsert(
      SessionListEntry(sessionId: 'a', display: 'renamed', createdAt: 1),
    );
    final read = await s.tryRead();
    expect(read, hasLength(1));
    expect(read!.single.display, 'renamed');
  });

  test('remove drops the id; unknown version is treated as missing', () async {
    final s = store();
    await s.writeAll([entry('a'), entry('b')]);
    await s.remove('a');
    expect((await s.tryRead())!.map((e) => e.sessionId), ['b']);
    final fs = SessionRepositoryFs(
      teampilotRoot: tmp.path,
      fs: LocalFilesystem(),
    );
    await File(
      fs.layout.sessionsIndexFile('ws-1'),
    ).writeAsString('{"version": 99, "sessions": []}');
    expect(await s.tryRead(), isNull);
  });
}
