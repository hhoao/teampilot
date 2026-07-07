import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

void main() {
  group('WorkspaceLayout session shared paths', () {
    final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('sessionRuntimeSharedToolDir is under runtime/_shared', () {
      final path = layout.sessionRuntimeSharedToolDir('ws', 'sess', 'cursor');
      expect(path, contains('/runtime/_shared/cursor'));
      expect(path, isNot(contains('/team-lead/')));
    });

    test('sessionLifecycleManifestPath ends with init.json under shared tool dir', () {
      final path = layout.sessionLifecycleManifestPath('ws', 'sess', 'cursor');
      expect(
        path,
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor/init.json',
      );
    });
  });

  group('RuntimeLayout session shared path delegates', () {
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: LocalFilesystem());

    test('sessionRuntimeSharedToolDir delegates to workspace layout', () {
      expect(
        layout.sessionRuntimeSharedToolDir('ws', 'sess', 'cursor'),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor',
      );
    });

    test('sessionLifecycleManifestPath delegates to workspace layout', () {
      expect(
        layout.sessionLifecycleManifestPath('ws', 'sess', 'cursor'),
        '/tp/workspace/workspaces/ws/sessions/sess/runtime/_shared/cursor/init.json',
      );
    });
  });
}
