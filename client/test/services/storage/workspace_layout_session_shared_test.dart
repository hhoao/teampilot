import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/cursor_warm_tier_manifest_paths.dart';

void main() {
  final pathContext = p.context;
  final cursorRuntimeRoot = pathContext.join(
    '/tp',
    'workspace',
    'workspaces',
    'ws',
    'runtime',
    'teams',
    cursorTestTeamId,
    'cursor',
  );

  group('WorkspaceLayout workspace runtime paths', () {
    final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test(
      'workspaceRuntimeToolDir is under workspace runtime/teams/{teamId}',
      () {
        final path = layout.workspaceRuntimeToolDir(
          'ws',
          cursorTestTeamId,
          'cursor',
        );
        expect(path, cursorRuntimeRoot);
        expect(path, isNot(contains('/sessions/')));
      },
    );

    test(
      'workspaceLifecycleManifestPath ends with init.json under team runtime',
      () {
        final path = layout.workspaceLifecycleManifestPath(
          'ws',
          cursorTestTeamId,
          'cursor',
        );
        expect(path, pathContext.join(cursorRuntimeRoot, 'init.json'));
      },
    );

    test('workspaceRuntimeMemberToolDir is under team runtime', () {
      expect(
        layout.workspaceRuntimeMemberToolDir(
          'ws',
          cursorTestTeamId,
          'team-lead',
          'cursor',
        ),
        pathContext.join(
          '/tp',
          'workspace',
          'workspaces',
          'ws',
          'runtime',
          'teams',
          cursorTestTeamId,
          'team-lead',
          'cursor',
        ),
      );
    });
  });

  group('RuntimeLayout workspace runtime path delegates', () {
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('workspaceRuntimeToolDir delegates to workspace layout', () {
      expect(
        layout.workspaceRuntimeToolDir('ws', cursorTestTeamId, 'cursor'),
        cursorRuntimeRoot,
      );
    });

    test('workspaceLifecycleManifestPath delegates to workspace layout', () {
      expect(
        layout.workspaceLifecycleManifestPath('ws', cursorTestTeamId, 'cursor'),
        pathContext.join(cursorRuntimeRoot, 'init.json'),
      );
    });
  });
}
