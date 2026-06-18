import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_projects_tab.dart';
import 'package:teampilot/services/home_workspace/home_workspace_project_launch_prefs_store.dart';

AppProject _project() =>
    AppProject(projectId: 'p1', primaryPath: '/tmp/p1', createdAt: 0);

void main() {
  group('projectLaunchRoute', () {
    test('encodes personal and team identities', () {
      expect(projectLaunchRoute('p1', LaunchIdentity.personal),
          '/home-v2/project/p1?as=personal');
      expect(projectLaunchRoute('p1', const LaunchIdentity.team('a')),
          '/home-v2/project/p1?as=team:a');
    });
  });

  group('rememberedLaunchRoute (skip-dialog decision)', () {
    test('null when no pref', () {
      expect(rememberedLaunchRoute(_project(), null), isNull);
    });

    test('null when remember is false', () {
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: 'team:a', remember: false),
        ),
        isNull,
      );
    });

    test('route when remembered and well-formed', () {
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: 'team:a', remember: true),
        ),
        '/home-v2/project/p1?as=team:a',
      );
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: 'personal', remember: true),
        ),
        '/home-v2/project/p1?as=personal',
      );
    });

    test('null when remembered identity is malformed (falls back to dialog)', () {
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: 'bogus', remember: true),
        ),
        isNull,
      );
    });
  });
}
