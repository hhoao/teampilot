import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/ask_user_question.dart';
import '../../services/terminal/ask_user_question_answer_service.dart';
import '../../utils/ui/app_keys.dart';

/// Interactive AskUserQuestion card shown in chat when the seat CLI capability
/// allows in-chat answering.
///
/// - Single single-select: option tap answers immediately (PTY digit or pending
///   labels).
/// - Multi-select / multi-question: radio or checkbox groups + one Submit.
class AskUserQuestionCard extends StatefulWidget {
  const AskUserQuestionCard({
    required this.session,
    required this.seatId,
    required this.questions,
    required this.onAnswerInTerminal,
    this.askRequestId,
    this.supportsMultiSelectInChat = false,
    super.key,
  });

  final AppSession session;

  /// Shell / seat key (`sessionId` for simple, member id for team).
  final String seatId;
  final List<AgentAskUserQuestion> questions;
  final String? askRequestId;

  /// When true, multi-select / multi-question UI is enabled (OpenCode).
  final bool supportsMultiSelectInChat;
  final VoidCallback onAnswerInTerminal;

  @override
  State<AskUserQuestionCard> createState() => _AskUserQuestionCardState();
}

class _AskUserQuestionCardState extends State<AskUserQuestionCard> {
  var _answering = false;
  String? _inlineError;

  /// Selected option indices per question (order matches [widget.questions]).
  late List<Set<int>> _selections;

  bool get _isQuickSingleSelect =>
      widget.questions.length == 1 && !widget.questions.single.multiSelect;

  @override
  void initState() {
    super.initState();
    _selections = List.generate(widget.questions.length, (_) => <int>{});
  }

