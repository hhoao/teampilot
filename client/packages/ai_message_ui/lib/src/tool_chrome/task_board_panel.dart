import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../strings.dart';
import '../selection_dead_zone.dart';
import 'floating_capsule_chrome.dart';

/// Floating task-board card pinned to the top-right of the chat message area.
///
/// Collapsed to a small pill that shows the task currently in progress (or the
/// count when nothing is in progress); tapping expands to a 320 px card (title,
/// completed/total, status-icon + subject rows, "+N more").
///
/// [collapsedLeading] docks a chrome widget (e.g. the session's Chat/Terminal
/// view toggle) into the collapsed pill, LEFT of the task data, so the two
/// share one capsule. When [items] is empty the pill still renders — hosting
/// only the leading widget — unless it is null.
class AiTaskBoardPanel extends StatefulWidget {
  const AiTaskBoardPanel({
    required this.items,
    this.maxVisible = 6,
    this.collapsedLeading,
    super.key,
  });

  final List<AiTaskBoardItem> items;
  final int maxVisible;

  /// Icon-only control shown at the left edge of the collapsed pill.
  final Widget? collapsedLeading;

  @override
  State<AiTaskBoardPanel> createState() => _AiTaskBoardPanelState();
}

class _AiTaskBoardPanelState extends State<AiTaskBoardPanel> {
  bool _expanded = false;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final leading = widget.collapsedLeading;
    if (widget.items.isEmpty) {
      if (leading == null) return const SizedBox.shrink();
      // No tasks yet: the docked control carries its own pill chrome
      // (TpSegmentedControl); no outer task-board capsule to add.
      return SelectionArea(
        child: SelectionDeadZone(child: leading),
      );
    }
    // SelectionArea makes task content selectable / copyable.
    return SelectionArea(
      child: _expanded ? _buildExpanded(context) : _buildCollapsed(context),
    );
  }

  /// Max height for the task list inside the expanded card (scrolls beyond).
  double _maxListHeight(BuildContext context) {
    return (MediaQuery.sizeOf(context).height * 0.4)
        .clamp(180.0, 360.0)
        .toDouble();
  }

  /// Overlay chrome so the floating board reads against the chat surface.
  Widget _chrome({
    required BuildContext context,
    required BorderRadius borderRadius,
    required Widget child,
  }) {
    return AiFloatingCapsuleChrome(
      borderRadius: borderRadius,
      child: child,
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    final completed = widget.items
        .where((t) => t.status == AiTaskStatus.completed)
        .length;
    final countText = strings.taskBoardCountLabel(
      completed,
      widget.items.length,
    );
    // Surface the task currently in progress; fall back to the count pill
    // when nothing is in progress.
    final active = widget.items
        .where((t) => t.status == AiTaskStatus.inProgress)
        .firstOrNull;
    final activeSubject = active?.subject.trim();
    final showActive = activeSubject != null && activeSubject.isNotEmpty;
    final label = showActive ? activeSubject : countText;
    final leading = widget.collapsedLeading;
    // Collapsed pill is chrome: keep taps from becoming text-selection drags
    // under the outer SelectionArea (which makes the count hard to click).
    return SelectionDeadZone(
      child: _chrome(
        context: context,
        borderRadius: BorderRadius.circular(999),
        child: TpHover(
          shape: TpPressableShape.stadium,
          onTap: () => setState(() {
            _expanded = true;
            _showAll = false;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  SelectionDeadZone(child: leading),
                  const SizedBox(width: 4),
                  Container(
                    width: 1,
                    height: 14,
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                ],
                if (showActive)
                  _TaskStatusIcon(
                    status: AiTaskStatus.inProgress,
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
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    final tasks = widget.items;
    final visible = _showAll ? tasks : tasks.take(widget.maxVisible).toList();
    final hasMore = tasks.length > widget.maxVisible;
    final completed = tasks
        .where((t) => t.status == AiTaskStatus.completed)
        .length;
    return _chrome(
      context: context,
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
                    strings.taskBoardTitle,
                    style: TpTextStyles.of(
                      context,
                    ).mdColored(scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    strings.taskBoardCountLabel(completed, tasks.length),
                    style: TpTextStyles.of(
                      context,
                    ).smColored(scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                  SelectionDeadZone(
                    child: TpHover(
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
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Cap the list height; overflow scrolls inside the card so a
              // huge task board does not cover the whole chat.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _maxListHeight(context)),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final task in visible) _TaskRow(task: task),
                    ],
                  ),
                ),
              ),
              if (hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SelectionDeadZone(
                    child: TpHover(
                      onTap: () => setState(() => _showAll = !_showAll),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _showAll
                                  ? strings.taskBoardShowLess
                                  : strings.taskBoardMoreLabel(
                                      tasks.length - widget.maxVisible,
                                    ),
                              style: TpTextStyles.of(
                                context,
                              ).smColored(scheme.primary),
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

  final AiTaskBoardItem task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subject = task.subject.trim().isEmpty ? '…' : task.subject;
    final done = task.status == AiTaskStatus.completed;
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

  final AiTaskStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      AiTaskStatus.pending => Icon(
        Icons.radio_button_unchecked,
        size: 16,
        color: color,
      ),
      AiTaskStatus.inProgress => Icon(
        Icons.arrow_forward,
        size: 16,
        color: color,
      ),
      AiTaskStatus.completed => Icon(
        Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      AiTaskStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 16,
        color: color,
      ),
      AiTaskStatus.unknown => Icon(Icons.help_outline, size: 16, color: color),
    };
  }
}
