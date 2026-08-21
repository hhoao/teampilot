import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/progress_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/progress_activity.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/progress_activity/progress_fraction.dart';
import '../notification/progress_activity_tile.dart';

Future<void> showProgressActivityDetailDialog(
  BuildContext context, {
  required String activityId,
}) {
  final cubit = context.read<ProgressActivityCubit>();
  return showTpDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => BlocProvider.value(
      value: cubit,
      child: _ProgressActivityDetailDialog(activityId: activityId),
    ),
  ).whenComplete(() {
    if (cubit.isClosed) return;
    cubit.setDetailOpen(activityId, false);
  });
}

class _ProgressActivityDetailDialog extends StatelessWidget {
  const _ProgressActivityDetailDialog({required this.activityId});

  final String activityId;

  void _close(BuildContext context) {
    final cubit = context.read<ProgressActivityCubit>();
    cubit.setDetailOpen(activityId, false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ProgressActivityCubit, ProgressActivityState>(
      listenWhen: (previous, current) {
        final wasPresent = previous.activities.any((a) => a.id == activityId);
        final isPresent = current.activities.any((a) => a.id == activityId);
        return wasPresent && !isPresent;
      },
      listener: (context, state) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: BlocBuilder<ProgressActivityCubit, ProgressActivityState>(
        buildWhen: (previous, current) {
          final prev = _findActivity(previous);
          final next = _findActivity(current);
          return prev != next;
        },
        builder: (context, state) {
          final activity = _findActivity(state);
          if (activity == null) {
            return const SizedBox.shrink();
          }
          return _ProgressActivityDetailBody(
            activity: activity,
            onClose: () => _close(context),
            onCancel: () => _requestCancel(context, activity),
          );
        },
      ),
    );
  }

  ProgressActivity? _findActivity(ProgressActivityState state) {
    for (final activity in state.activities) {
      if (activity.id == activityId) return activity;
    }
    return null;
  }
}

void _requestCancel(BuildContext context, ProgressActivity activity) {
  final jobKey = activity.jobKey;
  if (jobKey != null) {
    context.read<InstallJobRegistry>().requestCancel(jobKey);
    return;
  }
  context.read<ProgressActivityCubit>().requestCancel(activity.id);
}

class _ProgressActivityDetailBody extends StatelessWidget {
  const _ProgressActivityDetailBody({
    required this.activity,
    required this.onClose,
    required this.onCancel,
  });

  final ProgressActivity activity;
  final VoidCallback onClose;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final fraction = resolveProgressFraction(activity);
    final isCancelling = activity.phase == ProgressActivityPhase.cancelling;
    final canCancel = activity.cancellable && !isCancelling;
    final subtitle = activity.subtitle?.trim();

    Widget progressBar;
    if (fraction != null) {
      progressBar = LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        borderRadius: BorderRadius.circular(4),
        backgroundColor: cs.surfaceContainerHighest,
      );
    } else {
      progressBar = LinearProgressIndicator(
        borderRadius: BorderRadius.circular(4),
        backgroundColor: cs.surfaceContainerHighest,
      );
    }

    return TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: activity.title,
            closeTooltip: l10n.windowControlClose,
            onClose: onClose,
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  progressActivityKindIcon(activity.kind),
                  size: 22,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: styles.mdColored(cs.onSurfaceVariant),
                      ),
                    if (activity.totalItems != null &&
                        activity.totalItems! > 0) ...[
                      if (subtitle != null && subtitle.isNotEmpty)
                        const SizedBox(height: 8),
                      Text(
                        '${activity.completedItems ?? 0} / ${activity.totalItems}',
                        style: styles.mutedMd,
                      ),
                    ],
                    const SizedBox(height: 12),
                    progressBar,
                  ],
                ),
              ),
            ],
          ),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: onClose,
                child: Text(l10n.windowControlClose),
              ),
              if (activity.cancellable)
                TextButton(
                  onPressed: canCancel ? onCancel : null,
                  child: Text(l10n.cancel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
