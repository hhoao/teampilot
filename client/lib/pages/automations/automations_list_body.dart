import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/automation_state.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../models/automation_tab_scope.dart';
import '../../models/launch_profile.dart';
import '../../models/workspace.dart';
import '../../repositories/automation_repository.dart';
import '../../services/automation/automation_launch_session_binding.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/coarse_relative_time.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import '../home_workspace/open_workspace_tab_actions.dart';
import 'automation_editor_dialog.dart';
import 'automation_schedule_picker.dart';
import 'automation_sort.dart';

String formatAutomationRunCountLabel(
  AppLocalizations l10n,
  Automation automation,
) {
  if (automation.hasRunLimit) {
    return l10n.automationsRunCountLimited(
      automation.runCount,
      automation.maxRunCount!,
    );
  }
  if (automation.runCount > 0) {
    return l10n.automationsRunCountUnlimited(automation.runCount);
  }
  return '';
}

/// Automation list without page/dialog chrome — used by the management tab and
/// dialog content wrapper.
class AutomationsListBody extends StatefulWidget {
  const AutomationsListBody({
    this.filterTabScope,
    this.filterSessionId,
    this.groupByTabScope = false,
    this.sort = AutomationSort.nameAsc,
    this.enabledFilter = AutomationEnabledFilter.all,
    this.actionFilter = AutomationActionFilter.all,
    super.key,
  });

  final AutomationTabScope? filterTabScope;
  final String? filterSessionId;
  final bool groupByTabScope;
  final AutomationSort sort;
  final AutomationEnabledFilter enabledFilter;
  final AutomationActionFilter actionFilter;

  @override
  State<AutomationsListBody> createState() => _AutomationsListBodyState();
}

