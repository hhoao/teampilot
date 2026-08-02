import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/progress_activity.dart';
import '../../services/progress_activity/progress_fraction.dart';
import '../notification/progress_activity_tile.dart';
import '../progress_activity/progress_activity_detail_dialog.dart';
import 'workspace_status_bar.dart';

/// Closed status-bar pill + optional activities popover (`progress-activities`).
class ProgressActivitiesStatusItem implements WorkspaceStatusBarItem {
  ProgressActivitiesStatusItem({this.workspaceId});

  /// Active workspace from the host; null shows app-global activities only.
  final String? workspaceId;

  @override
  String get id => 'progress-activities';

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) {
    return _ProgressActivitiesStatusSegment(
      workspaceId: workspaceId,
      compact: compact,
    );
  }
}

class _ProgressActivitiesStatusSegment extends StatefulWidget {
  const _ProgressActivitiesStatusSegment({
    required this.workspaceId,
    required this.compact,
  });

  final String? workspaceId;
  final bool compact;

  @override
  State<_ProgressActivitiesStatusSegment> createState() =>
      _ProgressActivitiesStatusSegmentState();
}

class _ProgressActivitiesStatusSegmentState
    extends State<_ProgressActivitiesStatusSegment> {
  final _popover = TpPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  void _openDetail(BuildContext context, String activityId) {
    final cubit = context.read<ProgressActivityCubit>();
    cubit.setDetailOpen(activityId, true);
    unawaited(
      showProgressActivityDetailDialog(context, activityId: activityId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProgressActivityCubit, ProgressActivityState>(
      buildWhen: (previous, next) {
        final prev = previous.forWorkspace(widget.workspaceId);
        final curr = next.forWorkspace(widget.workspaceId);
        if (prev.length != curr.length) return true;
        for (var i = 0; i < prev.length; i++) {
          if (prev[i] != curr[i]) return true;
        }
        return false;
      },
      builder: (context, state) {
        final activities = state.forWorkspace(widget.workspaceId);
        if (activities.isEmpty) return const SizedBox.shrink();

        final l10n = context.l10n;
        final cubit = context.read<ProgressActivityCubit>();

        if (activities.length == 1) {
          final activity = activities.single;
          final label = activity.title;
          final percent = _percentLabel(activity);
          final tooltip = percent == null ? label : '$label · $percent';

          return Tooltip(
            message: tooltip,
            child: _PillButton(
              key: const Key('progress-activities-pill'),
              compact: widget.compact,
              label: label,
              percent: percent,
              indeterminate: percent == null,
              icon: progressActivityKindIcon(activity.kind),
              onTap: () => _openDetail(context, activity.id),
            ),
          );
        }

        final label = l10n.progressActivitiesMany(activities.length);
        return TpActionMenuAnchor(
          controller: _popover,
          fixedPanelWidth: _ProgressActivitiesPanel.panelWidth,
          closeOnTapOutside: true,
          anchor: const TpAnchor(
            childAlignment: Alignment.bottomRight,
            overlayAlignment: Alignment.topRight,
            offset: Offset(0, -8),
          ),
          popoverBuilder: (context, menu) => _ProgressActivitiesPanel(
            activities: activities,
            onActivityTap: (id) {
              menu.close();
              _openDetail(context, id);
            },
            onCancel: cubit.requestCancel,
          ),
          child: Tooltip(
            message: label,
            child: _PillButton(
              key: const Key('progress-activities-pill'),
              compact: widget.compact,
              label: label,
              percent: null,
              indeterminate: true,
              icon: Icons.sync,
              onTap: _popover.toggle,
            ),
          ),
        );
      },
    );
  }
}

String? _percentLabel(ProgressActivity activity) {
  final fraction = resolveProgressFraction(activity);
  if (fraction == null) return null;
  return '${(fraction.clamp(0.0, 1.0) * 100).round()}%';
}

class _ProgressActivitiesPanel extends StatelessWidget {
  const _ProgressActivitiesPanel({
    required this.activities,
    required this.onActivityTap,
    required this.onCancel,
  });

  static const double panelWidth = 360;

  final List<ProgressActivity> activities;
  final ValueChanged<String> onActivityTap;
  final ValueChanged<String> onCancel;

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
              l10n.progressActivitiesPanelTitle,
              style: styles.xs.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                height: 1.0,
              ),
            ),
          ),
          for (var i = 0; i < activities.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            ProgressActivityTile(
              activity: activities[i],
              onTap: () => onActivityTap(activities[i].id),
              onCancel: () => onCancel(activities[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    super.key,
    required this.compact,
    required this.label,
    required this.percent,
    required this.indeterminate,
    required this.icon,
    required this.onTap,
  });

  final bool compact;
  final String label;
  final String? percent;
  final bool indeterminate;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    final compact = this.compact;

    Widget trailing;
    if (percent != null) {
      trailing = Text(
        percent!,
        style: styles.xs.copyWith(
          color: muted,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else if (indeterminate) {
      trailing = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: cs.primary,
        ),
      );
    } else {
      trailing = const SizedBox.shrink();
    }

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: cs.onSurface.withValues(alpha: 0.07),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: muted),
          if (!compact) ...[
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.xs.copyWith(
                  color: muted,
                  height: 1.0,
                ),
              ),
            ),
          ],
          const SizedBox(width: 6),
          trailing,
        ],
      ),
    );
  }
}
