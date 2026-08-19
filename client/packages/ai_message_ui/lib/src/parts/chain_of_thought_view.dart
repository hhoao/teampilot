import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import 'reasoning_part_view.dart';
import 'tool_call_part_view.dart';

/// Default-collapsed chain-of-thought chrome for contiguous reasoning + tools.
class AiChainOfThoughtView extends StatefulWidget {
  const AiChainOfThoughtView({
    required this.parts,
    this.autoExpand = false,
    super.key,
  });

  final List<AiMessagePart> parts;

  /// While true, the chain stays expanded (including inner reasoning steps) so
  /// live "thinking" content remains visible. The host flips this off once a
  /// non-thinking part arrives or the message is no longer the tip, collapsing
  /// the reasoning back to its default collapsed chrome.
  final bool autoExpand;

  @override
  State<AiChainOfThoughtView> createState() => _AiChainOfThoughtViewState();
}

class _AiChainOfThoughtViewState extends State<AiChainOfThoughtView> {
  late bool _open = widget.autoExpand;

  @override
  void didUpdateWidget(covariant AiChainOfThoughtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Entering auto-expand opens the chain; leaving it collapses back to the
    // default chrome. While the mode is unchanged, respect manual toggles.
    if (widget.autoExpand != oldWidget.autoExpand) {
      _open = widget.autoExpand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final label = strings.formatThinkingProcessSteps(widget.parts.length);

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: Semantics(
              button: true,
              expanded: _open,
              label: label,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 16,
                          color: triggerColor,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: markdown.toolTrigger(triggerColor),
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
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in widget.parts) _buildInnerPart(part),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInnerPart(AiMessagePart part) {
    final aiTheme = AiMessageTheme.of(context);
    return switch (part) {
      AiReasoningPart() => AiReasoningPartView(
        part: part,
        initiallyExpanded:
            widget.autoExpand || aiTheme.cotExpandReasoningOnOpen,
      ),
      AiToolCallPart() => AiToolCallPartView(
        part: part,
        initiallyExpanded: aiTheme.cotExpandToolsOnOpen,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
