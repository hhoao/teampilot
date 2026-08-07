import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../services/cli/tasks/cli_task_board.dart';

/// Floating task-board card pinned to the top-right of the chat message area.
///
/// Collapsed to a small pill that shows the task currently in progress (or the
/// count when nothing is in progress); tapping expands to a 320 px card (title,
/// completed/total, status-icon + subject rows, "+N more").
class SessionCliTaskPanel extends StatefulWidget {
  const SessionCliTaskPanel({
    required this.board,
    required this.title,
    required this.countText,
    required this.moreLabel,
    required this.showLessLabel,
    this.maxVisible = 6,
    super.key,
  });

  final CliTaskBoard board;
  final String title;

  /// Pre-formatted "{completed}/{total}" label.
  final String countText;

  /// Overflow label builder, e.g. "… +3 more".
  final String Function(int count) moreLabel;

  /// Label for collapsing the overflow back to [maxVisible] rows.
  final String showLessLabel;

  final int maxVisible;

  @override
  State<SessionCliTaskPanel> createState() => _SessionCliTaskPanelState();
}

class _SessionCliTaskPanelState extends State<SessionCliTaskPanel> {
  bool _expanded = false;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    if (board.totalCount == 0) return const SizedBox.shrink();
    // SelectionArea makes task content selectable / copyable.
    return SelectionArea(
      child: _expanded
          ? _buildExpanded(context, board)
          : _buildCollapsed(context),
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Surface the task currently in progress; fall back to the count pill
    // when nothing is in progress.
    final active = widget.board.tasks
        .where((t) => t.status == CliTaskStatus.inProgress)
        .firstOrNull;
    final activeSubject = active?.subject.trim();
    final showActive = activeSubject != null && activeSubject.isNotEmpty;
    final label = showActive ? activeSubject : widget.countText;
    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() {
          _expanded = true;
          _showAll = false;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showActive)
                _TaskStatusIcon(
                  status: CliTaskStatus.inProgress,
                  color: scheme.primary,
                )
              else
                Icon(Icons.task_alt_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              if (showActive)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: _OverflowTooltipText(
                    text: label,
                    maxLines: 1,
                    style: TpTextStyles.of(context).smColored(scheme.onSurface),
                  ),
                )
              else
                Text(
                  label,
                  style: TpTextStyles.of(context).smColored(scheme.onSurface),
                ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context, CliTaskBoard board) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = board.tasks;
    final visible = _showAll ? tasks : tasks.take(widget.maxVisible).toList();
    final hasMore = tasks.length > widget.maxVisible;
    return Material(
      color: scheme.surface,
      elevation: 4,
      shadowColor: scheme.shadow,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: TpTextStyles.of(context).mdColored(
                      scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.countText,
                    style: TpTextStyles.of(context).smColored(
                      scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() {
                      _expanded = false;
                      _showAll = false;
                    }),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_fullscreen_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (final task in visible) _TaskRow(task: task),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: InkWell(
                    onTap: () => setState(() => _showAll = !_showAll),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showAll
                                ? widget.showLessLabel
                                : widget.moreLabel(tasks.length - widget.maxVisible),
                            style: TpTextStyles.of(context).smColored(
                              scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _showAll ? Icons.expand_less : Icons.expand_more,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final CliTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = task.subject.trim().isEmpty ? '…' : task.subject;
    final done = task.status == CliTaskStatus.completed;
    final textStyle = TpTextStyles.of(context).smColored(scheme.onSurface);
    // Center the 16px icon on the FIRST text line (not the whole 1–2 line
    // block) by nudging it into the first line box.
    const iconSize = 16.0;
    final lineHeight = (textStyle.fontSize ?? 12) * (textStyle.height ?? 1.0);
    final iconTop = ((lineHeight - iconSize) / 2).clamp(0.0, double.infinity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: iconTop),
            child: _TaskStatusIcon(
              status: task.status,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _OverflowTooltipText(
              text: subject,
              maxLines: 2,
              style: textStyle.copyWith(
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ellipsizes [text] but shows a hover tooltip with the full content only
/// when the text actually overflows its box (short subjects stay tooltip-free).
class _OverflowTooltipText extends StatelessWidget {
  const _OverflowTooltipText({
    required this.text,
    required this.style,
    this.maxLines = 2,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final label = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!painter.didExceedMaxLines) return label;
        return Tooltip(message: text, child: label);
      },
    );
  }
}

class _TaskStatusIcon extends StatelessWidget {
  const _TaskStatusIcon({required this.status, required this.color});

  final CliTaskStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      CliTaskStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: color,
      ),
      CliTaskStatus.inProgress => Icon(
        Icons.arrow_forward,
        size: 16,
        color: color,
      ),
      CliTaskStatus.completed => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      CliTaskStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: color,
      ),
      CliTaskStatus.unknown => Icon(
        Icons.help_outline,
        size: 16,
        color: color,
      ),
    };
  }
}
