import 'package:flutter/material.dart';

/// Vertical contentPadding used by [appMultilineInputDecoration] (each side).
/// Matches shadcn `py-2`.
const double kAppTextareaVerticalPadding = 8;

/// Horizontal contentPadding (each side). Matches shadcn `px-3`.
const double kAppTextareaHorizontalPadding = 12;

/// Outline border width budget for outer height (idle 1px; focused uses ring).
///
/// Top + bottom are applied via `borderWidth * 2` in
/// [appTextareaHeightForLines] / [appTextareaVerticalChrome].
const double kAppTextareaBorderWidth = 1;

/// Focus ring spread outside the border (shadcn `ring-[3px]`).
const double kAppTextareaFocusRingSpread = 3;

/// Total vertical chrome (padding + border) for the AppTextarea path.
///
/// Convention: [AppTextarea] `minHeight` / `maxHeight` are **outer** shell
/// heights including this chrome. Compose / borderless [AppTextareaShell]
/// children should keep using `lineHeight * n` (chrome = 0).
double appTextareaVerticalChrome({
  double verticalPadding = kAppTextareaVerticalPadding,
  double borderWidth = kAppTextareaBorderWidth,
}) =>
    verticalPadding * 2 + borderWidth * 2;

/// Outer shell height for [lines] of [style], including AppTextarea chrome.
double appTextareaHeightForLines(
  TextStyle style, {
  required int lines,
  double verticalPadding = kAppTextareaVerticalPadding,
  double borderWidth = kAppTextareaBorderWidth,
}) {
  assert(lines >= 1);
  final fontSize = style.fontSize ?? 14;
  final heightFactor = style.height ?? 20 / 14;
  final lineHeight = fontSize * heightFactor;
  return lines * lineHeight +
      appTextareaVerticalChrome(
        verticalPadding: verticalPadding,
        borderWidth: borderWidth,
      );
}
