import 'package:flutter/foundation.dart' show ValueListenable;
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
    this.activeListenable,
    this.routeRevisionListenable,
    required super.child,
    super.key,
  });

  final bool routeActive;
  final String? view;
  final WorkspaceConfigSection? configSection;

  /// Stable [ValueListenable] mirroring [routeActive] for consumers that must
  /// react to activation without registering an inherited dependency.
  ///
  /// Registering a dependency here makes the whole (heavy) subtree rebuild on
  /// every tab switch. Consumers instead listen to this notifier, so a
  /// background tab never rebuilds when a sibling tab activates.
  final ValueListenable<bool>? activeListenable;

  /// Bumped when this slot's activation or route inputs ([view],
  /// [configSection]) change while it stays in the foreground.
  ///
  /// Query-only navigation inside the same tab (e.g. `view=manage`) must
  /// resync the page even though no tab switch happens. Background tabs keep
  /// stable inputs, so they are never notified.
  final ValueListenable<int>? routeRevisionListenable;

  /// Registers a dependency so callers in `build` / `didChangeDependencies`
  /// are re-notified when the tab switches foreground/background.
  ///
  /// Must not be called outside build / `didChangeDependencies` (e.g. from
  /// `initState` or event callbacks) — use [maybePeekOf] there.
  static WorkspaceRouteActiveScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WorkspaceRouteActiveScope>();
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

  /// Activation signal without registering an inherited dependency.
  ///
  /// Consumers that only need to react to foreground/background changes should
  /// listen to this instead of calling [routeActiveOf], which would rebuild
  /// them (and their subtree) on every tab switch.
  static ValueListenable<bool>? peekActiveListenableOf(BuildContext context) {
    return maybePeekOf(context)?.activeListenable;
  }

  /// Route-resync signal without registering an inherited dependency.
  ///
  /// Fires on activation edges and on `view` / `configSection` changes of the
  /// foreground tab, so pages can follow query-only navigation (e.g.
  /// `view=manage`) without rebuilding on sibling-tab switches.
  static ValueListenable<int>? peekRouteRevisionOf(BuildContext context) {
    return maybePeekOf(context)?.routeRevisionListenable;
  }

  @override
  bool updateShouldNotify(WorkspaceRouteActiveScope oldWidget) {
    return routeActive != oldWidget.routeActive ||
        view != oldWidget.view ||
        configSection != oldWidget.configSection;
  }
}
