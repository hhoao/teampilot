import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Chat bubble for a Claude Code `Workflow` tool call: a run metadata header
/// plus one tappable row per spawned agent. Tapping a row drills into the
/// existing sub-agent preview via [AiToolSubagentActions.onOpenSubagent].
class WorkflowCard extends StatelessWidget {
  const WorkflowCard({
    required this.part,
    this.attachment,
    super.key,
  });

  final AiToolCallPart part;
  final AiSubagentAttachment? attachment;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiTheme = AiMessageTheme.of(context);
    final triggerColor = aiTheme.resolveToolTrigger(cs);
    final spacing = context.tpSpacing;
    final styles = TpTextStyles.of(context);
    final radius = TpTheme.of(context).control.radius;
    final l10n = context.l10n;
    final actions = AiToolSubagentActions.of(context);

    final workflow = attachment?.workflow;
    final name = workflow?.workflowName?.trim() ?? '';
    final title = name.isEmpty ? 'Workflow' : name;
    final status = workflow?.status?.trim() ?? '';
    final summary = workflow?.summary?.trim() ?? '';
    final phases = workflow?.phases ?? const <String>[];
    final agents = workflow?.agents ?? const <SubagentWorkflowAgent>[];
    final duration = workflow?.duration;

    return Padding(
      padding: EdgeInsets.only(bottom: aiTheme.partSpacing),
      child: Material(
        key: AppKeys.workflowCard,
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: EdgeInsets.all(spacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_rounded,
                    size: 16,
                    color: triggerColor,
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.smColored(cs.onSurface),
                    ),
                  ),
                  if (status.isNotEmpty) ...[
                    SizedBox(width: spacing.sm),
                    _StatusPill(
                      status: status,
                      color: _statusColor(cs, status),
                      styles: styles,
                    ),
                  ],
                  if (workflow != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      l10n.workflowCardAgents(workflow.agentCount),
                      style: styles.xsColored(cs.onSurfaceVariant),
                    ),
                    if (duration != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(duration),
                        style: styles.xsColored(cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ],
              ),
              if (phases.isNotEmpty) ...[
                SizedBox(height: spacing.xs),
                Wrap(
                  spacing: spacing.xs,
                  runSpacing: spacing.xs,
                  children: [
                    for (final phase in phases)
                      _PhaseChip(phase: phase, cs: cs, styles: styles),
                  ],
                ),
              ],
              if (summary.isNotEmpty) ...[
                SizedBox(height: spacing.xs),
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: styles.xsColored(cs.onSurfaceVariant),
                ),
              ],
              SizedBox(height: spacing.xs),
              if (workflow == null || agents.isEmpty)
                Text(
                  l10n.workflowCardRunMissing,
                  style: styles.xsColored(cs.onSurfaceVariant),
                )
              else
                for (final agent in agents)
                  _AgentRow(
                    agent: agent,
                    runId: workflow.runId,
                    spacing: spacing,
                    styles: styles,
                    onTap: actions.onOpenSubagent == null
                        ? null
                        : () {
                            actions.onOpenSubagent?.call(
                              subagentWorkflowChildToolCallId(
                                workflow.runId,
                                agent.agentId,
                              ),
                            );
                          },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({
    required this.agent,
    required this.runId,
    required this.spacing,
    required this.styles,
    required this.onTap,
  });

  final SubagentWorkflowAgent agent;
  final String runId;
  final TpSpacing spacing;
  final TpTextStyles styles;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = agent.role?.trim() ?? '';
    final label = role.isEmpty ? agent.agentId : role;
    final status = agent.status?.trim() ?? '';
    return TpHover(
      key: AppKeys.workflowAgentRow(runId, agent.agentId),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.xs,
          vertical: spacing.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurfaceVariant),
            SizedBox(width: spacing.xs),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.smColored(cs.onSurface),
              ),
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(width: 6),
              _StatusPill(
                status: status,
                color: _statusColor(cs, status),
                styles: styles,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({
    required this.phase,
    required this.cs,
    required this.styles,
  });

  final String phase;
  final ColorScheme cs;
  final TpTextStyles styles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        phase,
        style: styles.xsColored(cs.onSurfaceVariant),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.color,
    required this.styles,
  });

  final String status;
  final Color color;
  final TpTextStyles styles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: styles.xsColored(color),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = d.inMinutes;
  final remaining = seconds - minutes * 60;
  if (minutes < 60) return remaining == 0 ? '${minutes}m' : '${minutes}m ${remaining}s';
  final hours = d.inHours;
  return '${hours}h ${minutes - hours * 60}m';
}

Color _statusColor(ColorScheme cs, String status) {
  final normalized = status
      .replaceAll(RegExp(r'[^a-zA-Z]'), '')
      .toLowerCase();
  if (normalized == 'done' || normalized == 'approved') return cs.tertiary;
  if (normalized == 'running' ||
      normalized == 'inprogress' ||
      normalized == 'pending') {
    return cs.primary;
  }
  if (normalized == 'failed' ||
      normalized == 'cancelled' ||
      normalized == 'canceled' ||
      normalized == 'blocked' ||
      normalized == 'error') {
    return cs.error;
  }
  return cs.onSurfaceVariant;
}
