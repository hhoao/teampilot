import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/models/git_worktree.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_worktree_refresher.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_route_active_scope.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/test_runtime_context.dart';

class _CountingLister implements WorktreeLister {
  var calls = 0;
  @override
  Future<List<GitWorktree>> list(String repoPath) async {
    calls++;
    return const [];
  }
}

GitWorktree _wt(String p) => GitWorktree(
  path: p,
  branch: 'refs/heads/x',
  head: 'h',
  isBare: false,
  isMainWorktree: false,
);

class _Harness {
  _Harness({
    required this.routeActive,
    required this.target,
    this.isSubmitting = false,
    this.disabled = false,
  });
  final bool routeActive;
  final RuntimeTarget target;
  final bool isSubmitting;
  final bool disabled;
  late final lister = _CountingLister();
  late final cubit = WorktreeCubit(
    storage: fakeHomeStorage(),
    lister: lister,
    initialRepoPath: '/repo',
  );

  WorkspaceToolsContext get tools => WorkspaceToolsContext(
    targetId: target.id,
    context: RuntimeContext(
      target: target,
      filesystem: testRuntimeContext('/home').filesystem,
      home: '/home',
      cwd: '/home',
      appDataRoot: '/home',
      paths: testRuntimeContext('/home').paths,
    ),
  );

  Future<void> pump(WidgetTester tester, Widget refresher) async {
    await tester.pumpWidget(
      WorkspaceRouteActiveScope(
        routeActive: routeActive,
        child: WorkspaceToolsScope(
          state: WorkspaceToolsScopeState(
            tools: tools,
            roots: const ['/repo'],
            resolving: false,
          ),
          child: BlocProvider<WorktreeCubit>.value(
            value: cubit,
            child: refresher,
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('reloads the active repo on the refresh interval', (
    tester,
  ) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, greaterThanOrEqualTo(1));
  });

  testWidgets('skips on route inactive', (tester) async {
    final h = _Harness(routeActive: false, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('skips on ssh/termux targets', (tester) async {
    final h = _Harness(
      routeActive: true,
      target: RuntimeTarget.ssh('prof', label: 'remote'),
    );
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('skips while submitting', (tester) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(
        isSubmitting: true,
        child: SizedBox(),
      ),
    );
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });

  testWidgets('stops polling after unmount', (tester) async {
    final h = _Harness(routeActive: true, target: RuntimeTarget.local());
    addTearDown(h.cubit.close);
    await h.pump(
      tester,
      const WorkspaceLandingWorktreeRefresher(child: SizedBox()),
    );
    await tester.pumpWidget(const SizedBox()); // unmount → dispose
    await tester.pump(WorkspaceLandingWorktreeRefresher.refreshInterval);
    expect(h.lister.calls, 0);
  });
}
