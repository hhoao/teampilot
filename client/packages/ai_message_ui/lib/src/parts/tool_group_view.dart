import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'tool_call_part_view.dart';
import '../strings.dart';
import '../theme.dart';

/// Collapsible consecutive tool burst — assistant-ui ToolGroup.
class AiToolGroupView extends StatefulWidget {
  const AiToolGroupView({required this.tools, super.key});

  final List<AiToolCallPart> tools;

  @override
  State<AiToolGroupView> createState() => _AiToolGroupViewState();
}

class _AiToolGroupViewState extends State<AiToolGroupView> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tools = widget.tools;
    if (tools.length == 1) {
      return AiToolCallPartView(part: tools.single);
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final hasError = tools.any((t) => t.isError);

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionContainer.disabled(
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasError
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline,
                      size: 16,
                      color: hasError ? scheme.error : triggerColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.toolsUsedLabel(tools.length),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: triggerColor,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 4),
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
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final tool in tools)
                    AiToolCallPartView(part: tool, dense: true),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
