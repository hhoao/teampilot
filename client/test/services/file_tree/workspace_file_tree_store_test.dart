import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/test_runtime_context.dart';

Filesystem _localFs() => LocalFilesystem();

/// Minimal fake so cubits created by the store never spawn a process.
class _FakeGitService extends GitService {
  _FakeGitService() : super();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => GitRepoStatus.notARepository;

  @override
  Future<List<String>> branches(String dir) async => const [];
}

void main() {
  group('WorkspaceFileTreeStore', () {
    FileTreeCubit makeCubit(Filesystem fs) => FileTreeCubit(fs: fs);

    test('cubitFor returns the same instance per workspace id and target', () {
      final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
      final fs = _localFs();

      final a1 = store.cubitFor('ws-a', targetId: 'local', fs: fs);
      final a2 = store.cubitFor('ws-a', targetId: 'local', fs: fs);
      final b = store.cubitFor('ws-b', targetId: 'local', fs: fs);
      final remote = store.cubitFor('ws-a', targetId: 'ssh:p1', fs: fs);

      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b), isFalse);
      expect(identical(a1, remote), isFalse);

      store.dispose();
    });

    test('removeWorkspaceTarget closes one target cubit', () {
      final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
      final fs = _localFs();
      final local = store.cubitFor('ws-a', targetId: 'local', fs: fs);
      final remote = store.cubitFor('ws-a', targetId: 'ssh:p1', fs: fs);

      store.removeWorkspaceTarget('ws-a', 'local');

      expect(local.isClosed, isTrue);
      expect(remote.isClosed, isFalse);

      store.dispose();
    });

    test('removeWorkspace closes all target cubits for that workspace', () {
      final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
      final fs = _localFs();
      final local = store.cubitFor('ws-a', targetId: 'local', fs: fs);
      final remote = store.cubitFor('ws-a', targetId: 'ssh:p1', fs: fs);

      store.removeWorkspace('ws-a');

      expect(local.isClosed, isTrue);
      expect(remote.isClosed, isTrue);
      expect(
        identical(
          store.cubitFor('ws-a', targetId: 'local', fs: fs),
          local,
        ),
        isFalse,
      );

      store.dispose();
    });

    test('dispose closes every retained cubit', () {
      final store = WorkspaceFileTreeStore(cubitFactory: makeCubit);
      final fs = _localFs();
      final a = store.cubitFor('ws-a', targetId: 'local', fs: fs);
      final b = store.cubitFor('ws-b', targetId: 'local', fs: fs);

      store.dispose();

      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
    });
  });

  group('GitRepoStore', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    GitCubit makeCubit(String root, RuntimeContext ctx) =>
        GitCubit(service: _FakeGitService())..setRepoRoot(root);

    test('cubitFor returns the same instance per (normalized) root', () {
      final store = GitRepoStore(cubitFactory: makeCubit);
      final ctx = testRuntimeContext('/home');

      final a1 = store.cubitFor('/work/repo', workContext: ctx);
      final a2 = store.cubitFor('/work/repo', workContext: ctx);
      final a3 = store.cubitFor('/work/./repo', workContext: ctx);

      expect(identical(a1, a2), isTrue);
      expect(identical(a1, a3), isTrue);

      store.dispose();
    });

    test('same root on different targets yields distinct cubits', () {
      final store = GitRepoStore(cubitFactory: makeCubit);
      final home = testRuntimeContext('/home');
      final remote = RuntimeContext(
        target: RuntimeTarget.ssh('p1', label: 'box'),
        filesystem: InMemoryFilesystem(),
        home: '/remote',
        cwd: '/remote',
        appDataRoot: '/remote/app',
        paths: home.paths,
      );

      final localCubit = store.cubitFor('/repo', workContext: home);
      final remoteCubit = store.cubitFor('/repo', workContext: remote);

      expect(identical(localCubit, remoteCubit), isFalse);

      store.dispose();
    });

    test('LRU evicts and closes the least-recently-used cubit past the bound',
        () async {
      final store = GitRepoStore(cubitFactory: makeCubit, maxRetained: 2);
      final ctx = testRuntimeContext('/home');

      final a = store.cubitFor('/a', workContext: ctx);
      final b = store.cubitFor('/b', workContext: ctx);
      store.cubitFor('/a', workContext: ctx);
      final c = store.cubitFor('/c', workContext: ctx);

      expect(b.isClosed, isTrue);
      expect(a.isClosed, isFalse);
      expect(c.isClosed, isFalse);
      expect(identical(store.cubitFor('/b', workContext: ctx), b), isFalse);

      store.dispose();
    });

    test('dispose closes every retained cubit', () {
      final store = GitRepoStore(cubitFactory: makeCubit);
      final ctx = testRuntimeContext('/home');
      final a = store.cubitFor('/a', workContext: ctx);
      final b = store.cubitFor('/b', workContext: ctx);

      store.dispose();

      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
    });

    test('refreshAll creates a cubit for each non-empty root', () {
      final store = GitRepoStore(cubitFactory: makeCubit);
      final ctx = testRuntimeContext('/home');

      store.refreshAll(['/a', '', '/b'], workContext: ctx);

      final a = store.cubitFor('/a', workContext: ctx);
      final b = store.cubitFor('/b', workContext: ctx);
      expect(identical(store.cubitFor('/a', workContext: ctx), a), isTrue);
      expect(identical(store.cubitFor('/b', workContext: ctx), b), isTrue);

      store.dispose();
    });
  });
}
