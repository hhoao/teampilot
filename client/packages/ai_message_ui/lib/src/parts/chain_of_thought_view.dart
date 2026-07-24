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
  const AiChainOfThoughtView({required this.parts, super.key});

  final List<AiMessagePart> parts;

  @override
  State<AiChainOfThoughtView> createState() => _AiChainOfThoughtViewState();
}

class _AiChainOfThoughtViewState extends State<AiChainOfThoughtView> {
  bool _open = false;

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
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing + 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(aiTheme.panelRadius + 2),
          border: Border.all(color: aiTheme.resolveReasoningBorder(scheme)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 16,
                            color: triggerColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
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
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final part in widget.parts) _buildInnerPart(part),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInnerPart(AiMessagePart part) {
    return switch (part) {
      AiReasoningPart() => AiReasoningPartView(
        part: part,
        initiallyExpanded: true,
      ),
      AiToolCallPart() => AiToolCallPartView(
        part: part,
        initiallyExpanded: true,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
