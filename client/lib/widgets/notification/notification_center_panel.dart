import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/notification_cubit.dart';
import '../../cubits/progress_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../router/app_router.dart';
import '../../services/notification/notification_center_open.dart';
import 'notification_list_tile.dart';
import 'progress_activity_tile.dart';
import '../progress_activity/progress_activity_detail_dialog.dart';

const notificationCenterPanelWidth = 560.0;
const notificationCenterPanelListMaxHeight = 360.0;

class NotificationCenterPanel extends StatelessWidget {
  const NotificationCenterPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final notificationCubit = context.read<NotificationCubit>();
    final progressCubit = context.read<ProgressActivityCubit>();
    final historyItems = context.select((NotificationCubit c) => c.state.items);
    final ongoing = context.select(
      (ProgressActivityCubit c) => c.state.activities,
    );
    final hasOngoing = ongoing.isNotEmpty;
    final hasHistory = historyItems.isNotEmpty;
    final isEmpty = !hasOngoing && !hasHistory;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: notificationCenterPanelWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.notificationCenterTitle,
                  style: styles.mdSemiboldTightSnug,
                ),
              ),
              IconButton(
                tooltip: l10n.notificationMarkAllRead,
                onPressed: hasHistory
                    ? () => unawaited(notificationCubit.markAllRead())
                    : null,
                icon: const Icon(Icons.done_all, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const TpActionMenuDivider(),
          if (isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.notificationEmpty,
                textAlign: TextAlign.center,
                style: styles.mutedMd,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: notificationCenterPanelListMaxHeight,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasOngoing) ...[
                      _SectionHeader(label: l10n.notificationOngoingSection),
                      for (var i = 0; i < ongoing.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.25),
                          ),
                        ProgressActivityTile(
                          activity: ongoing[i],
                          onTap: () {
                            final id = ongoing[i].id;
                            progressCubit.setDetailOpen(id, true);
                            unawaited(
                              showProgressActivityDetailDialog(
                                context,
                                activityId: id,
                              ),
                            );
                          },
                          onCancel: () =>
                              progressCubit.requestCancel(ongoing[i].id),
                        ),
                      ],
                    ],
                    if (hasOngoing && hasHistory)
                      Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    if (hasHistory) ...[
                      _SectionHeader(label: l10n.notificationHistorySection),
                      for (var i = 0; i < historyItems.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: cs.outlineVariant.withValues(alpha: 0.25),
                          ),
                        NotificationListTile(
                          notification: historyItems[i],
                          onMarkRead: () =>
                              notificationCubit.markRead(historyItems[i].id),
                          onDelete: () =>
                              notificationCubit.delete(historyItems[i].id),
                          onOpen: () {
                            final item = historyItems[i];
                            unawaited(
                              openNotificationCenterItem(
                                notification: item,
                                markRead: notificationCubit.markRead,
                                go: (location) {
                                  onClose();
                                  appRouter.go(location);
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          const TpActionMenuDivider(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: hasHistory
                  ? () => unawaited(notificationCubit.clearAll())
                  : null,
              child: Text(l10n.notificationClearAll),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(label, style: styles.mutedSm),
    );
  }
}
