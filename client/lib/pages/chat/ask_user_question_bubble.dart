import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/agent_status/ask_user_question.dart';
import '../../utils/ui/app_keys.dart';

const _askUserToolNames = [
  'askuserquestion',
  'ask_user_question',
  'ask_user',
  'askquestion',
  'question',
];

/// History bubbles for ask-user tool calls, keyed by lowercase tool name.
Map<String, AiToolCallBubbleBuilder> cliAskUserBubbleBuilders() => {
  for (final name in _askUserToolNames)
    name: (context, part) {
      if (askUserQuestionsFromPart(part) == null) return null;
      return AskUserQuestionBubble(part: part);
    },
};

/// Questions encoded on a history tool-call part, or null when unparseable.
List<AgentAskUserQuestion>? askUserQuestionsFromPart(AiToolCallPart part) {
  final fromArgs = parseAskUserQuestions(part.args);
  if (fromArgs != null) return fromArgs;
  final text = part.argsText?.trim() ?? '';
  if (text.isEmpty) return null;
  try {
    return parseAskUserQuestions(jsonDecode(text));
  } on Object {
    return null;
  }
}

/// Read-only AskUserQuestion recap in session history.
class AskUserQuestionBubble extends StatefulWidget {
  const AskUserQuestionBubble({required this.part, super.key});

  final AiToolCallPart part;

  @override
  State<AskUserQuestionBubble> createState() => _AskUserQuestionBubbleState();
}

class _AskUserQuestionBubbleState extends State<AskUserQuestionBubble> {
  var _open = false;

  bool get _asking =>
      widget.part.status == AiToolCallStatus.running ||
      widget.part.status == AiToolCallStatus.incomplete;

  @override
  Widget build(BuildContext context) {
    final questions = askUserQuestionsFromPart(widget.part) ?? const [];
    final answers = parseAskUserAnswers(
      questions: questions,
      result: widget.part.result,
    );
    final scheme = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final aiTheme = AiMessageTheme.of(context);
    final l10n = context.l10n;
    final headerColor = scheme.onSurfaceVariant;
    final headerLabel = _asking
        ? l10n.askUserQuestionBubbleAsking
        : l10n.askUserQuestionBubbleAsked(questions.length);

    return Padding(
      key: AppKeys.askUserQuestionBubble,
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: AppKeys.askUserQuestionBubbleHeader,
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
                  for (var i = 0; i < questions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Text(
                      questions[i].question,
                      style: styles.smColored(scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (i < answers.length ? answers[i] : null) ??
                          l10n.askUserQuestionBubbleUnanswered,
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
