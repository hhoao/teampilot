import 'dart:ui';

import 'package:flutter/material.dart';

/// Defines the visual properties for panes, resizers, and tabs in the hierarchy.
///
/// Can be used as a [ThemeExtension] with [ThemeData.extensions] or with the
/// [PaneTheme] inherited widget.
class PaneThemeData extends ThemeExtension<PaneThemeData> {
  /// The color of the resizer in its default state.
  final Color? resizerColor;

  /// The color of the resizer when hovered.
  final Color? resizerHoverColor;

  /// The color of the resizer when it has input focus.
  final Color? resizerFocusedColor;

  /// The visual thickness of the resizer.
  final double resizerThickness;

  /// The thickness used for hit-testing (drag area).
  ///
  /// Usually larger than [resizerThickness] to make it easier to grab.
  final double resizerHitTestThickness;

  /// The background color for the tab header area.
  final Color? tabHeaderColor;

  /// The background color of a tab.
  final Color? tabBackground;

  /// The background color of a selected tab.
  final Color? tabSelectedBackground;

  /// The color of the label in an unselected tab.
  final Color? tabLabelColor;

  /// The color of the label in a selected tab.
  final Color? tabSelectedLabelColor;

  /// Creates a [PaneThemeData].
  const PaneThemeData({
    this.resizerColor,
    this.resizerHoverColor,
    this.resizerFocusedColor,
    this.resizerThickness = 4.0,
    double? resizerHitTestThickness,
    this.tabHeaderColor,
    this.tabBackground,
    this.tabSelectedBackground,
    this.tabLabelColor,
    this.tabSelectedLabelColor,
  }) : resizerHitTestThickness =
            resizerHitTestThickness ?? resizerThickness + 4.0;

  @override
  PaneThemeData copyWith({
    Color? resizerColor,
    Color? resizerHoverColor,
    Color? resizerFocusedColor,
    double? resizerThickness,
    double? resizerHitTestThickness,
    Color? tabHeaderColor,
    Color? tabBackground,
    Color? tabSelectedBackground,
    Color? tabLabelColor,
    Color? tabSelectedLabelColor,
  }) {
    return PaneThemeData(
      resizerColor: resizerColor ?? this.resizerColor,
      resizerHoverColor: resizerHoverColor ?? this.resizerHoverColor,
      resizerFocusedColor: resizerFocusedColor ?? this.resizerFocusedColor,
      resizerThickness: resizerThickness ?? this.resizerThickness,
      resizerHitTestThickness:
          resizerHitTestThickness ?? this.resizerHitTestThickness,
      tabHeaderColor: tabHeaderColor ?? this.tabHeaderColor,
      tabBackground: tabBackground ?? this.tabBackground,
      tabSelectedBackground:
          tabSelectedBackground ?? this.tabSelectedBackground,
      tabLabelColor: tabLabelColor ?? this.tabLabelColor,
      tabSelectedLabelColor:
          tabSelectedLabelColor ?? this.tabSelectedLabelColor,
    );
  }

  @override
  PaneThemeData lerp(covariant PaneThemeData? other, double t) {
    if (other == null) return this;
    return PaneThemeData(
      resizerColor: Color.lerp(resizerColor, other.resizerColor, t),
      resizerHoverColor: Color.lerp(
        resizerHoverColor,
        other.resizerHoverColor,
        t,
      ),
      resizerFocusedColor: Color.lerp(
        resizerFocusedColor,
        other.resizerFocusedColor,
        t,
      ),
      resizerThickness:
          lerpDouble(resizerThickness, other.resizerThickness, t) ??
              resizerThickness,
      resizerHitTestThickness: lerpDouble(
            resizerHitTestThickness,
            other.resizerHitTestThickness,
            t,
          ) ??
          resizerHitTestThickness,
      tabHeaderColor: Color.lerp(tabHeaderColor, other.tabHeaderColor, t),
      tabBackground: Color.lerp(tabBackground, other.tabBackground, t),
      tabSelectedBackground: Color.lerp(
        tabSelectedBackground,
        other.tabSelectedBackground,
        t,
      ),
      tabLabelColor: Color.lerp(tabLabelColor, other.tabLabelColor, t),
      tabSelectedLabelColor: Color.lerp(
        tabSelectedLabelColor,
        other.tabSelectedLabelColor,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaneThemeData &&
        other.resizerColor == resizerColor &&
        other.resizerHoverColor == resizerHoverColor &&
        other.resizerFocusedColor == resizerFocusedColor &&
        other.resizerThickness == resizerThickness &&
        other.resizerHitTestThickness == resizerHitTestThickness &&
        other.tabHeaderColor == tabHeaderColor &&
        other.tabBackground == tabBackground &&
        other.tabSelectedBackground == tabSelectedBackground &&
        other.tabLabelColor == tabLabelColor &&
        other.tabSelectedLabelColor == tabSelectedLabelColor;
  }

  @override
  int get hashCode => Object.hash(
        resizerColor,
        resizerHoverColor,
        resizerFocusedColor,
        resizerThickness,
        resizerHitTestThickness,
        tabHeaderColor,
        tabBackground,
        tabSelectedBackground,
        tabLabelColor,
        tabSelectedLabelColor,
      );
}

/// An inherited widget that defines the visual properties for [PaneThemeData] in this widget's subtree.
class PaneTheme extends InheritedWidget {
  /// The [PaneThemeData] argument.
  final PaneThemeData data;

  /// Creates a [PaneTheme].
  const PaneTheme({
    super.key,
    required this.data,
    required super.child,
  });

  /// The [PaneThemeData] from the closest [PaneTheme] instance that encloses the given context.
  ///
  /// Falls back to [ThemeData.extensions] if no [PaneTheme] is found.
  /// If neither is found, returns a default [PaneThemeData].
  static PaneThemeData of(BuildContext context) {
    final PaneTheme? result =
        context.dependOnInheritedWidgetOfExactType<PaneTheme>();
    if (result != null) return result.data;

    // Fallback to ThemeExtension
    final extension = Theme.of(context).extension<PaneThemeData>();
    return extension ?? const PaneThemeData();
  }

  @override
  bool updateShouldNotify(PaneTheme oldWidget) {
    return data != oldWidget.data;
  }
}
