import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';

/// Collapsible tool row aligned with assistant-ui ToolFallback.
class AiToolCallPartView extends StatefulWidget {
  const AiToolCallPartView({
    required this.part,
    this.dense = false,
    super.key,
  });

  final AiToolCallPart part;
  final bool dense;

  @override
  State<AiToolCallPartView> createState() => _AiToolCallPartViewState();
}

class _AiToolCallPartViewState extends State<AiToolCallPartView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final part = widget.part;
    final cancelled = part.isCancelled;
    final bottom = widget.dense ? 2.0 : aiTheme.partSpacing;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Semantics(
              button: true,
              expanded: _open,
              label: cancelled ? strings.cancelledTool : strings.usedTool,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(vertical: widget.dense ? 4 : 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatusIcon(part: part, color: triggerColor),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Text.rich(
                            TextSpan(
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: triggerColor,
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                height: 1.2,
                              ),
                              children: [
                                TextSpan(
                                  text:
                                      '${cancelled ? strings.cancelledTool : strings.usedTool}: ',
                                ),
                                TextSpan(
                                  text: part.toolName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.rotate(
                          angle: _open ? 0 : -math.pi / 2,
                          child: Icon(
                            Icons.expand_more,
                            size: 16,
                            color: triggerColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_open)
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
                        text: _argsText(part),
                        color: aiTheme.resolveToolPanel(scheme),
                        radius: aiTheme.panelRadius,
                        foreground: scheme.onSurface.withValues(alpha: 0.9),
                      ),
                    if (part.result != null) ...[
                      if (_hasArgs(part)) const SizedBox(height: 8),
                      Text(
                        '${strings.result}:',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: triggerColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _MutedPre(
                        text: _stringify(part.result),
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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: foreground,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
