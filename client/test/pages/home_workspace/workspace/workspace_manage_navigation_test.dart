import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

/// Regression: [openWorkspaceManagementRoute] must not collapse the *docked*
/// sidebar on desktop. The drawer-close is a narrow-only concern; on wide
/// layouts `sidebarVisible` is the persistent docked-pane intent, so clearing
/// it here left the sidebar hidden after leaving manage (user had to re-toggle).
void main() {
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
    createdAt: 1,
  );

  Future<LayoutCubit> pumpManageOpener(
    WidgetTester tester, {
    required Size size,
  }) async {
    final layout = LayoutCubit();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(layout.close);

    final router = GoRouter(
      initialLocation: '/home-v2/workspace/ws-1',
      routes: [
        GoRoute(
          path: '/home-v2/workspace/:id',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-manage'),
                onPressed: () =>
                    openWorkspaceManagementRoute(context, workspace),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        // Providers/scope must sit below MaterialApp's MediaQuery so
        // TpSidebarProvider can derive isMobile from the view size.
        builder: (context, child) => BlocProvider<LayoutCubit>.value(
          value: layout,
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return layout;
  }

  testWidgets('wide: opening manage keeps the docked sidebar visible', (
    tester,
  ) async {
    final layout = await pumpManageOpener(tester, size: const Size(1400, 900));
    expect(layout.state.preferences.sidebarVisible, isTrue);

    await tester.tap(find.byKey(const Key('open-manage')));
    await tester.pumpAndSettle();

    expect(
      layout.state.preferences.sidebarVisible,
      isTrue,
      reason: 'desktop manage nav must not clear the docked sidebar intent',
    );
    expect(layout.state.preferences.rightToolsVisible, isFalse);
  });

  testWidgets('narrow: opening manage closes the mobile drawer', (
    tester,
  ) async {
    final layout = await pumpManageOpener(tester, size: const Size(600, 900));
    expect(layout.state.preferences.sidebarVisible, isTrue);

    await tester.tap(find.byKey(const Key('open-manage')));
    await tester.pumpAndSettle();

    expect(
      layout.state.preferences.sidebarVisible,
      isFalse,
      reason: 'narrow manage nav slides the drawer shut before manage takes over',
    );
  });
}
