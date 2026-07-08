import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

void main() {
  group('WorkspaceLayout workspace runtime paths', () {
    final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('workspaceRuntimeToolDir is under workspace runtime', () {
      final path = layout.workspaceRuntimeToolDir('ws', 'cursor');
      expect(path, '/tp/workspace/workspaces/ws/runtime/cursor');
      expect(path, isNot(contains('/sessions/')));
    });

    test('workspaceLifecycleManifestPath ends with init.json under workspace runtime', () {
      final path = layout.workspaceLifecycleManifestPath('ws', 'cursor');
      expect(path, '/tp/workspace/workspaces/ws/runtime/cursor/init.json');
    });

    test('workspaceRuntimeMemberToolDir is under workspace runtime', () {
      expect(
        layout.workspaceRuntimeMemberToolDir('ws', 'team-lead', 'cursor'),
        '/tp/workspace/workspaces/ws/runtime/team-lead/cursor',
      );
    });
  });

  group('RuntimeLayout workspace runtime path delegates', () {
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('workspaceRuntimeToolDir delegates to workspace layout', () {
      expect(
        layout.workspaceRuntimeToolDir('ws', 'cursor'),
        '/tp/workspace/workspaces/ws/runtime/cursor',
      );
    });

    test('workspaceLifecycleManifestPath delegates to workspace layout', () {
      expect(
        layout.workspaceLifecycleManifestPath('ws', 'cursor'),
        '/tp/workspace/workspaces/ws/runtime/cursor/init.json',
      );
    });
  });
}
