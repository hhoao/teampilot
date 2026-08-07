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
    this.maxVisible = 6,
    super.key,
  });

  final CliTaskBoard board;
  final String title;

  /// Pre-formatted "{completed}/{total}" label.
  final String countText;

  /// Overflow label builder, e.g. "… +3 more".
  final String Function(int count) moreLabel;

  final int maxVisible;

  @override
  State<SessionCliTaskPanel> createState() => _SessionCliTaskPanelState();
}

class _SessionCliTaskPanelState extends State<SessionCliTaskPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final board = widget.board;
    if (board.totalCount == 0) return const SizedBox.shrink();
    if (!_expanded) return _buildCollapsed(context);
    return _buildExpanded(context, board);
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
        onTap: () => setState(() => _expanded = true),
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
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    final visible = board.tasks.take(widget.maxVisible).toList();
    final overflow = board.tasks.length - visible.length;
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
                    onTap: () => setState(() => _expanded = false),
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
              if (overflow > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.moreLabel(overflow),
                    style: TpTextStyles.of(context).smColored(
                      scheme.onSurfaceVariant,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: _TaskStatusIcon(
              status: task.status,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subject,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(context)
                  .smColored(scheme.onSurface)
                  .copyWith(
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
      CliTaskStatus.inProgress => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
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
