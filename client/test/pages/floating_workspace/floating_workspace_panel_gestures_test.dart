import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_placement.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_panel.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/floating_workspace/floating_maximize_insets.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

void main() {
  const hostSize = Size(1400, 900);
  const placement = FloatingPanelPlacement(
    width: 600,
    height: 400,
    rightInset: 40,
    bottomInset: 80,
  );

  Widget wrap({
    required FloatingWorkspaceCubit cubit,
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
    );
  }

  test('restoreFloatingPanelBoundsFromMaximize follows pointer fraction', () {
    const maxRect = Rect.fromLTRB(20, 10, 1380, 860);
    const pointer = Offset(700, 30); // fracX = (700-20)/1360 = 0.5
    final restored = restoreFloatingPanelBoundsFromMaximize(
      maxRect: maxRect,
      hostSize: hostSize,
      hostLocalPointer: pointer,
      restoredWidth: 600,
      restoredHeight: 400,
    );
    expect(restored.width, 600);
    expect(restored.height, 400);
    expect(restored.left, closeTo(700 - 0.5 * 600, 0.1));
    expect(restored.top, closeTo(30 - 20, 0.1)); // titleBarHeight/2 = 20
  });

  testWidgets('panel and title both use surface with divider', (
    tester,
  ) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(placement);
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(MaterialApp)));
    final surface = theme.colorScheme.surface;
    final materials = tester.widgetList<Material>(find.byType(Material));
    expect(materials.any((m) => m.color == surface), isTrue);

    final titleFill = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .any(
          (d) => d.color == surface && d.border?.bottom != null,
        );
    expect(titleFill, isTrue);
  });

  testWidgets('double-tap title bar toggles maximize', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(placement);
    await tester.pump();

    final title = find.byKey(const Key('floating_workspace_title_drag'));
    expect(title, findsOneWidget);

    await tester.tap(title);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(title);
    await tester.pump();
    await tester.pump(kDoubleTapTimeout);

    expect(cubit.state.isMaximized, isTrue);
    expect(cubit.state.visibility, FloatingPanelVisibility.open);

    await tester.tap(title);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(title);
    await tester.pump();
    await tester.pump(kDoubleTapTimeout);

    expect(cubit.state.isMaximized, isFalse);
    expect(cubit.state.visibility, FloatingPanelVisibility.open);
  });

  testWidgets('drag while maximized restores and follows pointer', (
    tester,
  ) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);
    insets.update(EdgeInsets.zero);

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(placement);
    cubit.setMaximized(true);
    await tester.pump();

    final title = find.byKey(const Key('floating_workspace_title_drag'));
    final center = tester.getCenter(title);

    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(24, 16));
    await tester.pump();
    expect(cubit.state.isMaximized, isFalse);

    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(cubit.state.isMaximized, isFalse);
    final placed = cubit.state.panelPlacement!;
    expect(placed.width, 600);
    expect(placed.height, 400);
    await tester.pump(kDoubleTapTimeout);
  });

  testWidgets('title bar has bottom divider under tabs', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );
    cubit.ensureOpen();
    cubit.setPanelPlacement(placement);
    await tester.pump();

    expect(find.byKey(const Key('floating_workspace_title_drag')), findsOneWidget);
    final titleDecoration = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .where(
          (d) =>
              d.color != null &&
              d.border?.bottom != BorderSide.none &&
              d.border?.bottom != null,
        )
        .toList();
    expect(titleDecoration, isNotEmpty);
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
    return FloatingTab(
      id: 'fake:$workspaceId',
      surfaceId: id,
      title: 'fake',
      payload: payload,
    );
  }
}
