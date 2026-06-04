import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team/default_team_project_service.dart';
import 'package:teampilot/utils/project_path_utils.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('primaryPathForTeam is cwd joined with team id', () {
    final cwd = AppStorage.cwd;
    expect(
      DefaultTeamProjectService.primaryPathForTeam('alpha-team'),
      normalizeProjectPath(p.join(cwd, 'alpha-team')),
    );
  });
}
