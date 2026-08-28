import 'package:flutter/material.dart';

import 'fade_expand_body.dart';

const kAiToolCardPreviewLines = 5;
const kAiToolCardExpandedMaxHeight = kAiFadeExpandExpandedMaxHeight;

/// Whole-card tap target for edit/shell tool cards; exclusive child gestures win.
class AiExpandableToolCard extends StatelessWidget {
  const AiExpandableToolCard({
    required this.open,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: child,
        ),
      ),
    );
  }
}

/// First [lines] lines of [text] (split on `\n`).
String previewToolCardText(String text, {int lines = kAiToolCardPreviewLines}) {
  final split = text.split('\n');
  if (split.length <= lines) return text;
  return split.take(lines).join('\n');
}

/// Bounds panel text (shell command/output, tool args/results) so a
/// pathologically large string cannot freeze layout. Keeps the head + a
/// truncation marker; the tool row/card collapse stays the primary gate.
const int kAiToolPanelMaxChars = 50000;
const String kAiToolPanelTruncationMarker = '\n… [truncated]';

/// Collapsed shell cards switch to [previewToolCardText] above this size so
/// [AiFadeExpandBody] does not layout tens of thousands of characters.
const int kAiShellCollapsedPreviewMinChars = 2048;

String capToolPanelText(String text, {int maxChars = kAiToolPanelMaxChars}) {
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}${kAiToolPanelTruncationMarker}';
}
