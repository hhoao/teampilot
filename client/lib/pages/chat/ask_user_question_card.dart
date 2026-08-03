import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/ask_user_question.dart';
import '../../utils/ui/app_keys.dart';

/// Interactive AskUserQuestion card shown in chat when a single, single-select
/// question is waiting on the seat. Clicking an option injects the picker
/// selection keystrokes via [ChatCubit.answerAskUserQuestion] — no need to
/// switch to the Terminal.
class AskUserQuestionCard extends StatefulWidget {
  const AskUserQuestionCard({
    required this.session,
    required this.seatId,
    required this.question,
    required this.onAnswerInTerminal,
    super.key,
  });

  final AppSession session;

  /// Shell / seat key (`sessionId` for simple, member id for team).
  final String seatId;
  final AgentAskUserQuestion question;
  final VoidCallback onAnswerInTerminal;

  @override
  State<AskUserQuestionCard> createState() => _AskUserQuestionCardState();
}

class _AskUserQuestionCardState extends State<AskUserQuestionCard> {
  var _answering = false;

  Future<void> _answer(int optionIndex) async {
    if (_answering) return;
    setState(() => _answering = true);
    try {
      await context
          .read<ChatCubit>()
          .answerAskUserQuestion(
            sessionId: widget.session.sessionId,
            memberId: widget.seatId,
            optionIndex: optionIndex,
          );
    } finally {
      if (mounted) setState(() => _answering = false);
    }
  }

  Future<void> _cancel() async {
    if (_answering) return;
    await context
        .read<ChatCubit>()
        .cancelAskUserQuestion(
          sessionId: widget.session.sessionId,
          memberId: widget.seatId,
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Material(
        key: AppKeys.askUserQuestionCard,
        elevation: 2,
        shadowColor: cs.shadow.withValues(alpha: 0.28),
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.front_hand_rounded, size: 16, color: cs.tertiary),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.agentAskUserQuestionTitle,
                      style: styles.smColored(cs.onSurface),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.sm),
              Text(
                widget.question.question,
                style: styles.mdColored(cs.onSurface),
              ),
              SizedBox(height: spacing.sm),
              for (var i = 0; i < widget.question.options.length; i++) ...[
                _OptionButton(
                  index: i,
                  option: widget.question.options[i],
                  enabled: !_answering,
                  onTap: () => _answer(i),
                ),
                if (i != widget.question.options.length - 1)
                  SizedBox(height: spacing.xs),
              ],
              SizedBox(height: spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TpButton(
                    variant: TpButtonVariant.ghost,
                    size: TpControlSize.small,
                    onPressed: _answering ? null : widget.onAnswerInTerminal,
                    child: Text(l10n.agentAskAnswerInTerminal),
                  ),
                  SizedBox(width: spacing.xs),
                  TpButton(
                    variant: TpButtonVariant.ghost,
                    size: TpControlSize.small,
                    onPressed: _answering ? null : _cancel,
                    child: Text(l10n.agentAskCancelQuestion),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.index,
    required this.option,
    required this.enabled,
    required this.onTap,
  });

  final int index;
  final AgentAskUserOption option;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    return Material(
      color: enabled ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        key: AppKeys.askUserQuestionOption(index),
        borderRadius: BorderRadius.circular(radius),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: styles.xsColored(cs.onPrimaryContainer),
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: styles.smColored(cs.onSurface),
                    ),
                    if (option.description != null) ...[
                      SizedBox(height: 2),
                      Text(
                        option.description!,
                        style: styles.xsColored(cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.keyboard_arrow_right_rounded,
                  size: 16,
                  color: cs.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
