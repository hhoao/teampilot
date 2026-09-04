import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/git_graph_cubit.dart';
import 'package:teampilot/services/git/git_repo_store.dart';

import '../../support/git_graph_test_fakes.dart';
import '../../support/test_runtime_context.dart';

/// 记录 refresh() 调用的图 cubit 替身（不触达真实 git 服务）。
class _SpyGraphCubit extends GitGraphCubit {
  _SpyGraphCubit() : super(history: FakeHistoryForGraph(), git: FakeGitForGraph(repoStatus()));

  int refreshCalls = 0;

  @override
  Future<void> refresh() async {
    refreshCalls++;
  }
}

void main() {
  test('refreshGraphs creates nothing and skips unmounted graph cubits', () {
    final store = GitRepoStore(
      graphCubitFactory: (root, workContext) => _SpyGraphCubit(),
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    // 轮询不得为无人查看的 root 创建 graph cubit（一次图刷新约 5 个子进程）。
    store.refreshGraphs(['', '/repo-a', '/repo-b'], workContext: context);
    final cubitA =
        store.graphCubitFor('/repo-a', workContext: context)
            as _SpyGraphCubit;
    // 仅 graphCubitFor 挂载预热（setRepoRoot→refresh）。
    expect(cubitA.refreshCalls, 1);

    store.refreshGraphs(['/repo-a'], workContext: context);
    // 无面板监听 → 轮询跳过。
    expect(cubitA.refreshCalls, 1);

    void listener() {}
    cubitA.addListener(listener); // 面板挂载中
    store.refreshGraphs(['/repo-a'], workContext: context);
    expect(cubitA.refreshCalls, 2);

    cubitA.removeListener(listener); // 面板卸载
    store.refreshGraphs(['/repo-a'], workContext: context);
    expect(cubitA.refreshCalls, 2);
  });

  test('refreshGraphs refreshes mounted cubits across poll rounds', () {
    final store = GitRepoStore(
      graphCubitFactory: (root, workContext) => _SpyGraphCubit(),
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');

    final cubit =
        store.graphCubitFor('/repo', workContext: context) as _SpyGraphCubit;
    void listener() {}
    cubit.addListener(listener);

    store.refreshGraphs(['/repo'], workContext: context);
    store.refreshGraphs(['/repo'], workContext: context);
    // 预热 1 + 两轮轮询各 1。
    expect(cubit.refreshCalls, 3);
  });

  test('eviction skips graph cubits with active listeners', () {
    late final List<_SpyGraphCubit> created;
    var counter = 0;
    final store = GitRepoStore(
      maxRetained: 2,
      graphCubitFactory: (root, workContext) {
        counter++;
        return created[counter - 1];
      },
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');
    created = [_SpyGraphCubit(), _SpyGraphCubit(), _SpyGraphCubit(), _SpyGraphCubit()];

    final a = store.graphCubitFor('/a', workContext: context);
    final b = store.graphCubitFor('/b', workContext: context);
    void listener() {}
    a.addListener(listener); // 面板挂载中

    final c = store.graphCubitFor('/c', workContext: context); // 触发淘汰
    expect(a.isClosed, isFalse); // 有监听者 → 跳过
    expect(b.isClosed, isTrue); // LRU 里最老的可用项被淘汰
    expect(store.graphCubitFor('/c', workContext: context), same(c));

    a.removeListener(listener);
    store.graphCubitFor('/d', workContext: context); // 再次触发淘汰
    expect(a.isClosed, isTrue); // 移除监听后变为可淘汰
  });

  test('graphCubitFor recreates after an external close of the retained cubit', () async {
    late final List<_SpyGraphCubit> created;
    var counter = 0;
    final store = GitRepoStore(
      maxRetained: 2,
      graphCubitFactory: (root, workContext) {
        counter++;
        return created[counter - 1];
      },
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');
    created = [_SpyGraphCubit(), _SpyGraphCubit()];

    final first = store.graphCubitFor('/repo', workContext: context);
    expect(first.isClosed, isFalse);

    // 模拟外部路径（如 BlocProvider）误关了 store 保留的 cubit。
    await first.close();

    final second = store.graphCubitFor('/repo', workContext: context);
    // 必须换新实例，而不是把 closed cubit 发给面板。
    expect(second, isNot(same(first)));
    expect(second.isClosed, isFalse);
  });

  test('eviction pauses entirely when every graph cubit is mounted', () {
    late final List<_SpyGraphCubit> created;
    var counter = 0;
    final store = GitRepoStore(
      maxRetained: 1,
      graphCubitFactory: (root, workContext) {
        counter++;
        return created[counter - 1];
      },
    );
    addTearDown(store.dispose);
    final context = testRuntimeContext('/home');
    created = [_SpyGraphCubit(), _SpyGraphCubit()];
    void listener() {}

    final a = store.graphCubitFor('/a', workContext: context)..addListener(listener);
    // 超限时无可淘汰项：不得抛错，也不得关闭在用 cubit。
    expect(() => store.graphCubitFor('/b', workContext: context), returnsNormally);
    expect(a.isClosed, isFalse);
  });
}
