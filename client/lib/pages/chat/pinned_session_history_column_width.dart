import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:tp_markdown/tp_markdown.dart';

import '../../services/session/session_history_pagination.dart';
import '../../theme/app_markdown_style_sheet.dart';

/// Rebuilds history [Theme] / markdown tokens only when the stepped column
/// width or CoT expand prefs change. [child] always updates from the parent so
/// Bloc / InheritedWidget rebuilds are never frozen.
class PinnedSessionHistoryColumnWidth extends StatefulWidget {
  const PinnedSessionHistoryColumnWidth({
    required this.availableWidth,
    required this.expandReasoning,
    required this.expandTools,
    required this.child,
    super.key,
  });

  final double availableWidth;
  final bool expandReasoning;
  final bool expandTools;
  final Widget child;

  @override
  State<PinnedSessionHistoryColumnWidth> createState() =>
      _PinnedSessionHistoryColumnWidthState();
}

class _PinnedSessionHistoryColumnWidthState
    extends State<PinnedSessionHistoryColumnWidth> {
  double? _columnWidth;
  bool? _expandReasoning;
  bool? _expandTools;
  Brightness? _brightness;
  Color? _surfaceContainerHighest;
  Color? _onSurface;
  Color? _onSurfaceVariant;
  ThemeData? _themeData;

  @override
  Widget build(BuildContext context) {
    final next = resolveSessionHistoryColumnWidth(widget.availableWidth);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final spacing = context.tpSpacing;
    final needsTheme =
        _themeData == null ||
        _columnWidth != next ||
        _expandReasoning != widget.expandReasoning ||
        _expandTools != widget.expandTools ||
        _brightness != theme.brightness ||
        _surfaceContainerHighest != cs.surfaceContainerHighest ||
        _onSurface != cs.onSurface ||
        _onSurfaceVariant != cs.onSurfaceVariant;

    if (needsTheme) {
      _columnWidth = next;
      _expandReasoning = widget.expandReasoning;
      _expandTools = widget.expandTools;
      _brightness = theme.brightness;
      _surfaceContainerHighest = cs.surfaceContainerHighest;
      _onSurface = cs.onSurface;
      _onSurfaceVariant = cs.onSurfaceVariant;
      _themeData = theme.copyWith(
        extensions: [
          for (final ext in theme.extensions.values)
            if (ext is! AiMessageTheme) ext,
          AiMessageTheme.of(context).copyWith(
            markdown: buildAppMarkdownTokens(
              theme,
              MarkdownProfile.compact,
              width: next,
              mutedSurface: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            ),
            userBubbleColor: cs.surfaceContainerHighest,
            userBubbleForeground: cs.onSurface,
            mutedSurface: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            toolTriggerColor: cs.onSurfaceVariant,
            messageSpacing: 24,
            threadMaxWidth: next,
            threadHorizontalPadding: spacing.md,
            cotExpandReasoningOnOpen: widget.expandReasoning,
            cotExpandToolsOnOpen: widget.expandTools,
          ),
        ],
      );
    }

    return Theme(data: _themeData!, child: widget.child);
  }
}
