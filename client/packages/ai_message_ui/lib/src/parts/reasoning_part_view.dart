import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme.dart';
import 'text_part_view.dart';

/// Collapsible reasoning — assistant-ui ReasoningRoot (outline + markdown).
class AiReasoningPartView extends StatefulWidget {
  const AiReasoningPartView({required this.part, super.key});

  final AiReasoningPart part;

  @override
  State<AiReasoningPartView> createState() => _AiReasoningPartViewState();
}

class _AiReasoningPartViewState extends State<AiReasoningPartView> {
  bool _open = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final baseTrigger = aiTheme.resolveToolTrigger(scheme);
    final triggerColor = _hovered ? scheme.onSurface : baseTrigger;

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
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  borderRadius:
                      BorderRadius.circular(aiTheme.panelRadius + 2),
                  child: AnimatedScale(
                    scale: _hovered ? 0.99 : 1,
                    duration: const Duration(milliseconds: 100),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: triggerColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _open ? 0 : -0.25,
                            duration: const Duration(milliseconds: 200),
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
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 256),
                        child: SingleChildScrollView(
                          child: DefaultTextStyle.merge(
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                            child: AiTextPartView(text: widget.part.text),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
