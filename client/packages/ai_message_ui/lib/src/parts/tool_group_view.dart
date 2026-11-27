import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import '../markdown/compiled_markdown_chrome.dart';
import '../strings.dart';
import '../theme.dart';
import 'activity_outline.dart';
import 'tool_call_part_view.dart';

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
    final markdown = aiTheme.markdown;
    final triggerColor = aiTheme.resolveToolTrigger(scheme);
    final hasError = tools.any((t) => t.isError || t.isCancelled);
    final hasRunning = tools.any((t) => t.isRunning);
    final allComplete = tools.every(
      (t) => t.status == AiToolCallStatus.complete && !t.isError,
    );
    final statusColor = hasError
        ? scheme.error
        : hasRunning
        ? scheme.primary
        : allComplete
        ? aiTheme.resolveToolSuccess(scheme)
        : triggerColor;
    final header = SelectionContainer.disabled(
      child: Semantics(
        button: true,
        expanded: _open,
        label: strings.toolsUsedLabel(tools.length),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => setState(() => _open = !_open),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  AiActivityChevron(open: _open, color: statusColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      strings.toolsUsedLabel(tools.length),
                      style: markdown.toolTrigger(triggerColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: AiActivityOutline(
        header: header,
        children: [
          if (_open)
            for (final tool in tools)
              AiToolCallPartView(part: tool, dense: true),
        ],
      ),
    );
  }
}
