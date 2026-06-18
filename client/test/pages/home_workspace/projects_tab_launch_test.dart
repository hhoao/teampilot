import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_projects_tab.dart';
import 'package:teampilot/services/home_workspace/home_workspace_project_launch_prefs_store.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

AppProject _project() =>
    AppProject(projectId: 'p1', primaryPath: '/tmp/p1', createdAt: 0);

void main() {
  group('projectLaunchRoute', () {
    test('encodes bare identity ids', () {
      expect(
        projectLaunchRoute('p1', const LaunchIdentity('personal-default')),
        '/home-v2/project/p1?as=personal-default',
      );
      expect(
        projectLaunchRoute('p1', const LaunchIdentity('squad')),
        '/home-v2/project/p1?as=squad',
      );
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
          const ProjectLaunchPref(lastIdentity: 'squad', remember: false),
        ),
        isNull,
      );
    });

    test('route when remembered and well-formed', () {
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: 'squad', remember: true),
        ),
        '/home-v2/project/p1?as=squad',
      );
      expect(
        rememberedLaunchRoute(
          _project(),
          ProjectLaunchPref(
            lastIdentity: IdentityProvisioner.defaultPersonalId,
            remember: true,
          ),
        ),
        '/home-v2/project/p1?as=${IdentityProvisioner.defaultPersonalId}',
      );
    });

    test('null when remembered identity is malformed (falls back to dialog)', () {
      expect(
        rememberedLaunchRoute(
          _project(),
          const ProjectLaunchPref(lastIdentity: '', remember: true),
        ),
        isNull,
      );
    });
  });
}
