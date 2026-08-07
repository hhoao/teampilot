import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../edit/edit_tool_card.dart';
import '../shell/shell_tool_card.dart';
import '../markdown/compiled_markdown_chrome.dart';
import 'package:tp_markdown/tp_markdown.dart';
import 'expandable_tool_card.dart';
import '../strings.dart';
import '../theme.dart';
import '../tool_file_actions.dart';
import '../tool_subagent_actions.dart';

/// Collapsible tool row aligned with assistant-ui ToolFallback.
class AiToolCallPartView extends StatefulWidget {
  const AiToolCallPartView({
    required this.part,
    this.dense = false,
    this.initiallyExpanded = false,
    super.key,
  });

  final AiToolCallPart part;
  final bool dense;
  final bool initiallyExpanded;

  @override
  State<AiToolCallPartView> createState() => _AiToolCallPartViewState();
}

class _AiToolCallPartViewState extends State<AiToolCallPartView> {
  late bool _open = widget.initiallyExpanded;

  void _toggleExpanded() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final part = widget.part;
    final cancelled = part.isCancelled;
    final bottom = widget.dense ? 2.0 : aiTheme.partSpacing;
    final fileActions = AiToolFileActions.of(context);
    final subagentActions = AiToolSubagentActions.of(context);
    final onOpenSubagent = subagentActions.onOpenSubagent;
    final isSub =
        (subagentActions.isSubagentTool?.call(part.toolName) ??
            isAiSubagentToolName(part.toolName)) &&
        onOpenSubagent != null;
    final useSubagentChrome = isSub;
    const shellResolver = DefaultAiShellToolTargetResolver();
    final shellTarget =
        useSubagentChrome ? null : shellResolver.resolve(part);
    const editResolver = DefaultAiEditToolTargetResolver();
    final editTarget = useSubagentChrome || shellTarget != null
        ? null
        : editResolver.resolve(part);
    final target = useSubagentChrome || shellTarget != null || editTarget != null
        ? null
        : fileActions.resolver.resolve(part);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (useSubagentChrome)
            SelectionContainer.disabled(
              child: _SubagentToolTrigger(
                part: part,
                cancelled: cancelled,
                triggerColor: triggerColor,
                markdown: markdown,
                onOpenSubagent: onOpenSubagent,
                dense: widget.dense,
                open: _open,
                onToggle: _toggleExpanded,
              ),
            )
          else if (shellTarget != null)
            ShellToolCardHost(
              part: part,
              shell: shellTarget,
              triggerColor: triggerColor,
              markdown: markdown,
              dense: widget.dense,
              open: _open,
              onToggle: _toggleExpanded,
            )
          else if (editTarget != null)
            EditToolCard(
              part: part,
              hunk: editTarget.hunk,
              actions: fileActions,
              triggerColor: triggerColor,
              markdown: markdown,
              dense: widget.dense,
              open: _open,
              onToggle: _toggleExpanded,
            )
          else
            SelectionContainer.disabled(
              child: target == null
                  ? _LegacyToolTrigger(
                      part: part,
                      cancelled: cancelled,
                      triggerColor: triggerColor,
                      markdown: markdown,
                      strings: strings,
                      dense: widget.dense,
                      open: _open,
                      onToggle: _toggleExpanded,
                    )
                  : _SummaryToolTrigger(
                      part: part,
                      target: target,
                      cancelled: cancelled,
                      triggerColor: triggerColor,
                      markdown: markdown,
                      actions: fileActions,
                      dense: widget.dense,
                      open: _open,
                      onToggle: _toggleExpanded,
                    ),
            ),
          if (_open && shellTarget == null && editTarget == null)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_hasArgs(part))
                      _MutedPre(
                        text: capToolPanelText(_argsText(part)),
                        color: aiTheme.resolveToolPanel(scheme),
                        radius: aiTheme.panelRadius,
                        foreground: scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    if (part.result != null) ...[
                      if (_hasArgs(part)) const SizedBox(height: 8),
                      Text(
                        '${strings.result}:',
                        style: markdown.toolTrigger(triggerColor),
                      ),
                      const SizedBox(height: 4),
                      _MutedPre(
                        text: capToolPanelText(_stringify(part.result)),
                        color: aiTheme.resolveToolPanel(scheme),
                        radius: aiTheme.panelRadius,
                        foreground: part.isError
                            ? scheme.error
                            : scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegacyToolTrigger extends StatelessWidget {
  const _LegacyToolTrigger({
    required this.part,
    required this.cancelled,
    required this.triggerColor,
    required this.markdown,
    required this.strings,
    required this.dense,
    required this.open,
    required this.onToggle,
  });

  final AiToolCallPart part;
  final bool cancelled;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final AiMessageStrings strings;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      label: cancelled ? strings.cancelledTool : strings.usedTool,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _StatusIcon(part: part, color: triggerColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: markdown.toolTrigger(
                        triggerColor,
                        cancelled: cancelled,
                      ),
                      children: [
                        TextSpan(
                          text:
                              '${cancelled ? strings.cancelledTool : strings.usedTool}: ',
                        ),
                        TextSpan(
                          text: part.toolName,
                          style: markdown.toolNameEmphasis(
                            markdown.toolTrigger(
                              triggerColor,
                              cancelled: cancelled,
                            ),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                _ExpandChevron(open: open, color: triggerColor, onTap: onToggle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SubagentToolTrigger extends StatelessWidget {
  const _SubagentToolTrigger({
    required this.part,
    required this.cancelled,
    required this.triggerColor,
    required this.markdown,
    required this.onOpenSubagent,
    required this.dense,
    required this.open,
    required this.onToggle,
  });

  final AiToolCallPart part;
  final bool cancelled;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final Future<void> Function(String toolCallId) onOpenSubagent;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final triggerStyle = markdown.toolTrigger(
      triggerColor,
      cancelled: cancelled,
    );
    final title = subagentTitleFromPart(part);
    final strut = StrutStyle(
      fontSize: triggerStyle.fontSize,
      height: triggerStyle.height,
      fontWeight: triggerStyle.fontWeight,
      forceStrutHeight: true,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final label = title == null || title.isEmpty
        ? part.toolName
        : '${part.toolName} $title';
    final labelSpan = title == null || title.isEmpty
        ? TextSpan(text: part.toolName, style: triggerStyle)
        : TextSpan(
            style: triggerStyle,
            children: [
              TextSpan(
                text: part.toolName,
                style: markdown.toolNameEmphasis(triggerStyle),
              ),
              TextSpan(text: ' $title'),
            ],
          );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: _StatusIcon(part: part, color: triggerColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Blank trailing space expands; label itself opens the preview.
            child: GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Semantics(
                      button: true,
                      label: label,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => onOpenSubagent(part.toolCallId),
                          behavior: HitTestBehavior.opaque,
                          child: Text.rich(
                            labelSpan,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            strutStyle: strut,
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            expanded: open,
            child: _ExpandChevron(
              open: open,
              color: triggerColor,
              onTap: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryToolTrigger extends StatelessWidget {
  const _SummaryToolTrigger({
    required this.part,
    required this.target,
    required this.cancelled,
    required this.triggerColor,
    required this.markdown,
    required this.actions,
    required this.dense,
    required this.open,
    required this.onToggle,
  });

  final AiToolCallPart part;
  final AiToolFileTarget target;
  final bool cancelled;
  final Color triggerColor;
  final MarkdownTokens markdown;
  final AiToolFileActions actions;
  final bool dense;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final triggerStyle = markdown.toolTrigger(
      triggerColor,
      cancelled: cancelled,
    );
    final mutedStyle = markdown.toolTrigger(
      scheme.onSurfaceVariant,
      cancelled: cancelled,
    );
    // Same muted chrome as Agent titles — not primary/blue link color.
    final openTargetStyle = markdown.toolFileLink(triggerStyle, triggerColor);
    final strut = StrutStyle(
      fontSize: triggerStyle.fontSize,
      height: triggerStyle.height,
      fontWeight: triggerStyle.fontWeight,
      forceStrutHeight: true,
      leadingDistribution: TextLeadingDistribution.even,
    );
    final basename = _pathBasename(target.path);
    final lineLabel = _lineLabel(target);
    final onOpenFile = actions.onOpenFile;
    final fileSemanticsLabel = lineLabel == null
        ? basename
        : '$basename $lineLabel';

    final fileLabelSpans = <InlineSpan>[
      TextSpan(
        text: basename,
        style: onOpenFile != null ? openTargetStyle : triggerStyle,
      ),
      if (lineLabel != null)
        TextSpan(text: ' $lineLabel', style: mutedStyle),
    ];

    Widget fileLabelWidget = Text.rich(
      TextSpan(style: triggerStyle, children: fileLabelSpans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      strutStyle: strut,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );

    if (onOpenFile != null) {
      fileLabelWidget = Semantics(
        link: true,
        label: fileSemanticsLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onOpenFile(target),
            behavior: HitTestBehavior.opaque,
            child: fileLabelWidget,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: _StatusIcon(part: part, color: triggerColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Trailing blank expands; basename opens the file when wired.
            child: GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${part.toolName} ',
                    style: triggerStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: strut,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                  ),
                  Flexible(child: fileLabelWidget),
                ],
              ),
            ),
          ),
          Semantics(
            button: true,
            expanded: open,
            child: _ExpandChevron(
              open: open,
              color: triggerColor,
              onTap: onToggle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({
    required this.open,
    required this.color,
    required this.onTap,
  });

  final bool open;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Transform.rotate(
          angle: open ? 0 : -math.pi / 2,
          child: Icon(
            Icons.expand_more,
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.part, required this.color});

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
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
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

String _pathBasename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final last = slash > backslash ? slash : backslash;
  if (last >= 0) return path.substring(last + 1);
  return path;
}

String? _lineLabel(AiToolFileTarget target) {
  final start = target.startLine;
  if (start == null) return null;
  final end = target.endLine;
  if (end == null || end == start) return 'L$start';
  return 'L$start-$end';
}

bool _hasArgs(AiToolCallPart part) {
  final argsText = part.argsText?.trim();
  if (argsText != null && argsText.isNotEmpty) return true;
  return part.args != null && part.args!.isNotEmpty;
}

String _argsText(AiToolCallPart part) {
  final argsText = part.argsText?.trim();
  if (argsText != null && argsText.isNotEmpty) return argsText;
  return const JsonEncoder.withIndent('  ').convert(part.args);
}

String _stringify(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on Object {
    return value.toString();
  }
}

class _MutedPre extends StatelessWidget {
  const _MutedPre({
    required this.text,
    required this.color,
    required this.radius,
    required this.foreground,
  });

  final String text;
  final Color color;
  final double radius;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          text,
          softWrap: true,
          style: AiMessageTheme.of(context).markdown.codeBlock.copyWith(
            color: foreground,
          ),
        ),
      ),
    );
  }
}