  @override
  void didUpdateWidget(covariant AskUserQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameQuestions(oldWidget.questions, widget.questions)) {
      _selections = List.generate(widget.questions.length, (_) => <int>{});
      _inlineError = null;
      _answering = false;
    }
  }

  static bool _sameQuestions(
    List<AgentAskUserQuestion> a,
    List<AgentAskUserQuestion> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get _canSubmit {
    if (_answering) return false;
    if (widget.questions.isEmpty) return false;
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selections[i].isEmpty) return false;
    }
    return true;
  }

  List<List<String>> _labelsFromSelections() {
    return [
      for (var qi = 0; qi < widget.questions.length; qi++)
        [
          for (final oi in _selections[qi].toList()..sort())
            widget.questions[qi].options[oi].label,
        ],
    ];
  }

  String _mapFailureReason(String reason, AppLocalizations l10n) {
    switch (reason) {
      case 'terminal_disconnected':
        return l10n.agentAskTerminalDisconnected;
      default:
        return l10n.agentAskAnswerFailed;
    }
  }

  String _mapAskReplyError(String? askReplyError, AppLocalizations l10n) {
    final trimmed = askReplyError?.trim() ?? '';
    if (trimmed.isEmpty) return l10n.agentAskAnswerFailed;
    return trimmed;
  }

  Future<void> _answerQuick(int optionIndex) async {
    if (_answering) return;
    final question = widget.questions.single;
    if (optionIndex < 0 || optionIndex >= question.options.length) return;

    setState(() {
      _answering = true;
      _inlineError = null;
    });
    try {
      final label = question.options[optionIndex].label;
      final result = await context.read<ChatCubit>().answerAskUserQuestion(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
        optionIndex: optionIndex,
        askRequestId: widget.askRequestId,
        answers: [
          [label],
        ],
      );
      if (!mounted) return;
      if (result is AskUserAnswerFailed) {
        setState(() {
          _inlineError = _mapFailureReason(result.reason, context.l10n);
          _answering = false;
        });
      } else if (mounted) {
        setState(() => _answering = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineError = context.l10n.agentAskAnswerFailed;
          _answering = false;
        });
      }
    }
  }

  Future<void> _submitMulti() async {
    if (!_canSubmit) return;
    setState(() {
      _answering = true;
      _inlineError = null;
    });
    try {
      final answers = _labelsFromSelections();
      final firstIndex = _selections.first.isEmpty
          ? 0
          : (_selections.first.toList()..sort()).first;
      final result = await context.read<ChatCubit>().answerAskUserQuestion(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
        optionIndex: firstIndex,
        askRequestId: widget.askRequestId,
        answers: answers,
      );
      if (!mounted) return;
      if (result is AskUserAnswerFailed) {
        setState(() {
          _inlineError = _mapFailureReason(result.reason, context.l10n);
          _answering = false;
        });
      } else if (mounted) {
        setState(() => _answering = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineError = context.l10n.agentAskAnswerFailed;
          _answering = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    if (_answering) return;
    setState(() {
      _answering = true;
      _inlineError = null;
    });
    try {
      final result = await context.read<ChatCubit>().cancelAskUserQuestion(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
        askRequestId: widget.askRequestId,
      );
      if (!mounted) return;
      if (result is AskUserAnswerFailed) {
        setState(() {
          _inlineError = _mapFailureReason(result.reason, context.l10n);
          _answering = false;
        });
      } else if (mounted) {
        setState(() => _answering = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _inlineError = context.l10n.agentAskAnswerFailed;
          _answering = false;
        });
      }
    }
  }

  void _selectSingle(int questionIndex, int optionIndex) {
    if (_answering) return;
    setState(() {
      _selections[questionIndex] = {optionIndex};
      _inlineError = null;
    });
  }

  void _toggleMulti(int questionIndex, int optionIndex) {
    if (_answering) return;
    setState(() {
      final next = {..._selections[questionIndex]};
      if (next.contains(optionIndex)) {
        next.remove(optionIndex);
      } else {
        next.add(optionIndex);
      }
      _selections[questionIndex] = next;
      _inlineError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    final askReplyError =
        context.select<AgentAttentionCubit, String?>((c) {
          final entry = c.state.entryFor(
            sessionId: widget.session.sessionId,
            memberId: widget.seatId,
          );
          return entry?.askReplyError;
        });
    final displayError =
        _inlineError ??
        (askReplyError == null
            ? null
            : _mapAskReplyError(askReplyError, l10n));

    final useMultiUi =
        !_isQuickSingleSelect && widget.supportsMultiSelectInChat;

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
              if (_isQuickSingleSelect && !useMultiUi)
                ..._buildQuickSingleSelect(context)
              else
                ..._buildMultiUi(context),
              if (displayError != null) ...[
                SizedBox(height: spacing.sm),
                Text(
                  displayError,
                  key: AppKeys.askUserQuestionInlineError,
                  style: styles.xsColored(cs.error),
                ),
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
                  if (useMultiUi) ...[
                    SizedBox(width: spacing.xs),
                    TpButton(
                      key: AppKeys.askUserQuestionSubmitButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.small,
                      onPressed: _canSubmit ? _submitMulti : null,
                      child: Text(l10n.agentAskSubmitAnswers),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildQuickSingleSelect(BuildContext context) {
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final question = widget.questions.single;

    return [
      Text(question.question, style: styles.mdColored(cs.onSurface)),
      SizedBox(height: spacing.sm),
      for (var i = 0; i < question.options.length; i++) ...[
        _OptionButton(
          key: AppKeys.askUserQuestionOption(i),
          index: i,
          option: question.options[i],
          enabled: !_answering,
          selected: false,
          multiSelect: false,
          showChevron: true,
          onTap: () => _answerQuick(i),
        ),
        if (i != question.options.length - 1) SizedBox(height: spacing.xs),
      ],
    ];
  }

  List<Widget> _buildMultiUi(BuildContext context) {
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final out = <Widget>[];

    for (var qi = 0; qi < widget.questions.length; qi++) {
      final q = widget.questions[qi];
      if (qi > 0) out.add(SizedBox(height: spacing.md));
      out.add(Text(q.question, style: styles.mdColored(cs.onSurface)));
      out.add(SizedBox(height: spacing.sm));
      for (var oi = 0; oi < q.options.length; oi++) {
        final selected = _selections[qi].contains(oi);
        out.add(
          _OptionButton(
            key: AppKeys.askUserQuestionOptionAt(
              questionIndex: qi,
              optionIndex: oi,
            ),
            index: oi,
            option: q.options[oi],
            enabled: !_answering,
            selected: selected,
            multiSelect: q.multiSelect,
            showChevron: false,
            onTap: () {
              if (q.multiSelect) {
                _toggleMulti(qi, oi);
              } else {
                _selectSingle(qi, oi);
              }
            },
          ),
        );
        if (oi != q.options.length - 1) {
          out.add(SizedBox(height: spacing.xs));
        }
      }
    }
    return out;
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.index,
    required this.option,
    required this.enabled,
    required this.selected,
    required this.multiSelect,
    required this.showChevron,
    required this.onTap,
    super.key,
  });

  final int index;
  final AgentAskUserOption option;
  final bool enabled;
  final bool selected;
  final bool multiSelect;
  final bool showChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;

    final bg = selected
        ? cs.primaryContainer.withValues(alpha: 0.55)
        : (enabled ? cs.surfaceContainerLow : cs.surfaceContainerLowest);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              if (showChevron)
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
                )
              else
                Icon(
                  multiSelect
                      ? (selected
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded)
                      : (selected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded),
                  size: 18,
                  color: selected ? cs.primary : cs.outline,
                ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: styles.smColored(cs.onSurface)),
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
              if (showChevron && enabled)
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
