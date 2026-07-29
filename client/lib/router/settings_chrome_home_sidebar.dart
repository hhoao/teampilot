import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../pages/home_workspace/home_workspace_global_section.dart';
import '../pages/home_workspace/home_workspace_library_view.dart';
import '../pages/home_workspace/home_workspace_sidebar.dart';

/// Home global nav for hub/settings chrome on Android and narrow viewports.
class SettingsChromeHomeSidebar extends StatelessWidget {
  const SettingsChromeHomeSidebar({required this.path, super.key});

  final String path;

  @visibleForTesting
  static HomeGlobalView? activeGlobalView(String path) {
    if (path.startsWith('/skills')) return HomeGlobalView.skills;
    if (path.startsWith('/plugins')) return HomeGlobalView.plugins;
    if (path.startsWith('/mcp')) return HomeGlobalView.mcp;
    if (path.startsWith('/extensions')) return HomeGlobalView.extensions;
    if (path.startsWith('/providers')) return HomeGlobalView.providers;
    return null;
  }

  @visibleForTesting
  static String routeForGlobalView(HomeGlobalView view) {
    return switch (view) {
      HomeGlobalView.skills => '/skills',
      HomeGlobalView.plugins => '/plugins',
      HomeGlobalView.mcp => '/mcp',
      HomeGlobalView.extensions => '/extensions',
      HomeGlobalView.providers => '/providers',
      _ => view.homeLocation,
    };
  }

  void _navigate(BuildContext context, String location) {
    TpSidebarScope.maybeOf(context)?.setOpenMobile(false);
    context.go(location);
  }

  @override
  Widget build(BuildContext context) {
    return HomeSidebar(
      activeGlobalView: activeGlobalView(path),
      onSelectAllWorkspaces: () => _navigate(context, '/home-v2'),
      onSelectGlobalView: (view) =>
          _navigate(context, routeForGlobalView(view)),
      onSelectLibraryView: (HomeLibraryView view) => _navigate(
        context,
        '/home-v2',
      ),
    );
  }
}
