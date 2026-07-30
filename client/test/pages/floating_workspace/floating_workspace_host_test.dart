import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/floating_workspace/floating_panel_visibility.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/floating_workspace_tab.dart';
import 'package:teampilot/pages/floating_workspace/floating_workspace_host.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/floating_workspace/floating_maximize_insets.dart';
import 'package:teampilot/services/floating_workspace/floating_surface.dart';
import 'package:teampilot/services/floating_workspace/floating_surface_registry.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';

void main() {
  Widget wrap({
    required FloatingWorkspaceCubit cubit,
    required FloatingSurfaceRegistry registry,
    required FloatingMaximizeInsets insets,
    WorkspaceTerminalRegistry? terminalRegistry,
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
            child: RepositoryProvider<WorkspaceTerminalRegistry>.value(
              value: terminalRegistry ?? WorkspaceTerminalRegistry(),
              child: BlocProvider.value(
                value: cubit,
                child: const Scaffold(
                  body: FloatingWorkspaceHost(
                    child: SizedBox.expand(child: Text('shell-body')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('host shows panel when open, hides when hidden', (tester) async {
    final cubit = FloatingWorkspaceCubit();
    addTearDown(cubit.close);
    final registry = FloatingSurfaceRegistry([_FakeSurface()]);
    final insets = FloatingMaximizeInsets();
    addTearDown(insets.dispose);

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );

    expect(find.text('shell-body'), findsOneWidget);
    expect(find.byKey(const Key('floating_workspace_panel')), findsNothing);
    expect(find.byKey(const Key('floating_workspace_toggle')), findsOneWidget);

    cubit.toggle();
    await tester.pump();

    expect(cubit.state.visibility, FloatingPanelVisibility.open);
    expect(find.byKey(const Key('floating_workspace_panel')), findsOneWidget);
  });

  testWidgets('minimized with tabs keeps panel mounted offstage', (
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
    await tester.pump();

    // Drive open + tab through the live widget tree so BlocBuilder is subscribed.
    cubit.setActiveWorkspace('ws-1');
    cubit.ensureOpen();
    await tester.pump();
    cubit.ensureTab(
      const FloatingTab(
        id: 'terminal:a',
        surfaceId: 'terminal',
        title: 'Terminal',
        payload: 'a',
      ),
    );
    await tester.pump();
    expect(find.text('fake-body'), findsOneWidget);

    cubit.minimize();
    await tester.pump();

    expect(cubit.state.visibility, FloatingPanelVisibility.minimized);
    expect(cubit.state.activeBucket.tabs, isNotEmpty);
    expect(
      find.byKey(
        const Key('floating_workspace_panel_keep_alive'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('fake-body', skipOffstage: false), findsOneWidget);
  });

  testWidgets('attention dot shows while minimized with attention', (
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
    cubit.minimize();
    cubit.setAttention(true);
    await tester.pump();

    expect(find.byKey(const Key('floating_workspace_toggle')), findsOneWidget);
    // Amber 8px attention dot sits in the toggle Stack (Orca unread convention).
    expect(
      find.descendant(
        of: find.byKey(const Key('floating_workspace_toggle')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration! as BoxDecoration).color ==
                  const Color(0xFFF59E0B),
        ),
      ),
      findsOneWidget,
    );
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
      const Text('fake-body');

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
