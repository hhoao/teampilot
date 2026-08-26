import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_tools_scope_bridge.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope_registry.dart';

import '../../support/test_runtime_context.dart';

void main() {
  testWidgets('bridge republishes WorkspaceToolsScope into floating subtree', (
    tester,
  ) async {
    final home = testRuntimeContext('/home');
    final lifecycle = SessionLifecycleService(
      storageRootsResolver: () async => home,
      workContextResolver: (_) async => home,
    );
    final registry = WorkspaceToolsScopeRegistry();
    addTearDown(registry.dispose);
    final scopeCubit = registry.cubitFor(
      tabScopeId: 'ws-1',
      lifecycle: lifecycle,
    );
    await scopeCubit.sync(
      workspaceFolders: const [WorkspaceFolder(path: '/repo')],
      cwd: '/repo',
      additionalPaths: const [],
    );

    final floating = FloatingWorkspaceCubit();
    addTearDown(floating.close);
    floating.setActiveWorkspace('ws-1');

    late List<String>? seenRoots;
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableProvider<WorkspaceToolsScopeRegistry>.value(
          value: registry,
          child: BlocProvider<FloatingWorkspaceCubit>.value(
            value: floating,
            child: FloatingWorkspaceToolsScopeBridge(
              child: Builder(
                builder: (context) {
                  seenRoots = WorkspaceToolsScope.maybeOf(context)?.roots;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(seenRoots, ['/repo']);
  });

  testWidgets('bridge is a no-op when registry cubit is missing', (
    tester,
  ) async {
    final floating = FloatingWorkspaceCubit();
    addTearDown(floating.close);
    floating.setActiveWorkspace('ws-missing');

    late List<String>? seenRoots;
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableProvider<WorkspaceToolsScopeRegistry>.value(
          value: WorkspaceToolsScopeRegistry(),
          child: BlocProvider<FloatingWorkspaceCubit>.value(
            value: floating,
            child: FloatingWorkspaceToolsScopeBridge(
              child: Builder(
                builder: (context) {
                  seenRoots = WorkspaceToolsScope.maybeOf(context)?.roots;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(seenRoots, isNull);
  });
}
