import 'package:flutter/material.dart';

import 'inline_token_palette.dart';

/// Visual bleed on the left only; right edge stays at the layout token end.
const double inlineTokenPillLeftBleed = 4;

/// Inner text padding inside the pill background.
const double inlineTokenPillHorizontalPadding = 6;

List<InlineSpan> buildInlineTokenMirrorLayoutSpans({
  required String text,
  required TextStyle baseStyle,
  required RegExp tokenPattern,
}) {
  if (text.isEmpty) return [TextSpan(text: '', style: baseStyle)];

  final spans = <InlineSpan>[];
  var start = 0;
  for (final match in tokenPattern.allMatches(text)) {
    if (match.start > start) {
      spans.add(
        TextSpan(text: text.substring(start, match.start), style: baseStyle),
      );
    }
    final token = match.group(0)!;
    spans.add(
      TextSpan(
        text: token,
        style: baseStyle.copyWith(color: Colors.transparent),
      ),
    );
    start = match.end;
  }
  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: baseStyle));
  }
  return spans;
}

StrutStyle inlineTokenMirrorStrutStyle(TextStyle baseStyle) {
  return StrutStyle(
    fontSize: baseStyle.fontSize,
    height: baseStyle.height,
    fontFamily: baseStyle.fontFamily,
    fontFamilyFallback: baseStyle.fontFamilyFallback,
    forceStrutHeight: true,
  );
}

TextStyle inlineTokenPillLabelStyle(TextStyle baseStyle, Color foreground) {
  return baseStyle.copyWith(
    color: foreground,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );
}

double inlineTokenPillWidth(double layoutWidth) {
  return layoutWidth + inlineTokenPillLeftBleed;
}

List<Widget> buildInlineTokenPillOverlays({
  required String text,
  required TextStyle baseStyle,
  required ColorScheme colorScheme,
  required TextPainter painter,
  required RegExp tokenPattern,
  required InlineTokenPaletteResolver resolvePalette,
}) {
  final overlays = <Widget>[];
  for (final match in tokenPattern.allMatches(text)) {
    final token = match.group(0)!;
    final palette = resolvePalette(token, colorScheme);
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: match.start, extentOffset: match.end),
    );
    if (boxes.isEmpty) continue;

    final left = boxes.first.left;
    final top = boxes.map((box) => box.top).reduce((a, b) => a < b ? a : b);
    final bottom = boxes.map((box) => box.bottom).reduce((a, b) => a > b ? a : b);
    final layoutWidth = boxes.last.right - left;

    overlays.add(
      Positioned(
        left: left - inlineTokenPillLeftBleed,
        top: top + 1,
        width: inlineTokenPillWidth(layoutWidth),
        height: bottom - top - 2,
        child: _InlineTokenPill(
          token: token,
          baseStyle: baseStyle,
          palette: palette,
        ),
      ),
    );
  }
  return overlays;
}

class _InlineTokenPill extends StatelessWidget {
  const _InlineTokenPill({
    required this.token,
    required this.baseStyle,
    required this.palette,
  });

  final String token;
  final TextStyle baseStyle;
  final InlineTokenPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: inlineTokenPillHorizontalPadding,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              token,
              maxLines: 1,
              softWrap: false,
              style: inlineTokenPillLabelStyle(baseStyle, palette.foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decorative mirror of text with inline token chips (sits under the TextField).
class InlineTokenChipMirror extends StatelessWidget {
  const InlineTokenChipMirror({
    required this.text,
    required this.baseStyle,
    required this.minLines,
    required this.maxLines,
    required this.tokenPattern,
    required this.resolvePalette,
    this.scrollOffset = 0,
    super.key,
  });

  final String text;
  final TextStyle baseStyle;
  final int minLines;
  final int maxLines;
  final double scrollOffset;
  final RegExp tokenPattern;
  final InlineTokenPaletteResolver resolvePalette;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lineHeight = (baseStyle.fontSize ?? 14) * (baseStyle.height ?? 1.5);
    final minHeight = lineHeight * minLines;
    final maxHeight = lineHeight * maxLines;
    final strutStyle = inlineTokenMirrorStrutStyle(baseStyle);

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight, maxHeight: maxHeight),
      child: ClipRect(
        clipBehavior: Clip.none,
        child: Transform.translate(
          offset: Offset(0, -scrollOffset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layoutSpans = buildInlineTokenMirrorLayoutSpans(
                text: text,
                baseStyle: baseStyle,
                tokenPattern: tokenPattern,
              );
              final painter = TextPainter(
                text: TextSpan(children: layoutSpans),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                strutStyle: strutStyle,
                maxLines: maxLines,
              )..layout(maxWidth: constraints.maxWidth);

              return SizedBox(
                width: constraints.maxWidth,
                height: painter.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text.rich(
                      TextSpan(children: layoutSpans),
                      maxLines: maxLines,
                      strutStyle: strutStyle,
                    ),
                    ...buildInlineTokenPillOverlays(
                      text: text,
                      baseStyle: baseStyle,
                      colorScheme: cs,
                      painter: painter,
                      tokenPattern: tokenPattern,
                      resolvePalette: resolvePalette,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
