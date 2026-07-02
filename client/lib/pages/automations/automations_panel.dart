import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/automation_state.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../repositories/automation_repository.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/coarse_relative_time.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/menu/sidebar_action_menu.dart';
import 'automation_editor_dialog.dart';
import 'automation_schedule_picker.dart';

enum _AutomationFilter { all, enabledOnly }

/// Shared automation list used by the global management page and workspace
/// sidebar entry points.
class AutomationsPanel extends StatefulWidget {
  const AutomationsPanel({
    this.filterWorkspaceId,
    this.filterSessionId,
    this.groupByWorkspace = false,
    this.embedded = false,
    super.key,
  });

  final String? filterWorkspaceId;
  final String? filterSessionId;
  final bool groupByWorkspace;
  final bool embedded;

  @override
  State<AutomationsPanel> createState() => _AutomationsPanelState();
}

class _AutomationsPanelState extends State<AutomationsPanel> {
  _AutomationFilter _filter = _AutomationFilter.all;
  final Set<String> _expandedIds = {};
  var _didLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    final cubit = context.read<AutomationCubit>();
    if (widget.filterWorkspaceId != null) {
      unawaited(cubit.loadForWorkspace(widget.filterWorkspaceId!));
    } else {
      unawaited(cubit.load());
    }
  }

  List<Automation> _filtered(List<Automation> automations) {
    Iterable<Automation> items = automations;
    if (widget.filterSessionId != null) {
      items = items.where((a) => a.sessionId == widget.filterSessionId);
    }
    if (_filter == _AutomationFilter.enabledOnly) {
      items = items.where((a) => a.enabled);
    }
    final sorted = items.toList();
    sorted.sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  Future<void> _reload() async {
    final cubit = context.read<AutomationCubit>();
    if (widget.filterWorkspaceId != null) {
      await cubit.loadForWorkspace(widget.filterWorkspaceId!);
    } else {
      await cubit.load();
    }
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
      automation.workspaceId,
      automation.id,
    );
  }

  Future<void> _edit(Automation automation) async {
    final saved = await AutomationEditorDialog.show(
      context,
      initial: automation,
      workspaceId: automation.workspaceId,
      sessionId: automation.sessionId,
    );
    if (saved != null) await _reload();
  }

  Future<void> _create() async {
    final saved = await AutomationEditorDialog.show(
      context,
      workspaceId: widget.filterWorkspaceId,
      sessionId: widget.filterSessionId,
    );
    if (saved != null) await _reload();
  }

  Future<void> _runNow(Automation automation) async {
    await context.read<AutomationCubit>().runNow(
      automation.workspaceId,
      automation.id,
    );
  }

  void _toggleExpanded(String automationId) {
    setState(() {
      if (_expandedIds.contains(automationId)) {
        _expandedIds.remove(automationId);
      } else {
        _expandedIds.add(automationId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.automationsTitle,
              style: styles.subtitle.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          DropdownButton<_AutomationFilter>(
            value: _filter,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: _AutomationFilter.all,
                child: Text(l10n.automationsFilterAll),
              ),
              DropdownMenuItem(
                value: _AutomationFilter.enabledOnly,
                child: Text(l10n.automationsFilterEnabled),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _filter = value);
            },
          ),
          AppIconButton(
            icon: Icons.add_rounded,
            tooltip: l10n.automationsNew,
            onTap: _create,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: BlocBuilder<AutomationCubit, AutomationState>(
            builder: (context, state) {
              if (state.status == AutomationLoadStatus.loading &&
                  state.automations.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final automations = _filtered(state.automations);
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
              if (widget.groupByWorkspace) {
                return _GroupedList(
                  automations: automations,
                  runsByAutomationId: state.runsByAutomationId,
                  expandedIds: _expandedIds,
                  onToggleEnabled: _toggleEnabled,
                  onToggleExpanded: _toggleExpanded,
                  onEdit: _edit,
                  onDelete: _delete,
                  onRunNow: _runNow,
                  formatNextRun: (ms) => _formatNextRun(l10n, ms),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: automations.length,
                itemBuilder: (context, index) {
                  final a = automations[index];
                  final runs = (state.runsByAutomationId[a.id] ?? const [])
                    ..sort((x, y) => y.scheduledForMs.compareTo(x.scheduledForMs));
                  return _AutomationRow(
                    automation: a,
                    expanded: _expandedIds.contains(a.id),
                    runs: runs.take(10).toList(growable: false),
                    scheduleSummary: localizedScheduleSummary(
                      l10n,
                      scheduleDraftFromAutomation(a),
                    ),
                    nextRunLabel: _formatNextRun(l10n, a.nextRunAtMs),
                    onToggleEnabled: () => unawaited(_toggleEnabled(a)),
                    onTap: () => _toggleExpanded(a.id),
                    onEdit: () => unawaited(_edit(a)),
                    onDelete: () => unawaited(_delete(a)),
                    onRunNow: () => unawaited(_runNow(a)),
                  );
                },
              );
            },
          ),
        ),
      ],
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
    required this.expandedIds,
    required this.onToggleEnabled,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
    required this.formatNextRun,
  });

  final List<Automation> automations;
  final Map<String, List<AutomationRun>> runsByAutomationId;
  final Set<String> expandedIds;
  final Future<void> Function(Automation) onToggleEnabled;
  final void Function(String) onToggleExpanded;
  final Future<void> Function(Automation) onEdit;
  final Future<void> Function(Automation) onDelete;
  final Future<void> Function(Automation) onRunNow;
  final String Function(int?) formatNextRun;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final grouped = <String, List<Automation>>{};
    for (final a in automations) {
      grouped.putIfAbsent(a.workspaceId, () => []).add(a);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
            child: Text(
              entry.key,
              style: styles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...entry.value.map((a) {
            final runs = (runsByAutomationId[a.id] ?? const [])
              ..sort((x, y) => y.scheduledForMs.compareTo(x.scheduledForMs));
            return _AutomationRow(
              automation: a,
              expanded: expandedIds.contains(a.id),
              runs: runs.take(10).toList(growable: false),
              scheduleSummary: localizedScheduleSummary(
                l10n,
                scheduleDraftFromAutomation(a),
              ),
              nextRunLabel: formatNextRun(a.nextRunAtMs),
              onToggleEnabled: () => unawaited(onToggleEnabled(a)),
              onTap: () => onToggleExpanded(a.id),
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

class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
    required this.automation,
    required this.expanded,
    required this.runs,
    required this.scheduleSummary,
    required this.nextRunLabel,
    required this.onToggleEnabled,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onRunNow,
  });

  final Automation automation;
  final bool expanded;
  final List<AutomationRun> runs;
  final String scheduleSummary;
  final String nextRunLabel;
  final VoidCallback onToggleEnabled;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRunNow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final actionIcon = automation.action == AutomationAction.sendToLead
        ? Icons.send_rounded
        : Icons.play_arrow_rounded;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Icon(
                    actionIcon,
                    size: context.appIconSizes.md,
                    color: cs.primary,
                  ),
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
                          style: styles.caption.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
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
                  Switch(
                    value: automation.enabled,
                    onChanged: (_) => onToggleEnabled(),
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
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.automationsRunHistory,
                    style: styles.bodySmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (runs.isEmpty)
                    Text(
                      l10n.automationsRunHistoryEmpty,
                      style: styles.caption.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    )
                  else
                    ...runs.map((run) => _RunHistoryRow(run: run)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RunHistoryRow extends StatelessWidget {
  const _RunHistoryRow({required this.run});

  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final when = DateTime.fromMillisecondsSinceEpoch(run.scheduledForMs);
    final label = _statusLabel(l10n, run.status);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatCoarseRelativeTime(l10n, when),
              style: styles.caption,
            ),
          ),
          Text(
            label,
            style: styles.caption.copyWith(
              color: _statusColor(cs, run.status),
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, AutomationRunStatus status) {
    return switch (status) {
      AutomationRunStatus.completed => l10n.automationsRunStatusCompleted,
      AutomationRunStatus.skippedUnavailable =>
        l10n.automationsSkippedUnavailable,
      AutomationRunStatus.skippedMissed => l10n.automationsRunStatusSkippedMissed,
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
      AutomationRunStatus.skippedMissed =>
        cs.onSurfaceVariant,
      AutomationRunStatus.dispatchFailed => cs.error,
      _ => cs.onSurface,
    };
  }
}

/// Opens [AutomationsPanel] in a modal dialog (workspace sidebar entry).
Future<void> showAutomationsPanelDialog(
  BuildContext context, {
  String? filterWorkspaceId,
  String? filterSessionId,
}) {
  final height = MediaQuery.sizeOf(context).height * 0.85;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AppDialog(
      maxWidth: 720,
      maxHeight: height,
      child: SizedBox(
        height: height - 48,
        child: AutomationsPanel(
          filterWorkspaceId: filterWorkspaceId,
          filterSessionId: filterSessionId,
          embedded: true,
        ),
      ),
    ),
  );
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
    String workspaceId,
  ) {
    final enabled = automations
        .where((a) => a.workspaceId == workspaceId && a.enabled)
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
    String workspaceId,
  ) async {
    final automations = await repo.listForWorkspace(workspaceId);
    return fromAutomations(automations, workspaceId);
  }
}
