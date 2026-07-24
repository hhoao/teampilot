import 'dart:math' as math;

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import 'text_part_view.dart';

/// Collapsible reasoning — assistant-ui ReasoningRoot (outline + markdown).
class AiReasoningPartView extends StatefulWidget {
  const AiReasoningPartView({
    required this.part,
    this.initiallyExpanded = false,
    super.key,
  });

  final AiReasoningPart part;
  final bool initiallyExpanded;

  @override
  State<AiReasoningPartView> createState() => _AiReasoningPartViewState();
}

class _AiReasoningPartViewState extends State<AiReasoningPartView> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);

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
                label: strings.reasoning,
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
                              strings.reasoning,
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 256),
                    child: SingleChildScrollView(
                      child: DefaultTextStyle.merge(
                        style: markdown.reasoningBody(scheme.onSurfaceVariant),
                        child: AiTextPartView(text: widget.part.text),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
