import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_cubit.dart';
import 'package:teampilot/services/git/git_repo_store.dart';

import '../../support/git_graph_test_fakes.dart';
import '../../support/test_runtime_context.dart';

/// 记录 refresh() 调用的状态 cubit 替身（不触达真实 git 服务）。
class _SpyGitCubit extends GitCubit {
  _SpyGitCubit() : super(service: FakeGitForGraph(repoStatus()));

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

void main() {
  test('refreshAll fast-paths the active root only within the interval', () {
    var now = DateTime(2026, 1, 1);
    final store = GitRepoStore(
      cubitFactory: (root, workContext) => _SpyGitCubit(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    final a = store.cubitFor('/repo-a', workContext: context) as _SpyGitCubit;
    final b = store.cubitFor('/repo-b', workContext: context) as _SpyGitCubit;

    // 首次：全部预热（agent 未动任何项目时缓存也要温）。
    store.refreshAll(
      ['/repo-a', '/repo-b'],
      workContext: context,
      activeRoot: '/repo-b',
    );
    expect(a.refreshCalls, 1);
    expect(b.refreshCalls, 1);

    // 间隔内：只有选中的 root 跟随 watcher/轮询刷新。
    now = now.add(const Duration(seconds: 5));
    store.refreshAll(
      ['/repo-a', '/repo-b'],
      workContext: context,
      activeRoot: '/repo-b',
    );
    expect(a.refreshCalls, 1, reason: '非选中 root 间隔内不得重刷 status');
    expect(b.refreshCalls, 2);

    // 间隔过后：全部 root 再保缓存一次。
    now = now.add(GitRepoStore.backgroundRefreshInterval + const Duration(seconds: 1));
    store.refreshAll(
      ['/repo-a', '/repo-b'],
      workContext: context,
      activeRoot: '/repo-b',
    );
    expect(a.refreshCalls, 2);
    expect(b.refreshCalls, 3);
  });

  test('refreshAll falls back to the first root without a selection', () {
    var now = DateTime(2026, 1, 1);
    final store = GitRepoStore(
      cubitFactory: (root, workContext) => _SpyGitCubit(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    store.refreshAll(['', '/repo-a', '/repo-b'], workContext: context);
    final a = store.cubitFor('/repo-a', workContext: context) as _SpyGitCubit;
    final b = store.cubitFor('/repo-b', workContext: context) as _SpyGitCubit;
    expect(a.refreshCalls, 1, reason: '首次调用预热全部 root');
    expect(b.refreshCalls, 1);

    // 未上报选择（面板未挂载）→ 默认首个 root 全速。
    now = now.add(const Duration(seconds: 5));
    store.refreshAll(['/repo-a', '/repo-b'], workContext: context);
    expect(a.refreshCalls, 2);
    expect(b.refreshCalls, 1);
  });

  test('refreshAll ignores stale selection no longer among roots', () {
    var now = DateTime(2026, 1, 1);
    final store = GitRepoStore(
      cubitFactory: (root, workContext) => _SpyGitCubit(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    store.refreshAll(
      ['/repo-a', '/repo-b'],
      workContext: context,
      activeRoot: '/removed',
    );
    // activeRoot 不在 roots 内 → 回退首个 root，其余仍走首次预热。
    final a = store.cubitFor('/repo-a', workContext: context) as _SpyGitCubit;
    expect(a.refreshCalls, 1);

    now = now.add(const Duration(seconds: 5));
    store.refreshAll(
      ['/repo-a', '/repo-b'],
      workContext: context,
      activeRoot: '/removed',
    );
    expect(a.refreshCalls, 2, reason: '失效选择回退到首个 root 全速刷新');
  });

  test('single-root workspace keeps the historical full cadence', () {
    var now = DateTime(2026, 1, 1);
    final store = GitRepoStore(
      cubitFactory: (root, workContext) => _SpyGitCubit(),
      clock: () => now,
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    store.refreshAll(['/repo'], workContext: context);
    final cubit = store.cubitFor('/repo', workContext: context) as _SpyGitCubit;
    expect(cubit.refreshCalls, 1);

    now = now.add(const Duration(seconds: 1));
    store.refreshAll(['/repo'], workContext: context);
    expect(cubit.refreshCalls, 2, reason: '单 root 无降频，行为与历史一致');
  });
}
