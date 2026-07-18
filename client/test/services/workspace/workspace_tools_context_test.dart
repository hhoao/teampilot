import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

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

  test('rootsForTarget includes catalog paths on each machine', () {
    final home = testRuntimeContext('/home');
    final folders = const [
      WorkspaceFolder(path: '/local', targetId: 'local'),
      WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ];

    final remoteRoots = WorkspaceToolsContext.rootsForTarget(
      folders: folders,
      targetId: 'ssh:p1',
      primaryPath: '/local',
      additionalPaths: const [],
      context: home,
    );

    expect(remoteRoots, ['/remote']);
  });

  test('scope cubit resolves a slice per target in mixed workspaces', () async {
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
      WorkspaceFolder(path: '/local', targetId: 'local'),
      WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ];
    final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
    await cubit.sync(
      workspaceFolders: folders,
      cwd: '/local',
      additionalPaths: const [],
    );

    expect(cubit.state.isMixed, isTrue);
    expect(cubit.state.targetSlices.length, 2);
    expect(cubit.state.targetSlices.map((s) => s.targetId).toSet(), {
      'local',
      'ssh:p1',
    });
    expect(cubit.state.targetSlices[1].roots, ['/remote']);

    await cubit.close();
  });

  test('re-sync keeps tools visible while resolving', () async {
    final home = testRuntimeContext('/home');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (_) async => home,
    );
    final folders = const [WorkspaceFolder(path: '/repo', targetId: 'local')];
    final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
    await cubit.sync(
      workspaceFolders: folders,
      cwd: '/repo',
      additionalPaths: const [],
    );
    expect(cubit.state.isReady, isTrue);
    expect(cubit.state.tools, isNotNull);

    final readyDuringSync = cubit.stream.firstWhere((s) {
      if (!s.isReady) return false;
      return s.tools != null;
    });
    unawaited(
      cubit.sync(
        workspaceFolders: folders,
        cwd: '/repo/feature',
        additionalPaths: const [],
      ),
    );
    expect(await readyDuringSync, isNotNull);
    expect(cubit.state.isReady, isTrue);

    await cubit.close();
  });

  test(
    'mixed sync keeps local tools when remote target resolve fails',
    () async {
      final home = testRuntimeContext('/home');
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => home,
        workContextResolver: (target) async {
          if (target.kind == RuntimeKind.ssh) {
            throw StateError('ssh unreachable');
          }
          return home;
        },
      );
      final folders = const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
      await cubit.sync(
        workspaceFolders: folders,
        cwd: '/local',
        additionalPaths: const [],
      );

      expect(cubit.state.resolving, isFalse);
      expect(cubit.state.isReady, isTrue);
      expect(cubit.state.tools?.targetId, 'local');
      expect(cubit.state.targetSlices.map((s) => s.targetId), ['local']);
      expect(cubit.state.failedTargetIds, ['ssh:p1']);
      expect(cubit.state.resolveError, isNotNull);

      await cubit.close();
    },
  );

  test(
    'mixed sync surfaces local tools before a slow remote finishes',
    () async {
      final home = testRuntimeContext('/home');
      final remoteReady = Completer<void>();
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => home,
        workContextResolver: (target) async {
          if (target.kind == RuntimeKind.ssh) {
            await remoteReady.future;
            return RuntimeContext(
              target: RuntimeTarget.ssh('p1', label: 'box'),
              filesystem: InMemoryFilesystem(),
              home: '/remote',
              cwd: '/remote',
              appDataRoot: '/remote/app',
              paths: home.paths,
            );
          }
          return home;
        },
      );
      final folders = const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
      final ready = cubit.stream.firstWhere(
        (s) => s.isReady && s.tools?.targetId == 'local',
      );
      final syncFuture = cubit.sync(
        workspaceFolders: folders,
        cwd: '/local',
        additionalPaths: const [],
      );

      await ready;
      expect(cubit.state.targetSlices.map((s) => s.targetId), ['local']);

      remoteReady.complete();
      await syncFuture;
      expect(cubit.state.targetSlices.map((s) => s.targetId).toSet(), {
        'local',
        'ssh:p1',
      });

      await cubit.close();
    },
  );

  test(
    'mixed sync falls back to local when active remote resolve fails',
    () async {
      final home = testRuntimeContext('/home');
      final lifecycle = SessionLifecycleService(
        storageRootsResolver: () async => home,
        workContextResolver: (target) async {
          if (target.kind == RuntimeKind.ssh) {
            throw StateError('ssh unreachable');
          }
          return home;
        },
      );
      final folders = const [
        WorkspaceFolder(path: '/local', targetId: 'local'),
        WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
      ];
      final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
      await cubit.sync(
        workspaceFolders: folders,
        cwd: '/remote',
        additionalPaths: const [],
      );

      expect(cubit.state.resolving, isFalse);
      expect(cubit.state.isReady, isTrue);
      expect(cubit.state.tools?.targetId, 'local');
      expect(cubit.state.targetSlices.map((s) => s.targetId), ['local']);
      expect(cubit.state.failedTargetIds, contains('ssh:p1'));

      await cubit.close();
    },
  );

  test('sync ends resolving when every target fails', () async {
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => testRuntimeContext('/home'),
      workContextResolver: (_) async {
        throw StateError('all unreachable');
      },
    );
    final folders = const [
      WorkspaceFolder(path: '/local', targetId: 'local'),
      WorkspaceFolder(path: '/remote', targetId: 'ssh:p1'),
    ];
    final cubit = WorkspaceToolsScopeCubit(lifecycle: lifecycle);
    await cubit.sync(
      workspaceFolders: folders,
      cwd: '/local',
      additionalPaths: const [],
    );

    expect(cubit.state.resolving, isFalse);
    expect(cubit.state.isReady, isFalse);
    expect(cubit.state.tools, isNull);
    expect(cubit.state.resolveError, isNotNull);
    expect(cubit.state.failedTargetIds, isNotEmpty);

    await cubit.close();
  });
}
