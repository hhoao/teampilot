import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';

void main() {
  test('json round-trip carries no teamId', () {
    final project = AppProject(
      projectId: 'p1',
      primaryPath: '/tmp/repo',
      display: 'Repo',
      createdAt: 1,
      updatedAt: 2,
    );
    final json = project.toJson();
    expect(json.containsKey('teamId'), isFalse);
    final restored = AppProject.fromJson(json);
    expect(restored.projectId, 'p1');
    expect(restored.primaryPath, '/tmp/repo');
    expect(restored.display, 'Repo');
  });

  test('legacy teamId key in json is ignored on read', () {
    final restored = AppProject.fromJson({
      'projectId': 'p1',
      'primaryPath': '/tmp/repo',
      'teamId': 'old-team',
      'createdAt': 1,
    });
    expect(restored.projectId, 'p1');
    // No teamId surface exists; the field is simply dropped.
  });
}
