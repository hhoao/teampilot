import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import 'package:tp_markdown/tp_markdown.dart';
import '../parts/expandable_tool_card.dart';
import '../parts/fade_expand_body.dart';
import '../selection_dead_zone.dart';
import '../theme.dart';
import '../tool_file_actions.dart';
import 'edit_line_highlighter.dart';

/// Picks up to [cap] lines for collapsed preview, preferring add/remove rows.
///
/// Collapsed edit cards mount **only** this preview (on-demand); full hunk
/// lines mount after expand — unlike user bubbles which always clip full text.
List<AiEditLine> previewEditHunkLines(
  List<AiEditLine> lines, {
  int cap = kAiToolCardPreviewLines,
}) {
  if (lines.length <= cap) return lines;

  bool isChange(AiEditLine line) =>
      line.kind == AiEditLineKind.add || line.kind == AiEditLineKind.remove;

  final head = lines.take(cap);
  if (head.any(isChange)) {
    return head.toList(growable: false);
  }

  final changeIndex = lines.indexWhere(isChange);
  if (changeIndex < 0) {
    return head.toList(growable: false);
  }

  var start = math.max(0, changeIndex - 1);
  if (start + cap > lines.length) {
    start = math.max(0, lines.length - cap);
  }
  return lines.sublist(start, start + cap);
}

/// Cursor-style edit tool card: header + inline mini/full diff.
class EditToolCard extends StatelessWidget {
  const EditToolCard({
    required this.part,
    required this.hunk,
    required this.actions,
    required this.triggerColor,
    required this.markdown,
    required this.dense,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final AiToolCallPart part;
  final AiEditHunk hunk;
  final AiToolFileActions actions;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final panelColor = aiTheme.resolveToolPanel(scheme);
    final basename = _pathBasename(hunk.path);
    final openTarget = _openFileTarget(hunk);
    final onOpenFile = actions.onOpenFile;
    final triggerStyle = markdown.toolTrigger(triggerColor);
    final openTargetStyle = markdown.toolFileLink(triggerStyle, triggerColor);
    // On-demand: collapsed mounts preview only; expand mounts full hunk.
    final visibleLines =
        open ? hunk.lines : previewEditHunkLines(hunk.lines);
    final hasMore = hunk.lines.length > visibleLines.length;

    final titleWidget = Text(
      basename,
      style: onOpenFile != null ? openTargetStyle : triggerStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    Widget title = titleWidget;
    if (onOpenFile != null && openTarget != null) {
      title = Semantics(
        link: true,
        label: basename,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onOpenFile(openTarget),
            behavior: HitTestBehavior.opaque,
            child: titleWidget,
          ),
        ),
      );
    }

    final badges = <Widget>[
      if (hunk.addedCount > 0)
        _EditBadge(
          label: '+${hunk.addedCount}',
          color: scheme.primary,
          style: markdown.toolTrigger(scheme.primary),
        ),
      if (hunk.removedCount > 0)
        _EditBadge(
          label: '-${hunk.removedCount}',
          color: scheme.error,
          style: markdown.toolTrigger(scheme.error),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _EditStatusIcon(part: part, color: triggerColor),
                const SizedBox(width: 6),
                Icon(
                  _fileTypeIcon(hunk.path),
                  size: 15,
                  color: triggerColor,
                ),
                const SizedBox(width: 6),
                Expanded(child: title),
                ...badges,
                const SizedBox(width: 4),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggle,
                    child: _EditExpandChevron(
                      open: open,
                      color: triggerColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Body stays selectable (user-bubble parity); only fade/chevron toggles.
        _EditDiffPanel(
          hunk: hunk,
          lines: visibleLines,
          panelColor: panelColor,
          radius: aiTheme.panelRadius,
          markdown: markdown,
          highlighter: actions.lineHighlighter,
          open: open,
          onToggle: onToggle,
          forceChrome: !open && hasMore,
        ),
      ],
    );
  }
}

class _EditDiffPanel extends StatelessWidget {
  const _EditDiffPanel({
    required this.hunk,
    required this.lines,
    required this.panelColor,
    required this.radius,
    required this.markdown,
    required this.highlighter,
    required this.open,
    required this.onToggle,
    required this.forceChrome,
  });

  final AiEditHunk hunk;
  final List<AiEditLine> lines;
  final Color panelColor;
  final double radius;
  final MarkdownTokens markdown;
  final AiEditLineHighlighter highlighter;
  final bool open;
  final VoidCallback onToggle;
  final bool forceChrome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mono = markdown.codeBlock;

