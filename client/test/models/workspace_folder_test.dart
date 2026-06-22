import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';

void main() {
  test('defaults targetId to local and round-trips json', () {
    const f = WorkspaceFolder(path: '/tmp/repo');
    expect(f.targetId, 'local');
    final restored = WorkspaceFolder.fromJson(f.toJson());
    expect(restored.path, '/tmp/repo');
    expect(restored.targetId, 'local');
  });

  test('toJson always writes path and targetId', () {
    final json = const WorkspaceFolder(path: '/a', targetId: 'local').toJson();
    expect(json['path'], '/a');
    expect(json['targetId'], 'local');
  });

  test('foldersFromLegacyJson prefers new folders array', () {
    final folders = foldersFromLegacyJson({
      'folders': [
        {'path': '/a', 'targetId': 'local'},
        {'path': '/b', 'targetId': 'local'},
      ],
      'primaryPath': '/ignored',
      'additionalPaths': ['/ignored2'],
    });
    expect(folders.map((f) => f.path), ['/a', '/b']);
  });

  test('foldersFromLegacyJson upgrades legacy primaryPath + additionalPaths', () {
    final folders = foldersFromLegacyJson({
      'primaryPath': '/main',
      'additionalPaths': ['/x', '/y'],
    });
    expect(folders.map((f) => f.path), ['/main', '/x', '/y']);
    expect(folders.every((f) => f.targetId == 'local'), isTrue);
  });

  test('foldersFromLegacyJson tolerates empty primaryPath', () {
    final folders = foldersFromLegacyJson({
      'primaryPath': '',
      'additionalPaths': ['/only'],
    });
    expect(folders.map((f) => f.path), ['/only']);
  });

  test('foldersFromLegacyJson returns empty when nothing present', () {
    expect(foldersFromLegacyJson(<String, Object?>{}), isEmpty);
  });

  test('foldersFromLegacyJson falls through to legacy when folders is empty', () {
    final folders = foldersFromLegacyJson({
      'folders': <Object?>[],
      'primaryPath': '/main',
      'additionalPaths': ['/x'],
    });
    expect(folders.map((f) => f.path), ['/main', '/x']);
  });

  test('foldersFromLegacyJson returns empty for empty folders and no legacy', () {
    expect(foldersFromLegacyJson({'folders': <Object?>[]}), isEmpty);
  });
}