class _AutomationsListBodyState extends State<AutomationsListBody> {
  var _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    final cubit = context.read<AutomationCubit>();
    if (widget.filterTabScope != null) {
      unawaited(cubit.loadForTabScope(widget.filterTabScope!));
    } else {
      unawaited(cubit.load());
    }
  }

  List<Automation> _visible(List<Automation> automations) {
    final filtered = filterAutomations(
      automations: automations,
      enabledFilter: widget.enabledFilter,
      actionFilter: widget.actionFilter,
      sessionId: widget.filterSessionId,
    );
    return sortAutomations(filtered, widget.sort);
  }

  Future<void> _reload() async {
    final cubit = context.read<AutomationCubit>();
    if (widget.filterTabScope != null) {
      await cubit.loadForTabScope(widget.filterTabScope!);
    } else {
      await cubit.load();
    }
  }

  Future<void> _toggleEnabled(Automation automation) async {
    await context.read<AutomationCubit>().toggleEnabled(
      automation.tabScope,
      automation.id,
    );
  }

  Future<void> _delete(Automation automation) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.automationsDeleteConfirm),
            const SizedBox(height: 12),
            Text(automation.name),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AutomationCubit>().delete(
      automation.tabScope,
      automation.id,
    );
  }

  Future<void> _edit(Automation automation) async {
    final saved = await AutomationEditorDialog.show(
      context,
      initial: automation,
      kind: automation.isScheduledMessage
          ? AutomationEditorKind.scheduledMessage
          : AutomationEditorKind.launchPrompt,
      launchProfileId: automation.launchProfileId,
      workspaceId: automation.workspaceId,
      sessionId: automation.sessionId,
    );
    if (saved != null) await _reload();
  }

  Future<void> _runNow(Automation automation) async {
    await context.read<AutomationCubit>().runNow(
      automation.tabScope,
      automation.id,
    );
  }

  void _showRunHistory(Automation automation, List<AutomationRun> runs) {
    unawaited(
      showAutomationRunHistoryDialog(
        context,
        automation: automation,
        runs: runs.take(10).toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    return BlocBuilder<AutomationCubit, AutomationState>(
      builder: (context, state) {
        if (state.status == AutomationLoadStatus.loading &&
            state.automations.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final automations = _visible(state.automations);
        if (automations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.automationsEmpty,
                style: styles.body.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (widget.groupByTabScope) {
          return _GroupedList(
            automations: automations,
            runsByAutomationId: state.runsByAutomationId,
            onToggleEnabled: _toggleEnabled,
            onShowRunHistory: _showRunHistory,
            onEdit: _edit,
            onDelete: _delete,
            onRunNow: _runNow,
            formatNextRun: (ms) => _formatNextRun(l10n, ms),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          itemCount: automations.length,
          itemBuilder: (context, index) {
            final a = automations[index];
            final runs = List<AutomationRun>.of(
              state.runsByAutomationId[a.id] ?? const [],
            )..sort((x, y) => y.scheduledForMs.compareTo(x.scheduledForMs));
            return AutomationRow(
              automation: a,
              scheduleSummary: localizedScheduleSummary(
                l10n,
                scheduleDraftFromAutomation(a),
              ),
              runCountLabel: formatAutomationRunCountLabel(l10n, a),
              nextRunLabel: _formatNextRun(l10n, a.nextRunAtMs),
              onToggleEnabled: () => unawaited(_toggleEnabled(a)),
              onShowRunHistory: () => _showRunHistory(a, runs),
              onEdit: () => unawaited(_edit(a)),
              onDelete: () => unawaited(_delete(a)),
              onRunNow: () => unawaited(_runNow(a)),
            );
          },
        );
      },
    );
  }

  String _formatNextRun(AppLocalizations l10n, int? nextRunAtMs) {
    if (nextRunAtMs == null) return l10n.automationsNextRunNone;
    final dt = DateTime.fromMillisecondsSinceEpoch(nextRunAtMs);
    final now = DateTime.now();
    if (dt.isAfter(now)) {
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return l10n.automationsNextRun(time);
      }
      return l10n.automationsNextRun('${dt.month}/${dt.day} $time');
    }
    return l10n.automationsNextRun(formatCoarseRelativeTime(l10n, dt));
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.automations,
    required this.runsByAutomationId,
    required this.onToggleEnabled,
    required this.onShowRunHistory,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    required this.formatNextRun,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final Future<void> Function(Automation) onToggleEnabled;
  final void Function(Automation, List<AutomationRun>) onShowRunHistory;
  final Future<void> Function(Automation) onEdit;
  final Future<void> Function(Automation) onDelete;
  final Future<void> Function(Automation) onRunNow;
  final String Function(int?) formatNextRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, chatState) {
        return BlocBuilder<LaunchProfileCubit, LaunchProfileState>(
          builder: (context, profileState) {
            return _buildGroupedList(
              context,
              l10n: l10n,
              cs: cs,
              styles: styles,
              workspaces: chatState.workspaces,
              identities: profileState.identities,
            );
          },
        );
      },
    );
  }

  Widget _buildGroupedList(
    BuildContext context, {
    required AppLocalizations l10n,
    required ColorScheme cs,
    required AppTextStyles styles,
    required List<Workspace> workspaces,
    required List<LaunchProfile> identities,
  }) {
    final grouped = <AutomationTabScope, List<Automation>>{};
    for (final a in automations) {
      grouped.putIfAbsent(a.tabScope, () => []).add(a);
    }
    final sortedGroups = grouped.entries.toList()
      ..sort(
        (a, b) =>
            automationTabScopeGroupLabel(
              l10n,
              a.key,
              workspaces,
              identities,
            ).compareTo(
              automationTabScopeGroupLabel(l10n, b.key, workspaces, identities),
            ),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      children: [
        for (final entry in sortedGroups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
            child: Text(
              automationTabScopeGroupLabel(
                l10n,
                entry.key,
                workspaces,
                identities,
              ),
              style: styles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...entry.value.map((a) {
            final runs = List<AutomationRun>.of(
              runsByAutomationId[a.id] ?? const [],
            )..sort((x, y) => y.scheduledForMs.compareTo(x.scheduledForMs));
            return AutomationRow(
              automation: a,
              scheduleSummary: localizedScheduleSummary(
                l10n,
                scheduleDraftFromAutomation(a),
              ),
              runCountLabel: formatAutomationRunCountLabel(l10n, a),
              nextRunLabel: formatNextRun(a.nextRunAtMs),
              onToggleEnabled: () => unawaited(onToggleEnabled(a)),
              onShowRunHistory: () => onShowRunHistory(a, runs),
              onEdit: () => unawaited(onEdit(a)),
              onDelete: () => unawaited(onDelete(a)),
              onRunNow: () => unawaited(onRunNow(a)),
            );
          }),
        ],
      ],
    );
  }
}

String automationTabScopeGroupLabel(
  AppLocalizations l10n,
  AutomationTabScope scope,
  List<Workspace> workspaces,
  List<LaunchProfile> identities,
) {
  final workspace = workspaces
      .where((w) => w.workspaceId == scope.workspaceId)
      .firstOrNull;
  if (workspace == null) {
    return scope.workspaceId;
  }
  return workspaceTabDisplayLabel(l10n: l10n, workspace: workspace);
}

class AutomationRow extends StatelessWidget {
  const AutomationRow({
    required this.automation,
    required this.scheduleSummary,
    required this.runCountLabel,
    required this.nextRunLabel,
    required this.onToggleEnabled,
    required this.onShowRunHistory,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    super.key,
  });

  final Automation automation;
  final String scheduleSummary;
  final String runCountLabel;
  final String nextRunLabel;
  final VoidCallback onToggleEnabled;
  final VoidCallback onShowRunHistory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final actionIcon = automation.isScheduledMessage
        ? Icons.send_rounded
        : Icons.play_arrow_rounded;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Icon(actionIcon, size: context.appIconSizes.md, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    automation.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.prominent,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scheduleSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.caption.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (AutomationLaunchSessionBinding.hasBinding(
                    automation,
                  )) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.automationsReuseSessionListHint(
                        automation.sessionId!,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.caption.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (runCountLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      runCountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.caption.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (automation.enabled) ...[
                    const SizedBox(height: 2),
                    Text(
                      nextRunLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.caption.copyWith(
                        color: cs.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.history_rounded,
              compact: true,
              size: AppIconButton.kCompactSize,
              tooltip: l10n.automationsRunHistory,
              onTap: onShowRunHistory,
            ),
            Switch(
              value: automation.enabled,
              onChanged: automation.isRunLimitReached
                  ? null
                  : (_) => onToggleEnabled(),
            ),
            SidebarActionMenuIconAnchor(
              icon: Icon(Icons.more_vert, size: context.appIconSizes.md),
              buildMenuChildren: (ctx, controller) => [
                SidebarActionMenuItem(
                  icon: Icons.edit_outlined,
                  label: l10n.automationsEdit,
                  menuController: controller,
                  onTap: onEdit,
                ),
                SidebarActionMenuItem(
                  icon: Icons.play_circle_outline,
                  label: l10n.automationsRunNow,
                  menuController: controller,
                  enabled: !automation.isRunLimitReached,
                  onTap: onRunNow,
                ),
                SidebarActionMenuItem(
                  icon: Icons.delete_outline,
                  label: l10n.automationsDelete,
                  destructive: true,
                  menuController: controller,
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAutomationRunHistoryDialog(
  BuildContext context, {
  required Automation automation,
  required List<AutomationRun> runs,
}) {
  final l10n = context.l10n;
  final cs = Theme.of(context).colorScheme;
  final styles = AppTextStyles.of(context);
  final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

  return showDialog<void>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 480,
      maxHeight: maxHeight,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.automationsRunHistory),
          const SizedBox(height: 8),
          if (runs.isEmpty)
            Text(
              l10n.automationsRunHistoryEmpty,
              style: styles.caption.copyWith(color: cs.onSurfaceVariant),
            )
          else
            ...runs.map((run) => AutomationRunHistoryRow(run: run)),
        ],
      ),
    ),
  );
}

class AutomationRunHistoryRow extends StatelessWidget {
  const AutomationRunHistoryRow({required this.run, super.key});

  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final when = DateTime.fromMillisecondsSinceEpoch(run.scheduledForMs);
    final label = _statusLabel(l10n, run.status);
    final statusColor = _statusColor(cs, run.status);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                formatCoarseRelativeTime(l10n, when),
                style: styles.prominent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: styles.bodySmall.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, AutomationRunStatus status) {
    return switch (status) {
      AutomationRunStatus.completed => l10n.automationsRunStatusCompleted,
      AutomationRunStatus.skippedUnavailable =>
        l10n.automationsSkippedUnavailable,
      AutomationRunStatus.skippedMissed =>
        l10n.automationsRunStatusSkippedMissed,
      AutomationRunStatus.dispatchFailed => l10n.automationsDispatchFailed,
      AutomationRunStatus.dispatching => l10n.automationsRunStatusDispatching,
      AutomationRunStatus.dispatched => l10n.automationsRunStatusDispatched,
      AutomationRunStatus.pending => l10n.automationsRunStatusPending,
    };
  }

  Color _statusColor(ColorScheme cs, AutomationRunStatus status) {
    return switch (status) {
      AutomationRunStatus.completed => cs.primary,
      AutomationRunStatus.skippedUnavailable ||
      AutomationRunStatus.skippedMissed => cs.onSurfaceVariant,
      AutomationRunStatus.dispatchFailed => cs.error,
      _ => cs.onSurface,
    };
  }
}

/// Summary for workspace sidebar header: enabled count + nearest next run.
class AutomationWorkspaceSummary {
  const AutomationWorkspaceSummary({
    required this.enabledCount,
    this.nearestNextRunAtMs,
  });

  final int enabledCount;
  final int? nearestNextRunAtMs;

  static AutomationWorkspaceSummary fromAutomations(
    List<Automation> automations,
    AutomationTabScope tabScope,
  ) {
    final enabled = automations
        .where(
          (a) =>
              a.workspaceId == tabScope.workspaceId &&
              a.launchProfileId == tabScope.launchProfileId &&
              a.enabled,
        )
        .toList();
    int? nearest;
    for (final a in enabled) {
      final next = a.nextRunAtMs;
      if (next == null) continue;
      if (nearest == null || next < nearest) nearest = next;
    }
    return AutomationWorkspaceSummary(
      enabledCount: enabled.length,
      nearestNextRunAtMs: nearest,
    );
  }

  static Future<AutomationWorkspaceSummary> load(
    AutomationRepository repo,
    AutomationTabScope tabScope,
  ) async {
    final automations = await repo.listForTabScope(tabScope);
    return fromAutomations(automations, tabScope);
  }
}
