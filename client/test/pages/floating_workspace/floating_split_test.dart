import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_placement.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/pages/floating_workspace/floating_group_host.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_chrome.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_empty.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_panel.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/floating_workspace/floating_maximize_insets.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';
import 'package:teampilot/widgets/workbench/workbench_split_layout_view.dart';

void main() {
  // 600x400 fits two 180-min groups plus the divider on both axes.
  const widePlacement = FloatingPanelPlacement(
    width: 600,
    height: 400,
    rightInset: 40,
    bottomInset: 80,
  );

  // 320x300 fits neither axis (threshold is 2 * 180 + 1 = 361).
  const narrowPlacement = FloatingPanelPlacement(
    width: 320,
    height: 300,
    rightInset: 40,
    bottomInset: 80,
  );

  Widget wrap({
    required FloatingWorkspaceCubit cubit,
    required WorkbenchCubit workbench,
    required FloatingSurfaceRegistry registry,
    required FloatingMaximizeInsets insets,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: RepositoryProvider<CommandBus>.value(
        value: CommandBus(),
        child: RepositoryProvider<FloatingSurfaceRegistry>.value(
          value: registry,
          child: RepositoryProvider<FloatingMaximizeInsets>.value(
            value: insets,
            child: BlocProvider.value(
              value: cubit,
              child: BlocProvider<WorkbenchCubit>.value(
                value: workbench,
                child: const Scaffold(
                  body: SizedBox(
                    width: 1400,
                    height: 900,
                    child: FloatingWorkspacePanel(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('floatingPanelSplitEnabled', () {
    test('requires two min-extent groups plus the divider on both axes', () {
      const min = kFloatingMinGroupExtent;
      expect(floatingPanelSplitEnabled(const Size(min * 2 + 1, min * 2 + 1)),
          isTrue);
      expect(
        floatingPanelSplitEnabled(const Size(min * 2, min * 2 + 1)),
        isFalse,
      );
      expect(
        floatingPanelSplitEnabled(const Size(min * 2 + 1, min * 2)),
        isFalse,
      );
    });
  });

  testWidgets('splitTab renders two group hosts; title bar hides its tab '
      'strip (per-group headers own the tabs)', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(widePlacement);
    cubit.setActiveWorkspace('ws');
    workbench.openFloating('ws', WorkbenchTabId.shell('One'));
    workbench.openFloating('ws', WorkbenchTabId.shell('Two'));
    await tester.pumpAndSettle();

    // Single group: exactly today's panel — one body, no slim group header.
    expect(find.byType(FloatingGroupHost), findsOneWidget);
    expect(find.byType(FloatingWorkspaceChrome), findsOneWidget);

    workbench.splitTab(
      'ws',
      WorkbenchTabId.shell('Two'),
      axis: Axis.horizontal,
      before: false,
      floating: true,
    );
    await tester.pumpAndSettle();

    // Two group hosts, one divider, and a slim header per group.
    expect(find.byType(FloatingGroupHost), findsNWidgets(2));
    expect(
      find.byKey(workbenchSplitDividerKey(const <bool>[])),
      findsOneWidget,
    );
    // Multi-group: the title bar drops its tab strip (drag handle + chrome
    // only) — each group's slim header owns its tabs. 'Two' shows once (the
    // focused group's header), 'One' once (g0's header).
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    final layout = workbench.floatingLayout('ws');
    expect(layout.groups[layout.focusedGroupId]!.order, [
      WorkbenchTabId.shell('Two'),
    ]);
  });

  testWidgets('narrow panel renders the focused group only', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(narrowPlacement);
    cubit.setActiveWorkspace('ws');
    workbench.openFloating('ws', WorkbenchTabId.shell('One'));
    workbench.openFloating('ws', WorkbenchTabId.shell('Two'));
    workbench.splitTab(
      'ws',
      WorkbenchTabId.shell('Two'),
      axis: Axis.horizontal,
      before: false,
      floating: true,
    );
    await tester.pumpAndSettle();

    // Layout still holds two groups; only the focused one renders.
    expect(workbench.floatingLayout('ws').groups.length, 2);
    expect(find.byType(FloatingGroupHost), findsOneWidget);
    expect(find.byKey(workbenchSplitDividerKey(const <bool>[])), findsNothing);
    // Focused group's strip is visible via the title bar and its slim header.
    expect(find.text('Two'), findsNWidgets(2));
    expect(find.text('One'), findsNothing);
  });

  testWidgets('narrow panel hides title-bar split entries for a multi-tab '
      'group', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(narrowPlacement);
    cubit.setActiveWorkspace('ws');
    // Two tabs in the focused group: the split entries would be eligible on a
    // wide panel (multi-tab rule passes) — only the size threshold gates them.
    workbench.openFloating('ws', WorkbenchTabId.shell('One'));
    workbench.openFloating('ws', WorkbenchTabId.shell('Two'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    // Menu opened, but split entries follow the panel's own size threshold.
    expect(find.text('Close Others'), findsOneWidget);
    expect(find.text('Split Right'), findsNothing);
    expect(find.text('Split Down'), findsNothing);
  });

  testWidgets('title-bar split menu splits the focused group down', (
    tester,
  ) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(widePlacement);
    cubit.setActiveWorkspace('ws');
    workbench.openFloating('ws', WorkbenchTabId.shell('One'));
    workbench.openFloating('ws', WorkbenchTabId.shell('Two'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split Down'));
    await tester.pumpAndSettle();

    final layout = workbench.floatingLayout('ws');
    expect(layout.groups.length, 2);
    expect(layout.root, isA<SplitBranch>());
    expect((layout.root as SplitBranch).axis, Axis.vertical);
    expect(find.byType(FloatingGroupHost), findsNWidgets(2));
  });

  testWidgets('dragging a tab chip onto another group body moves the tab', (
    tester,
  ) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(widePlacement);
    cubit.setActiveWorkspace('ws');
    workbench.openFloating('ws', WorkbenchTabId.shell('One'));
    workbench.openFloating('ws', WorkbenchTabId.shell('Two'));
    workbench.splitTab(
      'ws',
      WorkbenchTabId.shell('Two'),
      axis: Axis.horizontal,
      before: false,
      floating: true,
    );
    await tester.pumpAndSettle();

    // 'One' lives in g0 (left pane); drag its chip onto g1's body center.
    final source = tester.getCenter(find.text('One'));
    final target = tester.getCenter(
      find.byKey(const ValueKey('floating_group_host_g1')),
    );
    final gesture = await tester.startGesture(
      source,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // Move in steps so the drag controller samples positions over g0's body
    // before settling over g1 (center zone → moveTab).
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy((target - source) / 5);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final layout = workbench.floatingLayout('ws');
    expect(layout.groups['g1']!.order, [
      WorkbenchTabId.shell('Two'),
      WorkbenchTabId.shell('One'),
    ]);
    expect(layout.focusedGroupId, 'g1');
  });

  testWidgets('empty launcher still renders when there are no tabs', (
    tester,
  ) async {
    final cubit = FloatingWorkspaceCubit();
    final workbench = WorkbenchCubit();
    addTearDown(cubit.close);
    addTearDown(workbench.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, workbench: workbench, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(widePlacement);
    cubit.setActiveWorkspace('ws');
    await tester.pumpAndSettle();

    expect(find.byType(FloatingGroupHost), findsNothing);
    expect(find.byType(FloatingWorkspaceEmpty), findsOneWidget);
  });
}

class _FakeSurface extends FloatingSurface {
  @override
  String get id => 'terminal';

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  Future<void> activate(FloatingTab tab) async {}

  @override
  Widget build(BuildContext context, FloatingTab tab) =>
      const ColoredBox(color: Colors.red, child: Text('fake-body'));

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final label = payload is String && payload.isNotEmpty ? payload : 'fake';
    return FloatingTab(
      id: 'fake:$label',
      surfaceId: id,
      title: label,
      payload: payload,
    );
  }
}
