import 'package:flutter/material.dart';

/// Title-bar tab control for the workspace home shell.
class HomeTabScope extends InheritedWidget {
  const HomeTabScope({
    required this.openProject,
    required super.child,
    super.key,
  });

  /// When [activate] is false, adds a project tab without leaving the current route.
  final void Function(String projectId, {bool activate}) openProject;

  static HomeTabScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HomeTabScope>();
  }

  static void openInTab(
    BuildContext context,
    String projectId, {
    bool activate = true,
  }) {
    maybeOf(context)?.openProject(projectId, activate: activate);
  }

  @override
  bool updateShouldNotify(HomeTabScope oldWidget) => false;
}
