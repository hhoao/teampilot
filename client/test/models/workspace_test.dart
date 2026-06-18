import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';

void main() {
  test('json round-trip carries no teamId', () {
    final workspace = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp/repo',
      display: 'Repo',
      createdAt: 1,
      updatedAt: 2,
    );
    final json = workspace.toJson();
    expect(json.containsKey('teamId'), isFalse);
    final restored = Workspace.fromJson(json);
    expect(restored.workspaceId, 'p1');
    expect(restored.primaryPath, '/tmp/repo');
    expect(restored.display, 'Repo');
  });

  test('legacy teamId key in json is ignored on read', () {
    final restored = Workspace.fromJson({
      'workspaceId': 'p1',
      'primaryPath': '/tmp/repo',
      'teamId': 'old-team',
      'createdAt': 1,
    });
    expect(restored.workspaceId, 'p1');
    // No teamId surface exists; the field is simply dropped.
  });

  test('defaultIdentityId round-trips and defaults empty', () {
    const p = Workspace(
      workspaceId: 'p1',
      primaryPath: '/tmp/p1',
      createdAt: 1,
      defaultIdentityId: 'coding',
    );
    final restored = Workspace.fromJson(p.toJson());
    expect(restored.defaultIdentityId, 'coding');
    expect(
      Workspace.fromJson({'workspaceId': 'x', 'primaryPath': '/x'})
          .defaultIdentityId,
      '',
    );
  });
}
