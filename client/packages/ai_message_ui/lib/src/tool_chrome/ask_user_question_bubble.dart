import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../strings.dart';
import '../theme.dart';

/// Read-only ask-user recap in session history.
class AiAskUserQuestionBubble extends StatefulWidget {
  const AiAskUserQuestionBubble({required this.target, super.key});

  static const bubbleKey = Key('ask-user-question-bubble');
  static const headerKey = Key('ask-user-question-bubble-header');

  final AiAskUserTarget target;

  @override
  State<AiAskUserQuestionBubble> createState() =>
      _AiAskUserQuestionBubbleState();
}

class _AiAskUserQuestionBubbleState extends State<AiAskUserQuestionBubble> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.target.items;
    final scheme = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final aiTheme = AiMessageTheme.of(context);
    final strings = AiMessageStrings.of(context);
    final headerColor = scheme.onSurfaceVariant;
    final headerLabel = widget.target.asking
        ? strings.askUserAsking
        : strings.askUserAskedLabel(items.length);

    return Padding(
      key: AiAskUserQuestionBubble.bubbleKey,
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: AiAskUserQuestionBubble.headerKey,
              onTap: () => setState(() => _open = !_open),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline_rounded,
                      size: 16,
                      color: headerColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        headerLabel,
                        style: styles.smColored(headerColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _open ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: headerColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Text(
                      items[i].question,
                      style: styles.smColored(scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].answer ?? strings.askUserUnanswered,
                      style: styles.smColored(headerColor),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
