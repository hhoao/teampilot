import 'package:flutter/material.dart';

/// Title-bar tab control for the workspace home shell.
class HomeTabScope extends InheritedWidget {
  const HomeTabScope({
    required this.openWorkspace,
    required super.child,
    super.key,
  });

  /// When [activate] is false, adds a workspace tab without leaving the current route.
  final void Function(String workspaceId, {bool activate}) openWorkspace;

  static HomeTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HomeTabScope>();
  }

  static void openInTab(
    BuildContext context,
    String workspaceId, {
    bool activate = true,
  }) {
    maybeOf(context)?.openWorkspace(workspaceId, activate: activate);
  }

  @override
  bool updateShouldNotify(HomeTabScope oldWidget) => false;
}
