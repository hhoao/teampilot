import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/cursor_warm_tier_manifest_paths.dart';

void main() {
  group('WorkspaceLayout workspace runtime paths', () {
    final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('workspaceRuntimeToolDir is under workspace runtime/teams/{teamId}', () {
      final path = layout.workspaceRuntimeToolDir('ws', cursorTestTeamId, 'cursor');
      expect(
        path,
        '/tp/workspace/workspaces/ws/runtime/teams/team-a/cursor',
      );
      expect(path, isNot(contains('/sessions/')));
    });

    test('workspaceLifecycleManifestPath ends with init.json under team runtime', () {
      final path = layout.workspaceLifecycleManifestPath(
        'ws',
        cursorTestTeamId,
        'cursor',
      );
      expect(
        path,
        '/tp/workspace/workspaces/ws/runtime/teams/team-a/cursor/init.json',
      );
    });

    test('workspaceRuntimeMemberToolDir is under team runtime', () {
      expect(
        layout.workspaceRuntimeMemberToolDir(
          'ws',
          cursorTestTeamId,
          'team-lead',
          'cursor',
        ),
        '/tp/workspace/workspaces/ws/runtime/teams/team-a/team-lead/cursor',
      );
    });
  });

  group('RuntimeLayout workspace runtime path delegates', () {
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('workspaceRuntimeToolDir delegates to workspace layout', () {
      expect(
        layout.workspaceRuntimeToolDir('ws', cursorTestTeamId, 'cursor'),
        '/tp/workspace/workspaces/ws/runtime/teams/team-a/cursor',
      );
    });

    test('workspaceLifecycleManifestPath delegates to workspace layout', () {
      expect(
        layout.workspaceLifecycleManifestPath('ws', cursorTestTeamId, 'cursor'),
        '/tp/workspace/workspaces/ws/runtime/teams/team-a/cursor/init.json',
      );
    });
  });
}
