import 'package:flutter/widgets.dart';

/// Foreground/background state for the kept-alive home body layer.
///
/// Provided by [_HomeBodyLayer] so [HomePage] does not take a [routeActive]
/// constructor arg that changes on every title-bar tab switch.
class HomeRouteActiveScope extends InheritedWidget {
  const HomeRouteActiveScope({
    required this.routeActive,
    required super.child,
    super.key,
  });

  final bool routeActive;

  static HomeRouteActiveScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<HomeRouteActiveScope>();
  }

  static bool routeActiveOf(BuildContext context) {
    return maybeOf(context)?.routeActive ?? true;
  }

  @override
  bool updateShouldNotify(HomeRouteActiveScope oldWidget) {
    return routeActive != oldWidget.routeActive;
  }
}
