import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/models/git_status.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/git/git_service.dart';

/// Minimal fake so cubits created by the store never spawn a process.
class _FakeGitService extends GitService {
  _FakeGitService()
    : super(runner: (exe, args, {stdoutEncoding, stderrEncoding}) async {
        throw StateError('runner should not be used in fake');
      });

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<GitRepoStatus> status(String dir) async => GitRepoStatus.notARepository;

  @override
  Future<List<String>> branches(String dir) async => const [];
}

void main() {
  GitCubit makeCubit(String root) =>
      GitCubit(service: _FakeGitService())..setRepoRoot(root);

  test('cubitFor returns the same instance per (normalized) root', () {
    final store = GitRepoStore(cubitFactory: makeCubit);

    final a1 = store.cubitFor('/work/repo');
    final a2 = store.cubitFor('/work/repo');
    final a3 = store.cubitFor('/work/./repo'); // normalizes to the same path

    expect(identical(a1, a2), isTrue);
    expect(identical(a1, a3), isTrue);

    store.dispose();
  });

  test('LRU evicts and closes the least-recently-used cubit past the bound',
      () async {
    final store = GitRepoStore(cubitFactory: makeCubit, maxRetained: 2);

    final a = store.cubitFor('/a');
    final b = store.cubitFor('/b');
    // Touch /a so /b becomes least-recently-used.
    store.cubitFor('/a');
    // Adding a third root evicts /b (the LRU), closing its cubit.
    final c = store.cubitFor('/c');

    expect(b.isClosed, isTrue);
    expect(a.isClosed, isFalse);
    expect(c.isClosed, isFalse);
    // Re-accessing /b builds a fresh cubit (the old one is gone).
    expect(identical(store.cubitFor('/b'), b), isFalse);

    store.dispose();
  });

  test('dispose closes every retained cubit', () {
    final store = GitRepoStore(cubitFactory: makeCubit);
    final a = store.cubitFor('/a');
    final b = store.cubitFor('/b');

    store.dispose();

    expect(a.isClosed, isTrue);
    expect(b.isClosed, isTrue);
  });

  test('refreshAll creates a cubit for each non-empty root', () {
    final store = GitRepoStore(cubitFactory: makeCubit);

    store.refreshAll(['/a', '', '/b']);

    // Re-accessing returns the already-created instances (no rebuild).
    final a = store.cubitFor('/a');
    final b = store.cubitFor('/b');
    expect(identical(store.cubitFor('/a'), a), isTrue);
    expect(identical(store.cubitFor('/b'), b), isTrue);

    store.dispose();
  });
}
