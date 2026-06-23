import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

/// P2: a session's work-plane context is resolved from its workspace folder
/// target. The lifecycle calls `workContextResolver(target)` with the target
/// encoded in `folders.first.targetId`.
void main() {
  test('local workspace resolves the local/home work context', () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return home;
      },
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/proj')], // targetId defaults local
      createdAt: 1,
    );

    final ctx = await lifecycle.debugResolveWorkContext(session);
    expect(resolved, ['local']);
    expect(identical(ctx, home), isTrue);
  });

  test('ssh workspace resolves forTarget(ssh); metadata stays on home', () async {
    final resolved = <String>[];
    final home = testRuntimeContext('/home-root');
    final remote = RuntimeContext(
      target: RuntimeTarget.ssh('p1', label: 'box'),
      filesystem: InMemoryFilesystem(),
      home: '/remote',
      cwd: '/remote',
      appDataRoot: '/remote/app',
      paths: home.paths, // not used here
    );
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (target) async {
        resolved.add(target.id);
        return target.kind == RuntimeKind.ssh ? remote : home;
      },
    );
    final session = AppSession(
      sessionId: 's2',
      workspaceId: 'w2',
      folders: const [
        WorkspaceFolder(path: '/proj', targetId: 'ssh:p1'),
      ],
      createdAt: 1,
    );

    final ctx = await lifecycle.debugResolveWorkContext(session);
    expect(resolved, ['ssh:p1']);
    expect(ctx.appDataRoot, '/remote/app'); // work-plane on the remote
  });
}
