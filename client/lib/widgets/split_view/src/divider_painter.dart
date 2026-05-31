import 'package:flutter/material.dart';

/// The divider painter factory.
class DividerPainters {
  /// Builds a divider painter to set the background color.
  static DividerPainter background(
      {bool animationEnabled = DividerPainter.defaultAnimationEnabled,
      Duration animationDuration = DividerPainter.defaultAnimationDuration,
      Color? color,
      Color? highlightedColor}) {
    return DividerPainter(
        animationEnabled: animationEnabled,
        animationDuration: animationDuration,
        backgroundColor: color,
        highlightedBackgroundColor: highlightedColor);
  }

  /// Builds a dashed divider painter.
  static DividerPainter dashed(
      {double size = 10,
      double gap = 5,
      Color? backgroundColor,
      Color? highlightedBackgroundColor,
      bool animationEnabled = DividerPainter.defaultAnimationEnabled,
      Duration animationDuration = DividerPainter.defaultAnimationDuration,
      Color color = Colors.black,
      Color? highlightedColor,
      StrokeCap strokeCap = StrokeCap.square,
      double thickness = 1,
      double? highlightedThickness,
      double? highlightedGap}) {
    return _DashedDividerPainter(
        size: size,
        gap: gap,
        backgroundColor: backgroundColor,
        highlightedBackgroundColor: highlightedBackgroundColor,
        animationEnabled: animationEnabled,
        animationDuration: animationDuration,
        color: color,
        highlightedColor: highlightedColor,
        strokeCap: strokeCap,
        thickness: thickness,
        highlightedThickness: highlightedThickness,
        highlightedGap: highlightedGap);
  }

  /// Builds a grooved divider painter.
  static DividerPainter grooved1(
      {double size = 25,
      Color? backgroundColor,
      Color? highlightedBackgroundColor,
      bool animationEnabled = DividerPainter.defaultAnimationEnabled,
      Duration animationDuration = DividerPainter.defaultAnimationDuration,
      Color color = Colors.black38,
      Color? highlightedColor = Colors.black,
      StrokeCap strokeCap = StrokeCap.round,
      double thickness = 2,
      double? highlightedThickness = 4,
      double? highlightedSize = 40}) {
    return _GroovedDividerPainter1(
        size: size,
        backgroundColor: backgroundColor,
        highlightedBackgroundColor: highlightedBackgroundColor,
        animationEnabled: animationEnabled,
        animationDuration: animationDuration,
        color: color,
        highlightedColor: highlightedColor,
        strokeCap: strokeCap,
        thickness: thickness,
        highlightedThickness: highlightedThickness,
        highlightedSize: highlightedSize);
  }

  /// Builds a grooved divider painter.
  /// The [count] parameters defines the number of grooved for each side of the axis.
  static DividerPainter grooved2(
      {double size = 3,
      Color? backgroundColor,
      Color? highlightedBackgroundColor,
      bool animationEnabled = DividerPainter.defaultAnimationEnabled,
      Duration animationDuration = DividerPainter.defaultAnimationDuration,
      Color color = Colors.black38,
      double gap = 5,
      int count = 7,
      Color? highlightedColor = Colors.black,
      StrokeCap strokeCap = StrokeCap.round,
      double thickness = 2,
      int? highlightedCount = 13}) {
    return _GroovedDividerPainter2(
        size: size,
        backgroundColor: backgroundColor,
        highlightedBackgroundColor: highlightedBackgroundColor,
        animationEnabled: animationEnabled,
        animationDuration: animationDuration,
        color: color,
        gap: gap,
        count: count,
        highlightedColor: highlightedColor,
        strokeCap: strokeCap,
        thickness: thickness,
        highlightedCount: highlightedCount);
  }
}

/// Allows customizing the divider.
class DividerPainter {
  static const int backgroundKey = 0;

