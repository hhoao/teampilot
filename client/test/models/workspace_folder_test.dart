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

  test('foldersFromJson reads the folders array', () {
    final folders = foldersFromJson([
      {'path': '/a', 'targetId': 'local'},
      {'path': '/b', 'targetId': 'ssh:p1'},
    ]);
    expect(folders.map((f) => f.path), ['/a', '/b']);
    expect(folders.last.targetId, 'ssh:p1');
  });

  test('foldersFromJson returns empty for null / non-list', () {
    expect(foldersFromJson(null), isEmpty);
    expect(foldersFromJson('nope'), isEmpty);
    expect(foldersFromJson(const <Object?>[]), isEmpty);
  });
}
