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

void main() {
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
                body: FloatingWorkspaceHost(
                  child: SizedBox.expand(child: Text('shell-body')),
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

    cubit.setActiveWorkspace('ws-1');
    cubit.ensureTab(
      const FloatingTab(
        id: 'terminal:a',
        surfaceId: 'terminal',
        title: 'Terminal',
        payload: 'a',
      ),
    );
    cubit.ensureOpen();

    await tester.pumpWidget(
      wrap(cubit: cubit, registry: registry, insets: insets),
    );
    await tester.pump();
    expect(find.text('fake-body'), findsOneWidget);

    cubit.minimize();
    await tester.pump();
    // Bloc/cubit listener setState lands on the next frame in widget tests.
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
    expect(
      find.text('fake-body', skipOffstage: false),
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
