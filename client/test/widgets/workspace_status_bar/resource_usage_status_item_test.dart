import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/resource_manager_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/resource_manager/process_metrics_service.dart';
import 'package:teampilot/services/resource_manager/pty_process_registry.dart';
import 'package:teampilot/services/resource_manager/resource_binding.dart';
import 'package:teampilot/services/resource_manager/resource_memory_format.dart';
import 'package:teampilot/services/resource_manager/resource_memory_models.dart';
import 'package:teampilot/services/resource_manager/resource_tree_merge.dart';
import 'package:teampilot/widgets/workspace_status_bar/resource_manager_panel.dart';
import 'package:teampilot/widgets/workspace_status_bar/resource_usage_status_item.dart';
import 'package:teampilot/widgets/workspace_status_bar/workspace_status_bar.dart';
import 'package:teampilot/pages/home_workspace/global_resource_manager_host.dart';

class _SeededResourceManagerCubit extends ResourceManagerCubit {
  _SeededResourceManagerCubit(ResourceManagerState initial)
      : super(
          metricsService: ProcessMetricsService(),
          registry: PtyProcessRegistry(),
          bindingsSource: () => const [],
          killBinding: (_) async {},
        ) {
    emit(initial);
  }

  void seed(ResourceManagerState next) => emit(next);
}

Widget _host({
  required ResourceManagerCubit cubit,
  required Widget child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<ResourceManagerCubit>.value(
      value: cubit,
      child: Scaffold(body: child),
    ),
  );
}

ResourceTreeViewModel _treeWithNullLeaf() {
  return mergeResourceTree(
    bindings: const [
      ResourceBinding(
        key: 'chat:s1:m1',
        kind: ResourceBindingKind.chatMember,
        groupKey: 'main',
        groupLabel: 'main',
        title: 'Terminal 1',
        connected: true,
        sessionId: 's1',
        memberId: 'm1',
      ),
    ],
  );
}

void main() {
  testWidgets('pill shows terminal count only (no memory while closed)',
      (tester) async {
    const memoryBytes = 960.8 * 1024 * 1024;
    final memoryLabel = formatResourceMemory(memoryBytes);
    final cubit = _SeededResourceManagerCubit(
      ResourceManagerState(
        terminalCount: 2,
        snapshot: ResourceMemorySnapshot(
          collectedAt: DateTime.fromMillisecondsSinceEpoch(1),
          totalMemory: memoryBytes.round(),
        ),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: WorkspaceStatusBar(
          items: [ResourceUsageStatusItem()],
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text(memoryLabel), findsNothing);
  });

  testWidgets('panel leaf with null metrics shows em dash', (tester) async {
    final tree = _treeWithNullLeaf();
    final cubit = _SeededResourceManagerCubit(
      ResourceManagerState(
        isOpen: true,
        terminalCount: tree.terminalCount,
        tree: tree,
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: const ResourceManagerPanel(),
      ),
    );

    expect(find.text(kResourceMetricEmDash), findsWidgets);
    expect(tree.groups.single.leaves.single.cpuDisplay, kResourceMetricEmDash);
    expect(
      tree.groups.single.leaves.single.memoryDisplay,
      kResourceMetricEmDash,
    );
  });

  testWidgets('panel body is fixed 420 with scrollable middle', (tester) async {
    final cubit = _SeededResourceManagerCubit(
      const ResourceManagerState(isOpen: true),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: const ResourceManagerPanel(),
      ),
    );

    final body = tester.widget<SizedBox>(
      find.byKey(const Key('resource-manager-body')),
    );
    expect(body.height, ResourceManagerPanel.bodyHeight);
    expect(body.height, 420);
    expect(
      find.descendant(
        of: find.byKey(const Key('resource-manager-body')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('panel shows error affordance when state.error != null',
      (tester) async {
    final cubit = _SeededResourceManagerCubit(
      const ResourceManagerState(
        isOpen: true,
        error: 'boom',
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: cubit,
        child: const ResourceManagerPanel(),
      ),
    );

    expect(find.byKey(const Key('resource-manager-error')), findsOneWidget);
  });

  testWidgets(
    'status item under ResourceManagerNavigateScope wires leaf navigate',
    (tester) async {
      final tree = _treeWithNullLeaf();
      final leaf = tree.groups.single.leaves.single;
      ResourceTreeLeafVm? navigated;
      final cubit = _SeededResourceManagerCubit(
        ResourceManagerState(
          isOpen: true,
          terminalCount: tree.terminalCount,
          tree: tree,
        ),
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(
        _host(
          cubit: cubit,
          child: ResourceManagerNavigateScope(
            onNavigateLeaf: (l) => navigated = l,
            child: Builder(
              builder: (context) {
                // Same lookup path as WorkspaceStatusBar → buildSegment under Scope.
                final fromScope = ResourceManagerNavigateScope.maybeOf(context);
                expect(fromScope, isNotNull);
                // buildSegment must resolve the InheritedWidget (not null ctor arg).
                ResourceUsageStatusItem().buildSegment(context, compact: false);
                return ResourceManagerPanel(onNavigateLeaf: fromScope);
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text(leaf.title));
      await tester.pump();

      expect(navigated, isNotNull);
      expect(navigated!.key, leaf.key);
      expect(cubit.state.isOpen, isFalse);
    },
  );
}
