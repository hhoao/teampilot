import 'package:flutter/material.dart';

/// Title-bar tab control for the workspace home shell.
class HomeWorkspaceTabScope extends InheritedWidget {
  const HomeWorkspaceTabScope({
    required this.openProject,
    required super.child,
    super.key,
  });

  /// When [activate] is false, adds a project tab without leaving the current route.
  final void Function(String projectId, {bool activate}) openProject;

  static HomeWorkspaceTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HomeWorkspaceTabScope>();
  }

  static void openInTab(
    BuildContext context,
    String projectId, {
    bool activate = true,
  }) {
    maybeOf(context)?.openProject(projectId, activate: activate);
  }

  @override
  bool updateShouldNotify(HomeWorkspaceTabScope oldWidget) => false;
}
