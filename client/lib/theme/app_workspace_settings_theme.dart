import 'package:flutter/material.dart';

/// Global typography, spacing, and control metrics for workspace settings
/// surfaces (config, layout, and similar two-column settings UIs).
class AppWorkspaceSettingsTokens extends ThemeExtension<AppWorkspaceSettingsTokens> {
  const AppWorkspaceSettingsTokens({
    this.settingCardBorderRadius = 14,
    this.settingRowPadding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.settingGroupHeaderPadding = const EdgeInsets.fromLTRB(20, 20, 20, 8),
    this.titleSubtitleGap = 4,
    this.labelTrailingGap = 24,
    this.rowTitleFontSize = 13,
    this.rowSubtitleFontSize = 12,
    this.groupHeaderFontSize = 12,
    this.groupHeaderLetterSpacing = 0.2,
    this.groupHeaderOpacity = 0.72,
    this.rowSubtitleOpacity = 0.55,
    this.dropdownMinWidth = 140,
    this.dropdownHorizontalPadding = 4,
    this.dropdownBorderRadius = 10,
    this.dropdownIconOpacity = 0.55,
    this.dropdownLabelFontSize = 13,
    this.segmentedIconSize = 18,
    this.segmentHorizontalPadding = 10,
    this.segmentVerticalPadding = 7,
    this.segmentCornerRadius = 10,
    this.workspaceHeadingTitleFontSize = 15,
    this.workspaceHeadingTitleFontWeight = FontWeight.w800,
    this.workspaceHeadingTitleSubtitleGap = 6,
    this.workspaceHeadingSubtitleFontSize = 14,
    this.workspaceHeadingSubtitleHeight = 1.25,
    this.workspaceHeadingSubtitleOpacity = 0.64,
  });

  final double settingCardBorderRadius;
  final EdgeInsets settingRowPadding;
  final EdgeInsets settingGroupHeaderPadding;
  final double titleSubtitleGap;
  final double labelTrailingGap;

  final double rowTitleFontSize;
  final double rowSubtitleFontSize;
  final double groupHeaderFontSize;
  final double groupHeaderLetterSpacing;
  final double groupHeaderOpacity;
  final double rowSubtitleOpacity;

  final double dropdownMinWidth;
  final double dropdownHorizontalPadding;
  final double dropdownBorderRadius;
  final double dropdownIconOpacity;
  final double dropdownLabelFontSize;

  final double segmentedIconSize;
  final double segmentHorizontalPadding;
  final double segmentVerticalPadding;
  final double segmentCornerRadius;

  final double workspaceHeadingTitleFontSize;
  final FontWeight workspaceHeadingTitleFontWeight;
  final double workspaceHeadingTitleSubtitleGap;
  final double workspaceHeadingSubtitleFontSize;
  final double workspaceHeadingSubtitleHeight;
  final double workspaceHeadingSubtitleOpacity;

  static AppWorkspaceSettingsTokens of(BuildContext context) {
    return Theme.of(context).extension<AppWorkspaceSettingsTokens>() ??
        const AppWorkspaceSettingsTokens();
  }

  TextStyle rowTitleStyle(Color onSurface) {
    return TextStyle(
      fontSize: rowTitleFontSize,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: onSurface,
    );
  }

  TextStyle rowSubtitleStyle(Color onSurface) {
    return TextStyle(
      fontSize: rowSubtitleFontSize,
      fontWeight: FontWeight.w500,
      height: 1.35,
      color: onSurface.withValues(alpha: rowSubtitleOpacity),
    );
  }

  TextStyle groupHeaderStyle(Color onSurface) {
    return TextStyle(
      fontSize: groupHeaderFontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: groupHeaderLetterSpacing,
      color: onSurface.withValues(alpha: groupHeaderOpacity),
    );
  }

  TextStyle workspaceHeadingTitleStyle(Color onSurface) {
    return TextStyle(
      fontSize: workspaceHeadingTitleFontSize,
      fontWeight: workspaceHeadingTitleFontWeight,
      color: onSurface,
    );
  }

