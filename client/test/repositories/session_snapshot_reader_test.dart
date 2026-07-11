import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/session_snapshot_reader.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('session_snapshot_reader_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void writeSession(String id, Map<String, Object?> json) {
    final dir = Directory(p.join(tmp.path, id))..createSync();
    File(p.join(dir.path, 'session.json')).writeAsStringSync(jsonEncode(json));
  }

  test('readSessionMaps returns decoded session maps', () async {
    writeSession('s1', {
      'sessionId': 's1',
      'workspaceId': 'ws',
      'sessionTeam': '',
      'createdAt': 1,
      'updatedAt': 1,
    });
    writeSession('s2', {
      'sessionId': 's2',
      'workspaceId': 'ws',
      'sessionTeam': 'default-native-team',
      'createdAt': 1,
      'updatedAt': 1,
    });

    final maps = await SessionSnapshotReader.readSessionMaps(tmp.path);
    expect(maps.map((m) => m['sessionId']).toSet(), {'s1', 's2'});
  });

  test('readSessionMapsSync matches async entry point', () {
    writeSession('s3', {
      'sessionId': 's3',
      'workspaceId': 'ws',
      'sessionTeam': '',
      'createdAt': 1,
      'updatedAt': 1,
    });

    expect(
      SessionSnapshotReader.readSessionMapsSync(tmp.path).single['sessionId'],
      's3',
    );
  });
}
