import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/automation_state.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../services/automation/scheduled_task_summary.dart';
import 'workspace_status_bar.dart';

/// Global scheduled-tasks pill + popover (`scheduled-tasks`).
class ScheduledTasksStatusItem implements WorkspaceStatusBarItem {
  ScheduledTasksStatusItem({this.onEditAutomation, this.onManage});

  final ValueChanged<Automation>? onEditAutomation;
  final VoidCallback? onManage;

  @override
  String get id => 'scheduled-tasks';

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) {
    return _ScheduledTasksStatusSegment(
      compact: compact,
      onEditAutomation: onEditAutomation,
      onManage: onManage,
    );
  }
}

class _ScheduledTasksStatusSegment extends StatefulWidget {
  const _ScheduledTasksStatusSegment({
    required this.compact,
    this.onEditAutomation,
    this.onManage,
  });

  final bool compact;
  final ValueChanged<Automation>? onEditAutomation;
  final VoidCallback? onManage;

  @override
  State<_ScheduledTasksStatusSegment> createState() =>
      _ScheduledTasksStatusSegmentState();
}

class _ScheduledTasksStatusSegmentState
    extends State<_ScheduledTasksStatusSegment> {
  final _popover = TpPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AutomationCubit, AutomationState>(
      buildWhen: (previous, next) =>
          !listEquals(previous.globalAutomations, next.globalAutomations),
      builder: (context, state) {
        final summary = ScheduledTaskSummary.fromAutomations(
          state.globalAutomations,
        );
        final l10n = context.l10n;
        final cs = Theme.of(context).colorScheme;
        final styles = TpTextStyles.of(context);
        final nextLabel = summary.nextRunAtMs == null
            ? null
            : formatScheduledTaskNextRun(summary.nextRunAtMs!);
        final label = widget.compact
            ? '${summary.active.length}'
            : nextLabel == null
            ? '${summary.active.length}'
            : '${summary.active.length} · $nextLabel';

        return TpActionMenuAnchor(
          controller: _popover,
          fixedPanelWidth: _ScheduledTasksPanel.panelWidth,
          closeOnTapOutside: true,
          anchor: const TpAnchor(
            childAlignment: Alignment.bottomRight,
            overlayAlignment: Alignment.topRight,
            offset: Offset(0, -8),
          ),
          popoverBuilder: (context, menu) => _ScheduledTasksPanel(
            summary: summary,
            onEdit: (automation) {
              menu.close();
              widget.onEditAutomation?.call(automation);
            },
            onManage: () {
              menu.close();
              widget.onManage?.call();
            },
          ),
          child: Tooltip(
            message: l10n.automationsSidebarTitle,
            child: TpHover(
              key: const Key('scheduled-tasks-pill'),
              onTap: _popover.toggle,
              borderRadius: BorderRadius.circular(6),
              hoverColor: cs.onSurface.withValues(alpha: 0.07),
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 6 : 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.alarm_rounded,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: styles.xs.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScheduledTasksPanel extends StatelessWidget {
  const _ScheduledTasksPanel({
    required this.summary,
    required this.onEdit,
    required this.onManage,
  });

  static const double panelWidth = 340;
  static const double _listMaxHeight = 320;

  final ScheduledTaskSummary summary;
  final ValueChanged<Automation> onEdit;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: panelWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              l10n.automationsSidebarTitle,
              style: styles.xs.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                height: 1.0,
              ),
            ),
          ),
          if (summary.active.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.alarm_rounded,
                      key: const Key('scheduled-tasks-empty-icon'),
                      size: 20,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.automationsStatusBarEmpty,
                      style: styles.smColored(cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _listMaxHeight),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: summary.active.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.25),
                ),
                itemBuilder: (context, index) {
                  final automation = summary.active[index];
                  return _ScheduledTaskRow(
                    automation: automation,
                    onTap: () => onEdit(automation),
                  );
                },
              ),
            ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.25)),
          TpHover(
            key: const Key('scheduled-tasks-manage'),
            onTap: onManage,
            borderRadius: BorderRadius.circular(6),
            hoverColor: cs.onSurface.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.automationsManageAll,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.smMediumColored(cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledTaskRow extends StatelessWidget {
  const _ScheduledTaskRow({required this.automation, required this.onTap});

  final Automation automation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final next = automation.nextRunAtMs;
    final timeLabel = next == null
        ? l10n.automationsNextRunNone
        : l10n.automationsNextRun(formatScheduledTaskNextRun(next));

    return TpHover(
      key: ValueKey('scheduled-task-${automation.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: cs.onSurface.withValues(alpha: 0.06),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              automation.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.smMediumColored(cs.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              timeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.xs.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
