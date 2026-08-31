import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/automation_state.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/cli_presets_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../models/automation_list_scope.dart';
import '../../models/workspace.dart';
import '../../services/automation/automation_launch_session_binding.dart';
import '../../services/automation/automation_scope_label.dart';
import '../../utils/ui/coarse_relative_time.dart';
import '../../utils/workspace/workspace_display_name.dart';
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
      automation.effectiveMaxRunCount!,
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
    this.listScope,
    this.sort = AutomationSort.nameAsc,
    this.enabledFilter = AutomationEnabledFilter.all,
    this.actionFilter = AutomationActionFilter.all,
    this.shrinkWrap = false,
    super.key,
  });

  final AutomationListScope? listScope;
  final AutomationSort sort;
  final AutomationEnabledFilter enabledFilter;
  final AutomationActionFilter actionFilter;

  /// When true, list sizes to its children (for content-adaptive dialogs).
  final bool shrinkWrap;

  @override
  State<AutomationsListBody> createState() => _AutomationsListBodyState();
}

class _AutomationsListBodyState extends State<AutomationsListBody> {
  var _loadedScopeKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant AutomationsListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listScope != widget.listScope) {
      _loadedScopeKey = '';
      _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    final scopeKey = _scopeKey(widget.listScope);
    if (_loadedScopeKey == scopeKey) return;
    _loadedScopeKey = scopeKey;
    unawaited(_reload(context.read<AutomationCubit>()));
  }

  String _scopeKey(AutomationListScope? scope) {
    if (scope == null) return 'all';
    if (scope.isWorkspace) return 'workspace:${scope.workspaceId}';
    if (scope.isSession) {
      return 'session:${scope.workspaceId}:${scope.sessionId}';
    }
    return 'all';
  }

  List<Automation> _visible(AutomationState state) {
    final sessionId = widget.listScope?.isSession == true
        ? widget.listScope!.sessionId
        : null;
    final filtered = filterAutomations(
      automations: state.visibleAutomations,
      enabledFilter: widget.enabledFilter,
      actionFilter: widget.actionFilter,
      sessionId: sessionId,
    );
    return sortAutomations(filtered, widget.sort);
  }

  Future<void> _reload(AutomationCubit cubit) async {
    final scope = widget.listScope;
    if (scope == null || scope.isAll) {
      await cubit.load();
      return;
    }
    if (scope.isWorkspace) {
      await cubit.loadForWorkspace(scope.workspaceId!);
      return;
    }
    if (scope.isSession) {
      final workspaceId = scope.workspaceId!;
      final sessionId = scope.sessionId!;
      final session = context
          .read<ChatCubit>()
          .state
          .sessions
          .where(
            (s) => s.sessionId == sessionId && s.workspaceId == workspaceId,
          )
          .firstOrNull;
      if (session != null) {
        await cubit.loadForSession(workspaceId, session);
      } else {
        await cubit.loadForWorkspace(workspaceId);
      }
    }
  }

  bool get _groupByLaunchContext {
    final scope = widget.listScope;
    return scope == null || scope.isAll || scope.isWorkspace;
  }

  Future<void> _toggleEnabled(Automation automation) async {
    await context.read<AutomationCubit>().toggleEnabled(
      automation.workspaceId,
      automation.id,
    );
  }

  Future<void> _delete(Automation automation) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => TpDialog(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(title: l10n.automationsDeleteConfirm),
            const SizedBox(height: 12),
            Text(automation.name),
            TpDialogActions(
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
      automation.workspaceId,
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
      workspaceId: automation.workspaceId,
      sessionId: automation.sessionId,
    );
    if (saved != null) await _reload(context.read<AutomationCubit>());
  }

  Future<void> _runNow(Automation automation) async {
    await context.read<AutomationCubit>().runNow(
      automation.workspaceId,
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
    final styles = TpTextStyles.of(context);

    return BlocBuilder<AutomationCubit, AutomationState>(
      builder: (context, state) {
        if (state.status == AutomationLoadStatus.loading &&
            state.automations.isEmpty) {
          if (widget.shrinkWrap) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final automations = _visible(state);
        if (automations.isEmpty) {
          final empty = Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.automationsEmpty,
              style: styles.mdColored(cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          );
          return widget.shrinkWrap ? empty : Center(child: empty);
        }
        if (_groupByLaunchContext) {
          return _GroupedList(
            automations: automations,
            listScope: widget.listScope,
            runsByAutomationId: state.runsByAutomationId,
            onToggleEnabled: _toggleEnabled,
            onShowRunHistory: _showRunHistory,
            onEdit: _edit,
            onDelete: _delete,
            onRunNow: _runNow,
            formatNextRun: (ms) => _formatNextRun(l10n, ms),
            shrinkWrap: widget.shrinkWrap,
          );
        }
        return _FlatList(
          automations: automations,
          runsByAutomationId: state.runsByAutomationId,
          onToggleEnabled: _toggleEnabled,
          onShowRunHistory: _showRunHistory,
          onEdit: _edit,
          onDelete: _delete,
          onRunNow: _runNow,
          formatNextRun: (ms) => _formatNextRun(l10n, ms),
          shrinkWrap: widget.shrinkWrap,
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

class _FlatList extends StatelessWidget {
  const _FlatList({
    required this.automations,
    required this.runsByAutomationId,
    required this.onToggleEnabled,
    required this.onShowRunHistory,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    required this.formatNextRun,
    this.shrinkWrap = false,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final Future<void> Function(Automation) onToggleEnabled;
  final void Function(Automation, List<AutomationRun>) onShowRunHistory;
  final Future<void> Function(Automation) onEdit;
  final Future<void> Function(Automation) onDelete;
  final Future<void> Function(Automation) onRunNow;
  final String Function(int?) formatNextRun;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LaunchProfileCubit, LaunchProfileState>(
      builder: (context, profileState) {
        return BlocBuilder<CliPresetsCubit, CliPresetsState>(
          builder: (context, presetState) {
            final l10n = context.l10n;
            return ListView.builder(
              shrinkWrap: shrinkWrap,
              physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              itemCount: automations.length,
              itemBuilder: (context, index) {
                final automation = automations[index];
                final runs = List<AutomationRun>.of(
                  runsByAutomationId[automation.id] ?? const [],
                )..sort((x, y) => y.scheduledForMs.compareTo(x.scheduledForMs));
                return AutomationRow(
                  automation: automation,
                  scopeSubtitle: automationScopeSubtitle(
                    l10n,
                    automation: automation,
                    profiles: profileState,
                    presets: presetState,
                  ),
                  scheduleSummary: localizedScheduleSummary(
                    l10n,
                    scheduleDraftFromAutomation(automation),
                  ),
                  runCountLabel: formatAutomationRunCountLabel(
                    l10n,
                    automation,
                  ),
                  nextRunLabel: formatNextRun(automation.nextRunAtMs),
                  onToggleEnabled: () => unawaited(onToggleEnabled(automation)),
                  onShowRunHistory: () => onShowRunHistory(automation, runs),
                  onEdit: () => unawaited(onEdit(automation)),
                  onDelete: () => unawaited(onDelete(automation)),
                  onRunNow: () => unawaited(onRunNow(automation)),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.automations,
    required this.listScope,
    required this.runsByAutomationId,
    required this.onToggleEnabled,
    required this.onShowRunHistory,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    required this.formatNextRun,
    this.shrinkWrap = false,
  });

  final List<Automation> automations;
  final AutomationListScope? listScope;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final Future<void> Function(Automation) onToggleEnabled;
  final void Function(Automation, List<AutomationRun>) onShowRunHistory;
  final Future<void> Function(Automation) onEdit;
  final Future<void> Function(Automation) onDelete;
  final Future<void> Function(Automation) onRunNow;
  final String Function(int?) formatNextRun;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (prev, next) => !identical(prev.workspaces, next.workspaces),
      builder: (context, chatState) {
        return BlocBuilder<LaunchProfileCubit, LaunchProfileState>(
          builder: (context, profileState) {
            return BlocBuilder<CliPresetsCubit, CliPresetsState>(
              builder: (context, presetState) {
                final groups = _groupAutomations(
                  automations,
                  listScope: listScope,
                  workspaces: chatState.workspaces,
                  profiles: profileState,
                  l10n: l10n,
                );
                return ListView(
                  shrinkWrap: shrinkWrap,
                  physics: shrinkWrap
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  children: [
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                        child: Text(
                          group.label,
                          style: styles.smSemiboldColored(cs.onSurfaceVariant),
                        ),
                      ),
                      ...group.automations.map((automation) {
                        final runs =
                            List<AutomationRun>.of(
                              runsByAutomationId[automation.id] ?? const [],
                            )..sort(
                              (x, y) =>
                                  y.scheduledForMs.compareTo(x.scheduledForMs),
                            );
                        return AutomationRow(
                          automation: automation,
                          scopeSubtitle: automationScopeSubtitle(
                            l10n,
                            automation: automation,
                            profiles: profileState,
                            presets: presetState,
                          ),
                          scheduleSummary: localizedScheduleSummary(
                            l10n,
                            scheduleDraftFromAutomation(automation),
                          ),
                          runCountLabel: formatAutomationRunCountLabel(
                            l10n,
                            automation,
                          ),
                          nextRunLabel: formatNextRun(automation.nextRunAtMs),
                          onToggleEnabled: () =>
                              unawaited(onToggleEnabled(automation)),
                          onShowRunHistory: () =>
                              onShowRunHistory(automation, runs),
                          onEdit: () => unawaited(onEdit(automation)),
                          onDelete: () => unawaited(onDelete(automation)),
                          onRunNow: () => unawaited(onRunNow(automation)),
                        );
                      }),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AutomationGroup {
  const _AutomationGroup({required this.label, required this.automations});

  final String label;
  final List<Automation> automations;
}

List<_AutomationGroup> _groupAutomations(
  List<Automation> automations, {
  required AutomationListScope? listScope,
  required List<Workspace> workspaces,
  required LaunchProfileState profiles,
  required AppLocalizations l10n,
}) {
  final includeWorkspaceName = listScope == null || listScope.isAll;
  final grouped = <String, List<Automation>>{};
  for (final automation in automations) {
    final contextKey = automation.isPersonal
        ? 'personal'
        : (automation.teamId?.trim() ?? '');
    final key = includeWorkspaceName
        ? '${automation.workspaceId}\x1f$contextKey'
        : contextKey;
    grouped.putIfAbsent(key, () => []).add(automation);
  }

  final groups = grouped.entries.map((entry) {
    final automation = entry.value.first;
    final profileLabel = automationLaunchContextGroupLabel(
      l10n,
      automation: automation,
      profiles: profiles,
    );
    final workspace = workspaces
        .where((w) => w.workspaceId == automation.workspaceId)
        .firstOrNull;
    final label = includeWorkspaceName && workspace != null
        ? '${workspace.localizedName(l10n)} · $profileLabel'
        : profileLabel;
    return _AutomationGroup(label: label, automations: entry.value);
  }).toList();

  groups.sort((a, b) => a.label.compareTo(b.label));
  return groups;
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
    this.scopeSubtitle,
    super.key,
  });

  final Automation automation;
  final String? scopeSubtitle;
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
    final styles = TpTextStyles.of(context);
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
            Icon(actionIcon, size: context.tpIconSizes.md, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    automation.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.lg,
                  ),
                  if (scopeSubtitle != null && scopeSubtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      scopeSubtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.xsMediumColored(cs.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    scheduleSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.xsColored(cs.onSurfaceVariant),
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
                      style: styles.xsColored(cs.onSurfaceVariant),
                    ),
                  ],
                  if (runCountLabel.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      runCountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.xsColored(cs.onSurfaceVariant),
                    ),
                  ],
                  if (automation.enabled) ...[
                    const SizedBox(height: 2),
                    Text(
                      nextRunLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.xsColored(
                        cs.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            TpIconButton(
              icon: Icons.history_rounded,
              compact: true,
              size: TpIconButton.kCompactSize,
              tooltip: l10n.automationsRunHistory,
              onTap: onShowRunHistory,
            ),
            Switch(
              value: automation.enabled,
              onChanged: automation.isRunLimitReached
                  ? null
                  : (_) => onToggleEnabled(),
            ),
            TpActionMenuIconAnchor(
              icon: Icon(Icons.more_vert, size: context.tpIconSizes.md),
              buildMenuChildren: (ctx, controller) => [
                TpActionMenuItem(
                  icon: Icons.edit_outlined,
                  label: l10n.automationsEdit,
                  menuController: controller,
                  onTap: onEdit,
                ),
                TpActionMenuItem(
                  icon: Icons.play_circle_outline,
                  label: l10n.automationsRunNow,
                  menuController: controller,
                  enabled: !automation.isRunLimitReached,
                  onTap: onRunNow,
                ),
                TpActionMenuItem(
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
  final styles = TpTextStyles.of(context);
  final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

  return showDialog<void>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      maxHeight: maxHeight,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.automationsRunHistory),
          const SizedBox(height: 8),
          if (runs.isEmpty)
            Text(
              l10n.automationsRunHistoryEmpty,
              style: styles.xsColored(cs.onSurfaceVariant),
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
    final styles = TpTextStyles.of(context);
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
                style: styles.lg,
              ),
            ),
            const SizedBox(width: 12),
            Text(label, style: styles.smSemiboldColored(statusColor)),
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