  static const bool defaultAnimationEnabled = true;
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);

  DividerPainter(
      {this.backgroundColor,
      this.highlightedBackgroundColor,
      this.animationEnabled = DividerPainter.defaultAnimationEnabled,
      this.animationDuration = DividerPainter.defaultAnimationDuration});

  final bool animationEnabled;
  final Color? backgroundColor;
  final Color? highlightedBackgroundColor;
  final Duration animationDuration;

  /// Builds a tween map for animations.
  Map<int, Tween> buildTween() {
    Map<int, Tween> map = <int, Tween>{};
    if (animationEnabled &&
        backgroundColor != null &&
        highlightedBackgroundColor != null) {
      map[DividerPainter.backgroundKey] =
          ColorTween(begin: backgroundColor, end: highlightedBackgroundColor);
    }
    return map;
  }

  /// Paints the divider.
  void paint(
      {required Axis dividerAxis,
      required bool resizable,
      required bool highlighted,
      required Canvas canvas,
      required Size dividerSize,
      required Map<int, dynamic> animatedValues}) {
    Color? color = backgroundColor;
    if (animationEnabled && animatedValues.containsKey(backgroundKey)) {
      color = animatedValues[backgroundKey];
    } else if (highlighted && highlightedBackgroundColor != null) {
      color = highlightedBackgroundColor;
    }

    if (color != null) {
      var paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color
        ..isAntiAlias = true;
      canvas.drawRect(
          Rect.fromLTWH(0, 0, dividerSize.width, dividerSize.height), paint);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DividerPainter &&
          runtimeType == other.runtimeType &&
          animationEnabled == other.animationEnabled &&
          backgroundColor == other.backgroundColor &&
          highlightedBackgroundColor == other.highlightedBackgroundColor &&
          animationDuration == other.animationDuration;

  @override
  int get hashCode =>
      animationEnabled.hashCode ^
      backgroundColor.hashCode ^
      highlightedBackgroundColor.hashCode ^
      animationDuration.hashCode;
}

/// Divider with dashes.
class _DashedDividerPainter extends DividerPainter {
  static const int colorKey = 1;
  static const int thicknessKey = 2;

  _DashedDividerPainter(
      {required this.size,
      required this.gap,
      super.backgroundColor,
      super.highlightedBackgroundColor,
      super.animationEnabled,
      super.animationDuration,
      required this.color,
      this.highlightedColor,
      required this.strokeCap,
      required this.thickness,
      this.highlightedThickness,
      this.highlightedGap}) {
    if (size <= 0) {
      throw Exception('The size parameter must be positive: $size');
    }
    if (gap <= 0) {
      throw Exception('The gap parameter must be positive: $gap');
    }
    if (thickness <= 0) {
      throw Exception('The thickness parameter must be positive: $thickness');
    }
    if (highlightedThickness != null && highlightedThickness! <= 0) {
      throw Exception(
          'The highlightedThickness parameter must be positive: $highlightedThickness');
    }
    if (highlightedGap != null && highlightedGap! <= 0) {
      throw Exception(
          'The highlightedGap parameter must be positive: $highlightedGap');
    }
  }

  final double size;
  final double gap;
  final double? highlightedGap;
  final Color color;
  final Color? highlightedColor;
  final StrokeCap strokeCap;
  final double thickness;
  final double? highlightedThickness;

  @override
  void paint(
      {required Axis dividerAxis,
      required bool resizable,
      required bool highlighted,
      required Canvas canvas,
      required Size dividerSize,
      required Map<int, dynamic> animatedValues}) {
    super.paint(
        dividerAxis: dividerAxis,
        resizable: resizable,
        highlighted: highlighted,
        canvas: canvas,
        dividerSize: dividerSize,
        animatedValues: animatedValues);
    Color? resolvedColor;
    if (animationEnabled && animatedValues.containsKey(colorKey)) {
      resolvedColor = animatedValues[colorKey];
    } else if (highlighted && highlightedColor != null) {
      resolvedColor = highlightedColor!;
    } else {
      resolvedColor = color;
    }

    if (resolvedColor != null) {
      var resolvedThickness = thickness;
      if (animationEnabled && animatedValues.containsKey(thicknessKey)) {
        resolvedThickness = animatedValues[thicknessKey];
      } else if (highlighted && highlightedThickness != null) {
        resolvedThickness = highlightedThickness!;
      }
      var paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = resolvedColor
        ..strokeWidth = resolvedThickness
        ..strokeCap = strokeCap
        ..isAntiAlias = true;
      if (dividerAxis == Axis.vertical) {
        double startY = 0;
        while (startY < dividerSize.height) {
          canvas.drawLine(Offset(dividerSize.width / 2, startY),
              Offset(dividerSize.width / 2, startY + size), paint);
          startY += size + gap;
        }
      } else {
        double startX = 0;
        while (startX < dividerSize.width) {
          canvas.drawLine(Offset(startX, dividerSize.height / 2),
              Offset(startX + size, dividerSize.height / 2), paint);
          startX += size + gap;
        }
      }
    }
  }

  @override
  Map<int, Tween> buildTween() {
    Map<int, Tween> map = super.buildTween();
    if (animationEnabled) {
      if (highlightedColor != null) {
        map[colorKey] = ColorTween(begin: color, end: highlightedColor);
      }
      if (highlightedThickness != null) {
        map[thicknessKey] =
            Tween<double>(begin: thickness, end: highlightedThickness);
      }
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is _DashedDividerPainter &&
          runtimeType == other.runtimeType &&
          size == other.size &&
          gap == other.gap &&
          highlightedGap == other.highlightedGap &&
          color == other.color &&
          highlightedColor == other.highlightedColor &&
          strokeCap == other.strokeCap &&
          thickness == other.thickness &&
          highlightedThickness == other.highlightedThickness;

  @override
  int get hashCode =>
      super.hashCode ^
      size.hashCode ^
      gap.hashCode ^
      highlightedGap.hashCode ^
      color.hashCode ^
      highlightedColor.hashCode ^
      strokeCap.hashCode ^
      thickness.hashCode ^
      highlightedThickness.hashCode;
}

/// Divider with grooves (style 1).
class _GroovedDividerPainter1 extends DividerPainter {
  static const int colorKey = 1;
  static const int thicknessKey = 2;
  static const int sizeKey = 3;

  _GroovedDividerPainter1(
      {required this.size,
      super.backgroundColor,
      super.highlightedBackgroundColor,
      super.animationEnabled,
      super.animationDuration,
      required this.color,
      this.highlightedColor,
      required this.strokeCap,
      required this.thickness,
      this.highlightedThickness,
      this.highlightedSize}) {
    if (size <= 0) {
      throw Exception('The size parameter must be positive: $size');
    }
    if (thickness <= 0) {
      throw Exception('The thickness parameter must be positive: $thickness');
    }
    if (highlightedThickness != null && highlightedThickness! <= 0) {
      throw Exception(
          'The highlightedThickness parameter must be positive: $highlightedThickness');
    }
    if (highlightedSize != null && highlightedSize! <= 0) {
      throw Exception(
          'The highlightedSize parameter must be positive: $highlightedSize');
    }
  }

  final double size;
  final double? highlightedSize;
  final Color color;
  final Color? highlightedColor;
  final StrokeCap strokeCap;
  final double thickness;
  final double? highlightedThickness;

  @override
  void paint(
      {required Axis dividerAxis,
      required bool resizable,
      required bool highlighted,
      required Canvas canvas,
      required Size dividerSize,
      required Map<int, dynamic> animatedValues}) {
    super.paint(
        dividerAxis: dividerAxis,
        resizable: resizable,
        highlighted: highlighted,
        canvas: canvas,
        dividerSize: dividerSize,
        animatedValues: animatedValues);
    Color? resolvedColor;
    if (animationEnabled && animatedValues.containsKey(colorKey)) {
      resolvedColor = animatedValues[colorKey];
    } else if (highlighted && highlightedColor != null) {
      resolvedColor = highlightedColor!;
    } else {
      resolvedColor = color;
    }

    if (resolvedColor != null) {
      var resolvedThickness = thickness;
      if (animationEnabled && animatedValues.containsKey(thicknessKey)) {
        resolvedThickness = animatedValues[thicknessKey];
      } else if (highlighted && highlightedThickness != null) {
        resolvedThickness = highlightedThickness!;
      }
      var resolvedSize = size;
      if (animationEnabled && animatedValues.containsKey(sizeKey)) {
        resolvedSize = animatedValues[sizeKey];
      } else if (highlighted && highlightedSize != null) {
        resolvedSize = highlightedSize!;
      }
      var paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = resolvedColor
        ..strokeWidth = resolvedThickness
        ..strokeCap = strokeCap
        ..isAntiAlias = true;
      if (dividerAxis == Axis.vertical) {
        double startY = (dividerSize.height - resolvedSize) / 2;
        canvas.drawLine(Offset(dividerSize.width / 2, startY),
            Offset(dividerSize.width / 2, startY + resolvedSize), paint);
      } else {
        double startX = (dividerSize.width - resolvedSize) / 2;
        canvas.drawLine(Offset(startX, dividerSize.height / 2),
            Offset(startX + resolvedSize, dividerSize.height / 2), paint);
      }
    }
  }

  @override
  Map<int, Tween> buildTween() {
    Map<int, Tween> map = super.buildTween();
    if (animationEnabled) {
      if (highlightedColor != null) {
        map[colorKey] = ColorTween(begin: color, end: highlightedColor);
      }
      if (highlightedThickness != null) {
        map[thicknessKey] =
            Tween<double>(begin: thickness, end: highlightedThickness);
      }
      if (highlightedSize != null) {
        map[sizeKey] = Tween<double>(begin: size, end: highlightedSize);
      }
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is _GroovedDividerPainter1 &&
          runtimeType == other.runtimeType &&
          size == other.size &&
          highlightedSize == other.highlightedSize &&
          color == other.color &&
          highlightedColor == other.highlightedColor &&
          strokeCap == other.strokeCap &&
          thickness == other.thickness &&
          highlightedThickness == other.highlightedThickness;

  @override
  int get hashCode =>
      super.hashCode ^
      size.hashCode ^
      highlightedSize.hashCode ^
      color.hashCode ^
      highlightedColor.hashCode ^
      strokeCap.hashCode ^
      thickness.hashCode ^
      highlightedThickness.hashCode;
}

/// Divider with grooves (style 2).
class _GroovedDividerPainter2 extends DividerPainter {
  static const int colorKey = 1;
  static const int countKey = 2;

  _GroovedDividerPainter2(
      {required this.size,
      super.backgroundColor,
      super.highlightedBackgroundColor,
      super.animationEnabled,
      super.animationDuration,
      required this.color,
      required this.gap,
      required this.count,
      this.highlightedColor,
      required this.strokeCap,
      required this.thickness,
      this.highlightedCount}) {
    if (size <= 0) {
      throw Exception('The size parameter must be positive: $size');
    }
    if (gap <= 0) {
      throw Exception('The gap parameter must be positive: $gap');
    }
    if (count.isEven) {
      throw Exception('The count parameter must be odd');
    }
    if (count < 1) {
      throw Exception('The count parameter must be bigger than 1: $count');
    }
    if (thickness <= 0) {
      throw Exception('The thickness parameter must be positive: $thickness');
    }
    if (highlightedCount != null) {
      if (highlightedCount!.isEven) {
        throw Exception('The highlightedCount parameter must be odd');
      }
      if (highlightedCount! < 1) {
        throw Exception(
            'The highlightedCount parameter must be bigger than 1: $highlightedCount');
      }
    }
  }

  final double size;
  final double gap;
  final int count;
  final int? highlightedCount;
  final Color color;
  final Color? highlightedColor;
  final StrokeCap strokeCap;
  final double thickness;

  @override
  void paint(
      {required Axis dividerAxis,
      required bool resizable,
      required bool highlighted,
      required Canvas canvas,
      required Size dividerSize,
      required Map<int, dynamic> animatedValues}) {
    super.paint(
        dividerAxis: dividerAxis,
        resizable: resizable,
        highlighted: highlighted,
        canvas: canvas,
        dividerSize: dividerSize,
        animatedValues: animatedValues);
    Color? resolvedColor;
    if (animationEnabled && animatedValues.containsKey(colorKey)) {
      resolvedColor = animatedValues[colorKey];
    } else if (highlighted && highlightedColor != null) {
      resolvedColor = highlightedColor!;
    } else {
      resolvedColor = color;
    }

    if (resolvedColor != null) {
      var resolvedCount = count;
      if (animationEnabled && animatedValues.containsKey(countKey)) {
        resolvedCount = animatedValues[countKey];
        if (resolvedCount.isEven) {
          resolvedCount--;
        }
      } else if (highlighted && highlightedCount != null) {
        resolvedCount = highlightedCount!;
      }

      var paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = resolvedColor
        ..strokeWidth = thickness
        ..strokeCap = strokeCap
        ..isAntiAlias = true;

      double groovesSize = (resolvedCount - 1) * gap;
      if (dividerAxis == Axis.vertical) {
        double startY = (dividerSize.height - groovesSize) / 2;
        double x = (dividerSize.width - size) / 2;
        for (int i = 0; i < resolvedCount; i++) {
          canvas.drawLine(Offset(x, startY + (gap * i)),
              Offset(x + size, startY + (gap * i)), paint);
        }
      } else {
        double startX = (dividerSize.width - groovesSize) / 2;
        double y = (dividerSize.height - size) / 2;
        for (int i = 0; i < resolvedCount; i++) {
          canvas.drawLine(Offset(startX + (gap * i), y),
              Offset(startX + (gap * i), y + size), paint);
        }
      }
    }
  }

  @override
  Map<int, Tween> buildTween() {
    Map<int, Tween> map = super.buildTween();
    if (animationEnabled) {
      if (highlightedColor != null) {
        map[colorKey] = ColorTween(begin: color, end: highlightedColor);
      }
      if (highlightedCount != null) {
        map[countKey] = IntTween(begin: count, end: highlightedCount);
      }
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is _GroovedDividerPainter2 &&
          runtimeType == other.runtimeType &&
          size == other.size &&
          gap == other.gap &&
          count == other.count &&
          highlightedCount == other.highlightedCount &&
          color == other.color &&
          highlightedColor == other.highlightedColor &&
          strokeCap == other.strokeCap &&
          thickness == other.thickness;

  @override
  int get hashCode =>
      super.hashCode ^
      size.hashCode ^
      gap.hashCode ^
      count.hashCode ^
      highlightedCount.hashCode ^
      color.hashCode ^
      highlightedColor.hashCode ^
      strokeCap.hashCode ^
      thickness.hashCode;
}
