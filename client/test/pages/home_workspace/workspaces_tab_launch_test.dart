import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/pages/home_workspace/workspaces_tab.dart';
import 'package:teampilot/services/home_workspace/workspace_launch_prefs_store.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

Workspace _workspace() => Workspace(
    workspaceId: 'p1',
    folders: [WorkspaceFolder(path: '/tmp/p1')],
    createdAt: 0);

void main() {
  group('workspaceLaunchRoute', () {
    test('encodes bare identity ids', () {
      expect(
        workspaceLaunchRoute('p1', const LaunchProfileRef('personal-default')),
        '/home-v2/workspace/p1?as=personal-default',
      );
      expect(
        workspaceLaunchRoute('p1', const LaunchProfileRef('squad')),
        '/home-v2/workspace/p1?as=squad',
      );
    });
  });

  group('rememberedLaunchRoute (skip-dialog decision)', () {
    test('null when no pref', () {
      expect(rememberedLaunchRoute(_workspace(), null), isNull);
    });

    test('null when remember is false', () {
      expect(
        rememberedLaunchRoute(
          _workspace(),
          const WorkspaceLaunchPref(lastIdentity: 'squad', remember: false),
        ),
        isNull,
      );
    });

    test('route when remembered and well-formed', () {
      expect(
        rememberedLaunchRoute(
          _workspace(),
          const WorkspaceLaunchPref(lastIdentity: 'squad', remember: true),
        ),
        '/home-v2/workspace/p1?as=squad',
      );
      expect(
        rememberedLaunchRoute(
          _workspace(),
          WorkspaceLaunchPref(
            lastIdentity: LaunchProfileProvisioner.defaultPersonalId,
            remember: true,
          ),
        ),
        '/home-v2/workspace/p1?as=${LaunchProfileProvisioner.defaultPersonalId}',
      );
    });

    test('null when remembered identity is malformed (falls back to dialog)', () {
      expect(
        rememberedLaunchRoute(
          _workspace(),
          const WorkspaceLaunchPref(lastIdentity: '', remember: true),
        ),
        isNull,
      );
    });
  });
}
