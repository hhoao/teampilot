import 'package:flutter/widgets.dart';

import 'workspace_config_section.dart';

/// Foreground/background state for a kept-alive title-bar workspace tab.
///
/// Provided by [_WorkspaceTabSlot] so [WorkspacePage] does not take a
/// [routeActive] constructor arg that changes on every sibling tab switch
/// (which would rebuild the whole subtree).
class WorkspaceRouteActiveScope extends InheritedWidget {
  const WorkspaceRouteActiveScope({
    required this.routeActive,
    this.view,
    this.configSection,
    required super.child,
    super.key,
  });

  final bool routeActive;
  final String? view;
  final WorkspaceConfigSection? configSection;

  /// Registers a dependency so callers in `build` / `didChangeDependencies`
  /// are re-notified when the tab switches foreground/background.
  ///
  /// Must not be called outside build / `didChangeDependencies` (e.g. from
  /// `initState` or event callbacks) — use [maybePeekOf] there.
  static WorkspaceRouteActiveScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<
      WorkspaceRouteActiveScope
    >();
  }

  static bool routeActiveOf(BuildContext context) {
    return maybeOf(context)?.routeActive ?? true;
  }

  /// Non-registering read for `initState` and event callbacks, where a
  /// dependency cannot be established. The value is a snapshot from the last
  /// build — callers that must react to tab switches should register via
  /// [maybeOf] in `build` / `didChangeDependencies` instead.
  static WorkspaceRouteActiveScope? maybePeekOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
  }

  static bool peekRouteActiveOf(BuildContext context) {
    return maybePeekOf(context)?.routeActive ?? true;
  }

  @override
  bool updateShouldNotify(WorkspaceRouteActiveScope oldWidget) {
    return routeActive != oldWidget.routeActive ||
        view != oldWidget.view ||
        configSection != oldWidget.configSection;
  }
}