  TextStyle workspaceHeadingSubtitleStyle(Color onSurface) {
    return TextStyle(
      fontSize: workspaceHeadingSubtitleFontSize,
      height: workspaceHeadingSubtitleHeight,
      color: onSurface.withValues(alpha: workspaceHeadingSubtitleOpacity),
    );
  }

  @override
  AppWorkspaceSettingsTokens copyWith({
    double? settingCardBorderRadius,
    EdgeInsets? settingRowPadding,
    EdgeInsets? settingGroupHeaderPadding,
    double? titleSubtitleGap,
    double? labelTrailingGap,
    double? rowTitleFontSize,
    double? rowSubtitleFontSize,
    double? groupHeaderFontSize,
    double? groupHeaderLetterSpacing,
    double? groupHeaderOpacity,
    double? rowSubtitleOpacity,
    double? dropdownMinWidth,
    double? dropdownHorizontalPadding,
    double? dropdownBorderRadius,
    double? dropdownIconOpacity,
    double? dropdownLabelFontSize,
    double? segmentedIconSize,
    double? segmentHorizontalPadding,
    double? segmentVerticalPadding,
    double? segmentCornerRadius,
    double? workspaceHeadingTitleFontSize,
    FontWeight? workspaceHeadingTitleFontWeight,
    double? workspaceHeadingTitleSubtitleGap,
    double? workspaceHeadingSubtitleFontSize,
    double? workspaceHeadingSubtitleHeight,
    double? workspaceHeadingSubtitleOpacity,
  }) {
    return AppWorkspaceSettingsTokens(
      settingCardBorderRadius:
          settingCardBorderRadius ?? this.settingCardBorderRadius,
      settingRowPadding: settingRowPadding ?? this.settingRowPadding,
      settingGroupHeaderPadding:
          settingGroupHeaderPadding ?? this.settingGroupHeaderPadding,
      titleSubtitleGap: titleSubtitleGap ?? this.titleSubtitleGap,
      labelTrailingGap: labelTrailingGap ?? this.labelTrailingGap,
      rowTitleFontSize: rowTitleFontSize ?? this.rowTitleFontSize,
      rowSubtitleFontSize: rowSubtitleFontSize ?? this.rowSubtitleFontSize,
      groupHeaderFontSize: groupHeaderFontSize ?? this.groupHeaderFontSize,
      groupHeaderLetterSpacing:
          groupHeaderLetterSpacing ?? this.groupHeaderLetterSpacing,
      groupHeaderOpacity: groupHeaderOpacity ?? this.groupHeaderOpacity,
      rowSubtitleOpacity: rowSubtitleOpacity ?? this.rowSubtitleOpacity,
      dropdownMinWidth: dropdownMinWidth ?? this.dropdownMinWidth,
      dropdownHorizontalPadding:
          dropdownHorizontalPadding ?? this.dropdownHorizontalPadding,
      dropdownBorderRadius: dropdownBorderRadius ?? this.dropdownBorderRadius,
      dropdownIconOpacity: dropdownIconOpacity ?? this.dropdownIconOpacity,
      dropdownLabelFontSize:
          dropdownLabelFontSize ?? this.dropdownLabelFontSize,
      segmentedIconSize: segmentedIconSize ?? this.segmentedIconSize,
      segmentHorizontalPadding:
          segmentHorizontalPadding ?? this.segmentHorizontalPadding,
      segmentVerticalPadding:
          segmentVerticalPadding ?? this.segmentVerticalPadding,
      segmentCornerRadius: segmentCornerRadius ?? this.segmentCornerRadius,
      workspaceHeadingTitleFontSize:
          workspaceHeadingTitleFontSize ?? this.workspaceHeadingTitleFontSize,
      workspaceHeadingTitleFontWeight: workspaceHeadingTitleFontWeight ??
          this.workspaceHeadingTitleFontWeight,
      workspaceHeadingTitleSubtitleGap: workspaceHeadingTitleSubtitleGap ??
          this.workspaceHeadingTitleSubtitleGap,
      workspaceHeadingSubtitleFontSize: workspaceHeadingSubtitleFontSize ??
          this.workspaceHeadingSubtitleFontSize,
      workspaceHeadingSubtitleHeight: workspaceHeadingSubtitleHeight ??
          this.workspaceHeadingSubtitleHeight,
      workspaceHeadingSubtitleOpacity: workspaceHeadingSubtitleOpacity ??
          this.workspaceHeadingSubtitleOpacity,
    );
  }

