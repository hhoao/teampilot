import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

void main() {
  test('resolve picks target from cwd subpath', () async {
    final home = testRuntimeContext('/home');
    final remote = RuntimeContext(
      target: RuntimeTarget.ssh('p1', label: 'box'),
      filesystem: InMemoryFilesystem(),
      home: '/remote',
      cwd: '/remote',
      appDataRoot: '/remote/app',
      paths: home.paths,
    );
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async =>
          target.kind == RuntimeKind.ssh ? remote : home,
    );
    final folders = const [
      WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      WorkspaceFolder(path: '/local', targetId: 'local'),
    ];

    final resolved = await WorkspaceToolsContext.resolve(
      lifecycle: lifecycle,
      folders: folders,
      paths: ['/repo/feature'],
    );

    expect(resolved.targetId, 'ssh:p1');
    expect(resolved.context.appDataRoot, '/remote/app');
  });

  test('rootsOnTarget filters paths on other machines', () {
    final home = testRuntimeContext('/home');
    final folders = const [
      WorkspaceFolder(path: '/repo', targetId: 'ssh:p1'),
      WorkspaceFolder(path: '/local', targetId: 'local'),
    ];

    final roots = WorkspaceToolsContext.rootsOnTarget(
      folders: folders,
      targetId: 'ssh:p1',
      primaryPath: '/repo/wt',
      additionalPaths: const ['/local', '/repo/extra'],
      context: home,
    );

    expect(roots, ['/repo/wt', '/repo/extra']);
  });
}
