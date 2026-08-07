import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../services/agent_status/ask_user_question.dart';
import '../../services/terminal/ask_user_question_answer_service.dart';
import '../../utils/ui/app_keys.dart';

/// Interactive AskUserQuestion card — light card with numbered options,
/// header pill + pagination, and Ignore / Submit footer.
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
  var _activeQuestionIndex = 0;

  /// Keyboard focus highlight within the active question's options
  /// (authored options + trailing custom row).
  var _focusedOptionIndex = 0;
  final _focusNode = FocusNode();

  /// Selected option indices per question (order matches [widget.questions]).
  /// Index `options.length` is the freeform "Other" row.
  late List<Set<int>> _selections;
  late List<TextEditingController> _customControllers;
  late List<FocusNode> _customFocusNodes;

  @override
  void initState() {
    super.initState();
    _selections = List.generate(widget.questions.length, (_) => <int>{});
    _initCustomFields(widget.questions.length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _disposeCustomFields();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AskUserQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameQuestions(oldWidget.questions, widget.questions)) {
      _disposeCustomFields();
      _selections = List.generate(widget.questions.length, (_) => <int>{});
      _initCustomFields(widget.questions.length);
      _inlineError = null;
      _answering = false;
      _activeQuestionIndex = 0;
      _focusedOptionIndex = 0;
    }
  }

  void _initCustomFields(int count) {
    _customControllers = List.generate(count, (_) => TextEditingController());
    _customFocusNodes = List.generate(count, (i) {
      final node = FocusNode();
      // Selecting inside the TextField does not hit the outer InkWell — mark
      // freeform selected when the field actually gains focus.
      node.addListener(() {
        if (!mounted || !node.hasFocus || _answering) return;
        _selectCustom(i);
      });
      return node;
    });
  }

  void _disposeCustomFields() {
    for (final c in _customControllers) {
      c.dispose();
    }
    for (final n in _customFocusNodes) {
      n.dispose();
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

  int _customIndexFor(int questionIndex) =>
      widget.questions[questionIndex].options.length;

  int _rowCountFor(int questionIndex) =>
      widget.questions[questionIndex].options.length + 1;

  bool _isCustomSelected(int questionIndex) =>
      _selections[questionIndex].contains(_customIndexFor(questionIndex));

  bool _isQuestionAnswered(int questionIndex) {
    if (questionIndex < 0 || questionIndex >= widget.questions.length) {
      return false;
    }
    if (_selections[questionIndex].isEmpty) return false;
    if (_isCustomSelected(questionIndex) &&
        _customControllers[questionIndex].text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  bool get _canSubmit {
    if (_answering) return false;
    if (widget.questions.isEmpty) return false;
    for (var i = 0; i < widget.questions.length; i++) {
      if (!_isQuestionAnswered(i)) return false;
    }
    return true;
  }

  /// Multi-question: always allow Continue while answers remain incomplete
  /// (pager already lets users skip; the footer should match).
  bool get _canContinue {
    if (_answering || _canSubmit) return false;
    return widget.questions.length > 1;
  }

  /// First unanswered question after [from], wrapping from the start.
  int? _nextIncompleteQuestionIndex({int? from}) {
    final start = from ?? _activeQuestionIndex;
    for (var offset = 1; offset <= widget.questions.length; offset++) {
      final i = (start + offset) % widget.questions.length;
      if (!_isQuestionAnswered(i)) return i;
    }
    return null;
  }

  void _continueToNext() {
    if (!_canContinue) return;
    final incomplete = _nextIncompleteQuestionIndex();
    if (incomplete != null && incomplete != _activeQuestionIndex) {
      _goToQuestion(incomplete);
      return;
    }
    final next = (_activeQuestionIndex + 1) % widget.questions.length;
    if (next != _activeQuestionIndex) {
      _goToQuestion(next);
    }
  }

  void _primaryAction() {
    if (_canSubmit) {
      unawaited(_submit());
    } else if (_canContinue) {
      _continueToNext();
    }
  }

  List<List<String>> _labelsFromSelections() {
    return [
      for (var qi = 0; qi < widget.questions.length; qi++)
        [
          for (final oi in _selections[qi].toList()..sort())
            if (oi == _customIndexFor(qi))
              _customControllers[qi].text.trim()
            else
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

  String _headerLabel(int index, AppLocalizations l10n) {
    final header = widget.questions[index].header?.trim();
    if (header != null && header.isNotEmpty) return header;
    return l10n.agentAskQuestionTabFallback(index + 1);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _answering = true;
      _inlineError = null;
    });
    try {
      final answers = _labelsFromSelections();
      final optionIndices = <int>[
        for (var qi = 0; qi < widget.questions.length; qi++)
          (_selections[qi].toList()..sort()).first,
      ];
      final freeTexts = <String?>[
        for (var qi = 0; qi < widget.questions.length; qi++)
          optionIndices[qi] == _customIndexFor(qi)
              ? _customControllers[qi].text.trim()
              : null,
      ];
      final result = await context.read<ChatCubit>().answerAskUserQuestion(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
        optionIndex: optionIndices.first,
        optionIndices: optionIndices,
        askRequestId: widget.askRequestId,
        answers: answers,
        freeText: freeTexts.first,
        freeTexts: freeTexts,
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

  void _selectCustom(int questionIndex) {
    if (_answering) return;
    final custom = _customIndexFor(questionIndex);
    setState(() {
      _selections[questionIndex] = {custom};
      _focusedOptionIndex = custom;
      _inlineError = null;
    });
  }

  void _selectSingle(int questionIndex, int optionIndex) {
    if (_answering) return;
    setState(() {
      _selections[questionIndex] = {optionIndex};
      _focusedOptionIndex = optionIndex;
      _inlineError = null;
    });
    _unfocusAllCustomFields();
    _advanceAfterSelect(questionIndex);
  }

  void _toggleMulti(int questionIndex, int optionIndex) {
    if (_answering) return;
    final custom = _customIndexFor(questionIndex);
    setState(() {
      // Authored options and freeform Other are mutually exclusive.
      if (optionIndex == custom) {
        _selections[questionIndex] = {custom};
      } else {
        final next = {..._selections[questionIndex]}..remove(custom);
        if (next.contains(optionIndex)) {
          next.remove(optionIndex);
        } else {
          next.add(optionIndex);
        }
        _selections[questionIndex] = next;
        _unfocusAllCustomFields();
      }
      _focusedOptionIndex = optionIndex;
      _inlineError = null;
    });
  }

  void _unfocusAllCustomFields() {
    for (final node in _customFocusNodes) {
      if (node.hasFocus) node.unfocus();
    }
  }

  /// After answering a single-select question, move to the next page.
  void _advanceAfterSelect(int questionIndex) {
    if (questionIndex >= widget.questions.length - 1) return;
    if (widget.questions[questionIndex].multiSelect) return;
    _goToQuestion(questionIndex + 1);
  }

  void _activateFocusedOption() {
    final q = widget.questions[_activeQuestionIndex];
    final custom = _customIndexFor(_activeQuestionIndex);
    final oi = _focusedOptionIndex.clamp(0, custom);
    if (oi == custom) {
      _selectCustom(_activeQuestionIndex);
      _customFocusNodes[_activeQuestionIndex].requestFocus();
      return;
    }
    if (q.multiSelect) {
      _toggleMulti(_activeQuestionIndex, oi);
    } else {
      _selectSingle(_activeQuestionIndex, oi);
    }
  }

  void _moveFocus(int delta) {
    final count = _rowCountFor(_activeQuestionIndex);
    if (count == 0) return;
    final custom = _customIndexFor(_activeQuestionIndex);
    setState(() {
      _focusedOptionIndex = (_focusedOptionIndex + delta) % count;
      if (_focusedOptionIndex < 0) _focusedOptionIndex += count;
    });
    if (_focusedOptionIndex == custom) {
      _selectCustom(_activeQuestionIndex);
      _customFocusNodes[_activeQuestionIndex].requestFocus();
    } else {
      _unfocusAllCustomFields();
      _focusNode.requestFocus();
    }
  }

  void _goToQuestion(int index) {
    if (_answering) return;
    if (index < 0 || index >= widget.questions.length) return;
    _unfocusAllCustomFields();
    setState(() {
      _activeQuestionIndex = index;
      final selected = _selections[index];
      _focusedOptionIndex = selected.isEmpty
          ? 0
          : (selected.toList()..sort()).first;
    });
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _answering) return KeyEventResult.ignored;
    final customFocused = _customFocusNodes.any((n) => n.hasFocus);
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (customFocused) {
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _primaryAction();
        return KeyEventResult.handled;
      }
      // Digits / arrows go to the freeform field while it has focus.
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goToQuestion(_activeQuestionIndex - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goToQuestion(_activeQuestionIndex + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _activateFocusedOption();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_canSubmit || _canContinue) {
        _primaryAction();
      } else {
        _activateFocusedOption();
      }
      return KeyEventResult.handled;
    }
    final digit = _digitFromKey(event.logicalKey);
    if (digit != null) {
      final custom = _customIndexFor(_activeQuestionIndex);
      final oi = digit - 1;
      if (oi >= 0 && oi <= custom) {
        final q = widget.questions[_activeQuestionIndex];
        if (oi == custom) {
          _selectCustom(_activeQuestionIndex);
          _customFocusNodes[_activeQuestionIndex].requestFocus();
        } else if (q.multiSelect) {
          _toggleMulti(_activeQuestionIndex, oi);
        } else {
          _selectSingle(_activeQuestionIndex, oi);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  int? _digitFromKey(LogicalKeyboardKey key) {
    final digits = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
      LogicalKeyboardKey.numpad1: 1,
      LogicalKeyboardKey.numpad2: 2,
      LogicalKeyboardKey.numpad3: 3,
      LogicalKeyboardKey.numpad4: 4,
      LogicalKeyboardKey.numpad5: 5,
      LogicalKeyboardKey.numpad6: 6,
      LogicalKeyboardKey.numpad7: 7,
      LogicalKeyboardKey.numpad8: 8,
      LogicalKeyboardKey.numpad9: 9,
    };
    return digits[key];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final icons = TpTheme.of(context).iconSizes;

    final askReplyError = context.select<AgentAttentionCubit, String?>((c) {
      final entry = c.state.entryFor(
        sessionId: widget.session.sessionId,
        memberId: widget.seatId,
      );
      return entry?.askReplyError;
    });
    final displayError =
        _inlineError ??
        (askReplyError == null ? null : _mapAskReplyError(askReplyError, l10n));

    final activeIndex = _activeQuestionIndex.clamp(
      0,
      widget.questions.length - 1,
    );
    final active = widget.questions[activeIndex];
    final customIndex = _customIndexFor(activeIndex);
    final focused = _focusedOptionIndex.clamp(0, customIndex);
    final showPager = widget.questions.length > 1;
    final headerText = _headerLabel(activeIndex, l10n);

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Material(
          key: AppKeys.askUserQuestionCard,
          elevation: 0,
          color: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius + 4),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.lg,
              spacing.lg,
              spacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: spacing.md,
                        runSpacing: spacing.sm,
                        children: [
                          _HeaderPill(label: headerText),
                          SelectableText(
                            active.question,
                            style: styles
                                .mdColored(cs.onSurface)
                                .copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    if (showPager) ...[
                      SizedBox(width: spacing.md),
                      _QuestionPager(
                        current: activeIndex + 1,
                        total: widget.questions.length,
                        enabled: !_answering,
                        onPrev: () => _goToQuestion(activeIndex - 1),
                        onNext: () => _goToQuestion(activeIndex + 1),
                      ),
                    ],
                    SizedBox(width: spacing.md),
                    TpIconButton(
                      icon: Icons.terminal_rounded,
                      tooltip: l10n.agentAskAnswerInTerminal,
                      compact: true,
                      size: TpIconButton.kCompactSize,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      borderRadius: radius,
                      enabled: !_answering,
                      onTap: widget.onAnswerInTerminal,
                    ),
                  ],
                ),
                SizedBox(height: spacing.xl),
                _AlignedOptionList(
                  questionIndex: activeIndex,
                  options: active.options,
                  selected: _selections[activeIndex],
                  focusedIndex: focused,
                  enabled: !_answering,
                  customIndex: customIndex,
                  customController: _customControllers[activeIndex],
                  customFocusNode: _customFocusNodes[activeIndex],
                  customHint: l10n.agentAskCustomAnswerHint,
                  onOptionTap: (oi) {
                    if (active.multiSelect) {
                      _toggleMulti(activeIndex, oi);
                    } else {
                      _selectSingle(activeIndex, oi);
                    }
                  },
                  onCustomChanged: (_) {
                    _selectCustom(activeIndex);
                    setState(() {});
                  },
                  onCustomTap: () {
                    _selectCustom(activeIndex);
                    _customFocusNodes[activeIndex].requestFocus();
                  },
                ),
                if (displayError != null) ...[
                  SizedBox(height: spacing.md),
                  Text(
                    displayError,
                    key: AppKeys.askUserQuestionInlineError,
                    style: styles.mdColored(cs.error),
                  ),
                ],
                SizedBox(height: spacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: icons.md,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    SizedBox(width: spacing.sm),
                    Expanded(
                      child: SelectableText(
                        l10n.agentAskKeyboardHint,
                        style: styles
                            .mdColored(cs.onSurfaceVariant)
                            .copyWith(height: 1.4),
                      ),
                    ),
                    SizedBox(width: spacing.md),
                    TpButton(
                      variant: TpButtonVariant.ghost,
                      size: TpControlSize.medium,
                      onPressed: _answering ? null : _cancel,
                      child: Text(l10n.agentAskIgnore),
                    ),
                    SizedBox(width: spacing.sm),
                    TpButton(
                      key: _canSubmit
                          ? AppKeys.askUserQuestionSubmitButton
                          : AppKeys.askUserQuestionContinueButton,
                      variant: TpButtonVariant.primary,
                      size: TpControlSize.medium,
                      onPressed: (_canSubmit || _canContinue)
                          ? _primaryAction
                          : null,
                      child: Text(
                        _canSubmit
                            ? l10n.agentAskSubmitAnswers
                            : l10n.agentAskContinue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: styles.mdColored(cs.onSurfaceVariant).copyWith(height: 1.3),
      ),
    );
  }
}

class _QuestionPager extends StatelessWidget {
  const _QuestionPager({
    required this.current,
    required this.total,
    required this.enabled,
    required this.onPrev,
    required this.onNext,
  });

  final int current;
  final int total;
  final bool enabled;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    final radius = TpTheme.of(context).control.radius;
    final labelStyle = styles.mdColored(cs.onSurfaceVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TpIconButton(
          icon: Icons.chevron_left_rounded,
          compact: true,
          size: TpIconButton.kCompactSize,
          borderRadius: radius,
          color: cs.onSurfaceVariant,
          enabled: enabled && current > 1,
          onTap: onPrev,
        ),
        SizedBox(width: spacing.md),
        Text('$current / $total', style: labelStyle),
        SizedBox(width: spacing.md),
        TpIconButton(
          icon: Icons.chevron_right_rounded,
          compact: true,
          size: TpIconButton.kCompactSize,
          borderRadius: radius,
          color: cs.onSurfaceVariant,
          enabled: enabled && current < total,
          onTap: onNext,
        ),
      ],
    );
  }
}

/// Number / label / description columns aligned across option rows,
/// plus a trailing freeform "Other" row that matches the same rhythm.
class _AlignedOptionList extends StatelessWidget {
  const _AlignedOptionList({
    required this.questionIndex,
    required this.options,
    required this.selected,
    required this.focusedIndex,
    required this.enabled,
    required this.customIndex,
    required this.customController,
    required this.customFocusNode,
    required this.customHint,
    required this.onOptionTap,
    required this.onCustomChanged,
    required this.onCustomTap,
  });

  final int questionIndex;
  final List<AgentAskUserOption> options;
  final Set<int> selected;
  final int focusedIndex;
  final bool enabled;
  final int customIndex;
  final TextEditingController customController;
  final FocusNode customFocusNode;
  final String customHint;
  final ValueChanged<int> onOptionTap;
  final ValueChanged<String> onCustomChanged;
  final VoidCallback onCustomTap;

  static double _measureWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final spacing = context.tpSpacing;

    // Match chat body / question title (`md` = bodyMedium), not caption `sm`.
    final indexStyle = styles
        .mdColored(cs.onSurfaceVariant)
        .copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1.45,
        );
    final labelStyle = styles.mdColored(cs.onSurface).copyWith(height: 1.45);
    final descriptionStyle = styles
        .mdColored(cs.onSurfaceVariant)
        .copyWith(height: 1.45);
    final hintStyle = styles
        .mdColored(cs.onSurfaceVariant.withValues(alpha: 0.72))
        .copyWith(height: 1.45);

    var indexWidth = _measureWidth('${customIndex + 1}.', indexStyle);
    var labelWidth = 0.0;
    for (var oi = 0; oi < options.length; oi++) {
      final iw = _measureWidth('${oi + 1}.', indexStyle);
      if (iw > indexWidth) indexWidth = iw;
      final lw = _measureWidth(options[oi].label, labelStyle);
      if (lw > labelWidth) labelWidth = lw;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var oi = 0; oi < options.length; oi++) ...[
          if (oi > 0) SizedBox(height: spacing.xs),
          _OptionRow(
            key: AppKeys.askUserQuestionOptionAt(
              questionIndex: questionIndex,
              optionIndex: oi,
            ),
            indexLabel: '${oi + 1}.',
            option: options[oi],
            indexWidth: indexWidth,
            labelWidth: labelWidth,
            selected: selected.contains(oi),
            focused: focusedIndex == oi,
            enabled: enabled,
            radius: radius,
            indexStyle: indexStyle,
            labelStyle: labelStyle,
            descriptionStyle: descriptionStyle,
            onTap: () => onOptionTap(oi),
          ),
        ],
        SizedBox(height: spacing.xs),
        _CustomAnswerRow(
          key: AppKeys.askUserQuestionOptionAt(
            questionIndex: questionIndex,
            optionIndex: customIndex,
          ),
          indexLabel: '${customIndex + 1}.',
          indexWidth: indexWidth,
          controller: customController,
          focusNode: customFocusNode,
          hint: customHint,
          selected: selected.contains(customIndex),
          focused: focusedIndex == customIndex,
          enabled: enabled,
          radius: radius,
          indexStyle: indexStyle,
          labelStyle: labelStyle,
          hintStyle: hintStyle,
          onChanged: onCustomChanged,
          onTap: onCustomTap,
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.indexLabel,
    required this.option,
    required this.indexWidth,
    required this.labelWidth,
    required this.selected,
    required this.focused,
    required this.enabled,
    required this.radius,
    required this.indexStyle,
    required this.labelStyle,
    required this.descriptionStyle,
    required this.onTap,
    super.key,
  });

  final String indexLabel;
  final AgentAskUserOption option;
  final double indexWidth;
  final double labelWidth;
  final bool selected;
  final bool focused;
  final bool enabled;
  final double radius;
  final TextStyle indexStyle;
  final TextStyle labelStyle;
  final TextStyle descriptionStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;

    Color? bg;
    Color? accent;
    if (selected) {
      bg = cs.primary.withValues(alpha: 0.14);
      accent = cs.primary;
    } else if (focused) {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.28);
    }

    final effectiveIndex = accent == null
        ? indexStyle
        : indexStyle.copyWith(color: accent);
    final effectiveLabel = accent == null
        ? labelStyle
        : labelStyle.copyWith(color: accent);
    final effectiveDesc = accent == null
        ? descriptionStyle
        : descriptionStyle.copyWith(color: accent.withValues(alpha: 0.85));

    return TpHover(
      backgroundColor: bg ?? Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      // Keep focus on the card Focus node — otherwise the freeform TextField
      // can steal focus and wipe the authored selection via custom select.
      canRequestFocus: false,
      splashColor: Colors.transparent,
      // Keep the original InkWell overlayColor guard: a selected row keeps its
      // fill (primary 0.14) on hover instead of lightening to the hover tint.
      hoverColor: selected
          ? cs.primary.withValues(alpha: 0.14)
          : cs.primary.withValues(alpha: 0.08),
      enabled: enabled,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: indexWidth + spacing.md,
              child: Text(indexLabel, style: effectiveIndex),
            ),
            SizedBox(
              width: labelWidth + spacing.lg,
              child: Text(option.label, style: effectiveLabel),
            ),
            Expanded(
              child: option.description == null
                  ? const SizedBox.shrink()
                  : Text(option.description!, style: effectiveDesc),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomAnswerRow extends StatefulWidget {
  const _CustomAnswerRow({
    required this.indexLabel,
    required this.indexWidth,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.selected,
    required this.focused,
    required this.enabled,
    required this.radius,
    required this.indexStyle,
    required this.labelStyle,
    required this.hintStyle,
    required this.onChanged,
    required this.onTap,
    super.key,
  });

  final String indexLabel;
  final double indexWidth;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool selected;
  final bool focused;
  final bool enabled;
  final double radius;
  final TextStyle indexStyle;
  final TextStyle labelStyle;
  final TextStyle hintStyle;
  final ValueChanged<String> onChanged;
  final VoidCallback onTap;

  @override
  State<_CustomAnswerRow> createState() => _CustomAnswerRowState();
}

class _CustomAnswerRowState extends State<_CustomAnswerRow> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;

    Color? bg;
    Color? accent;
    if (widget.selected) {
      bg = cs.primary.withValues(alpha: 0.14);
      accent = cs.primary;
    } else if (_hovering) {
      bg = cs.primary.withValues(alpha: 0.08);
    } else if (widget.focused) {
      bg = cs.surfaceContainerHighest.withValues(alpha: 0.28);
    }

    final effectiveIndex = accent == null
        ? widget.indexStyle
        : widget.indexStyle.copyWith(color: accent);

    return MouseRegion(
      onEnter: widget.enabled
          ? (_) {
              if (!_hovering) setState(() => _hovering = true);
            }
          : null,
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      cursor: widget.enabled
          ? SystemMouseCursors.text
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: widget.enabled ? widget.onTap : null,
        child: Material(
          color: bg ?? Colors.transparent,
          borderRadius: BorderRadius.circular(widget.radius),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: widget.indexWidth + spacing.md,
                  child: Text(widget.indexLabel, style: effectiveIndex),
                ),
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      inputDecorationTheme: const InputDecorationTheme(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      onTap: widget.enabled ? widget.onTap : null,
                      onChanged: widget.onChanged,
                      style: accent == null
                          ? widget.labelStyle
                          : widget.labelStyle.copyWith(color: accent),
                      cursorColor: accent ?? cs.onSurfaceVariant,
                      cursorWidth: 1.2,
                      cursorHeight: (widget.labelStyle.fontSize ?? 14) * 1.2,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        fillColor: Colors.transparent,
                        hintText: widget.hint,
                        hintStyle: widget.hintStyle,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