  @override
  ThemeExtension<AppWorkspaceSettingsTokens> lerp(
    covariant ThemeExtension<AppWorkspaceSettingsTokens>? other,
    double t,
  ) {
    if (other is! AppWorkspaceSettingsTokens) return this;
    return AppWorkspaceSettingsTokens(
      settingCardBorderRadius: _lerpD(
        settingCardBorderRadius,
        other.settingCardBorderRadius,
        t,
      ),
      settingRowPadding:
          EdgeInsets.lerp(settingRowPadding, other.settingRowPadding, t)!,
      settingGroupHeaderPadding: EdgeInsets.lerp(
        settingGroupHeaderPadding,
        other.settingGroupHeaderPadding,
        t,
      )!,
      titleSubtitleGap: _lerpD(titleSubtitleGap, other.titleSubtitleGap, t),
      labelTrailingGap: _lerpD(labelTrailingGap, other.labelTrailingGap, t),
      rowTitleFontSize: _lerpD(rowTitleFontSize, other.rowTitleFontSize, t),
      rowSubtitleFontSize:
          _lerpD(rowSubtitleFontSize, other.rowSubtitleFontSize, t),
      groupHeaderFontSize:
          _lerpD(groupHeaderFontSize, other.groupHeaderFontSize, t),
      groupHeaderLetterSpacing: _lerpD(
        groupHeaderLetterSpacing,
        other.groupHeaderLetterSpacing,
        t,
      ),
      groupHeaderOpacity:
          _lerpD(groupHeaderOpacity, other.groupHeaderOpacity, t),
      rowSubtitleOpacity:
          _lerpD(rowSubtitleOpacity, other.rowSubtitleOpacity, t),
      dropdownMinWidth: _lerpD(dropdownMinWidth, other.dropdownMinWidth, t),
      dropdownHorizontalPadding: _lerpD(
        dropdownHorizontalPadding,
        other.dropdownHorizontalPadding,
        t,
      ),
      dropdownBorderRadius:
          _lerpD(dropdownBorderRadius, other.dropdownBorderRadius, t),
      dropdownIconOpacity:
          _lerpD(dropdownIconOpacity, other.dropdownIconOpacity, t),
      dropdownLabelFontSize:
          _lerpD(dropdownLabelFontSize, other.dropdownLabelFontSize, t),
      segmentedIconSize: _lerpD(segmentedIconSize, other.segmentedIconSize, t),
      segmentHorizontalPadding: _lerpD(
        segmentHorizontalPadding,
        other.segmentHorizontalPadding,
        t,
      ),
      segmentVerticalPadding: _lerpD(
        segmentVerticalPadding,
        other.segmentVerticalPadding,
        t,
      ),
      segmentCornerRadius:
          _lerpD(segmentCornerRadius, other.segmentCornerRadius, t),
      workspaceHeadingTitleFontSize: _lerpD(
        workspaceHeadingTitleFontSize,
        other.workspaceHeadingTitleFontSize,
        t,
      ),
      workspaceHeadingTitleFontWeight: t < 0.5
          ? workspaceHeadingTitleFontWeight
          : other.workspaceHeadingTitleFontWeight,
      workspaceHeadingTitleSubtitleGap: _lerpD(
        workspaceHeadingTitleSubtitleGap,
        other.workspaceHeadingTitleSubtitleGap,
        t,
      ),
      workspaceHeadingSubtitleFontSize: _lerpD(
        workspaceHeadingSubtitleFontSize,
        other.workspaceHeadingSubtitleFontSize,
        t,
      ),
      workspaceHeadingSubtitleHeight: _lerpD(
        workspaceHeadingSubtitleHeight,
        other.workspaceHeadingSubtitleHeight,
        t,
      ),
      workspaceHeadingSubtitleOpacity: _lerpD(
        workspaceHeadingSubtitleOpacity,
        other.workspaceHeadingSubtitleOpacity,
        t,
      ),
    );
  }

  static double _lerpD(double a, double b, double t) => a + (b - a) * t;
}