    Widget lineList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          _EditDiffLine(
            path: hunk.path,
            line: line,
            mono: mono,
            scheme: scheme,
            highlighter: highlighter,
            allowWrap: open,
          ),
      ],
    );

    lineList = AiFadeExpandBody(
      open: open,
      onToggle: onToggle,
      fadeColor: panelColor,
      forceChrome: forceChrome,
      child: lineList,
    );

    // Single clipped surface: line tint fills to the rounded edge (no inset
    // frame from outer padding).
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: panelColor,
        child: lineList,
      ),
    );
  }
}

class _EditDiffLine extends StatelessWidget {
  const _EditDiffLine({
    required this.path,
    required this.line,
    required this.mono,
    required this.scheme,
    required this.highlighter,
    required this.allowWrap,
  });

  final String path;
  final AiEditLine line;
  final TextStyle mono;
  final ColorScheme scheme;
  final AiEditLineHighlighter highlighter;
  final bool allowWrap;

  @override
  Widget build(BuildContext context) {
    final bg = switch (line.kind) {
      AiEditLineKind.add => scheme.primary.withValues(alpha: 0.12),
      AiEditLineKind.remove => scheme.error.withValues(alpha: 0.12),
      AiEditLineKind.context => Colors.transparent,
    };
    final fg = switch (line.kind) {
      AiEditLineKind.context => scheme.onSurface.withValues(alpha: 0.55),
      _ => scheme.onSurface.withValues(alpha: 0.9),
    };
    final prefix = switch (line.kind) {
      AiEditLineKind.add => '+',
      AiEditLineKind.remove => '-',
      AiEditLineKind.context => ' ',
    };
    final baseStyle = mono.copyWith(color: fg);
    InlineSpan content;
    try {
      content = highlighter.highlight(
        path: path,
        text: line.text,
        kind: line.kind,
        baseStyle: baseStyle,
      );
    } on Object {
      content = TextSpan(text: line.text, style: baseStyle);
    }

    final gutter = line.lineNumber == null
        ? const SizedBox(width: 36)
        : SizedBox(
            width: 36,
            child: Text(
              '${line.lineNumber}',
              style: mono.copyWith(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.right,
            ),
          );

    final row = DecoratedBox(
      decoration: BoxDecoration(color: bg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionDeadZone(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  gutter,
                  Text(
                    prefix,
                    style: mono.copyWith(
                      color: switch (line.kind) {
                        AiEditLineKind.add => scheme.primary,
                        AiEditLineKind.remove => scheme.error,
                        AiEditLineKind.context => scheme.onSurfaceVariant,
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: Text.rich(
                content,
                maxLines: allowWrap ? null : 1,
                overflow: allowWrap ? null : TextOverflow.ellipsis,
                softWrap: allowWrap,
                style: baseStyle,
              ),
            ),
          ],
        ),
      ),
    );

    return row;
  }
}

class _EditBadge extends StatelessWidget {
  const _EditBadge({
    required this.label,
    required this.color,
    required this.style,
  });

  final String label;
  final Color color;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

class _EditExpandChevron extends StatelessWidget {
  const _EditExpandChevron({
    required this.open,
    required this.color,
  });

  final bool open;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Transform.rotate(
        angle: open ? 0 : -math.pi / 2,
        child: Icon(Icons.expand_more, size: 16, color: color),
      ),
    );
  }
}

class _EditStatusIcon extends StatelessWidget {
  const _EditStatusIcon({required this.part, required this.color});

  final AiToolCallPart part;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (part.isError) {
      return Icon(Icons.error_outline, size: 16, color: scheme.error);
    }
    return switch (part.status) {
      AiToolCallStatus.running => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      AiToolCallStatus.complete => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      AiToolCallStatus.incomplete => Icon(
        Icons.highlight_off,
        size: 16,
        color: color,
      ),
      AiToolCallStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: color,
      ),
    };
  }
}

IconData _fileTypeIcon(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return Icons.insert_drive_file_outlined;
  return switch (path.substring(dot + 1).toLowerCase()) {
    'dart' || 'js' || 'ts' || 'tsx' || 'jsx' || 'py' || 'rs' || 'go' =>
      Icons.code_outlined,
    'md' || 'txt' => Icons.description_outlined,
    'json' || 'yaml' || 'yml' => Icons.data_object_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

String _pathBasename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final last = slash > backslash ? slash : backslash;
  if (last >= 0) return path.substring(last + 1);
  return path;
}

AiToolFileTarget? _openFileTarget(AiEditHunk hunk) {
  int? firstNumbered;
  int? lastNumbered;
  for (final line in hunk.lines) {
    final n = line.lineNumber;
    if (n == null) continue;
    firstNumbered ??= n;
    lastNumbered = n;
  }
  return AiToolFileTarget(
    path: hunk.path,
    startLine: hunk.startLine ?? firstNumbered,
    endLine: lastNumbered,
  );
}
