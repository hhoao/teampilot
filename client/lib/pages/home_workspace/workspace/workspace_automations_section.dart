import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/automation_cubit.dart';
import '../../../cubits/automation_state.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/automation_list_scope.dart';
import '../../../models/workspace.dart';
import '../../../pages/automations/automation_editor_dialog.dart';
import '../../../pages/automations/automations_dialog.dart';
import '../../../services/automation/automation_workspace_summary.dart';

/// Workspace sidebar entry for automations — opens the merged workspace panel.
class WorkspaceAutomationsSection extends StatefulWidget {
  const WorkspaceAutomationsSection({required this.workspace, super.key});

  final Workspace workspace;

  @override
  State<WorkspaceAutomationsSection> createState() =>
      _WorkspaceAutomationsSectionState();
}

class _WorkspaceAutomationsSectionState
    extends State<WorkspaceAutomationsSection> {
  String? _loadedWorkspaceId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant WorkspaceAutomationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.workspaceId != widget.workspace.workspaceId) {
      _loadedWorkspaceId = null;
      _ensureLoaded();
    }
  }

  void _ensureLoaded() {
    final workspaceId = widget.workspace.workspaceId;
    if (_loadedWorkspaceId == workspaceId) return;
    _loadedWorkspaceId = workspaceId;
    unawaited(
      context.read<AutomationCubit>().loadForWorkspace(workspaceId),
    );
  }

  Future<void> _openPanel({bool create = false}) async {
    final workspaceId = widget.workspace.workspaceId;
    if (create) {
      final saved = await AutomationEditorDialog.show(
        context,
        workspaceId: workspaceId,
      );
      if (saved == null || !mounted) return;
      await context.read<AutomationCubit>().loadForWorkspace(workspaceId);
    }
    if (!mounted) return;
    await showAutomationsPanelDialog(
      context,
      listScope: AutomationListScope.workspace(workspaceId),
    );
    if (!mounted) return;
    await context.read<AutomationCubit>().loadForWorkspace(workspaceId);
  }

  @override
  Widget build(BuildContext context) {
    final workspaceId = widget.workspace.workspaceId;

    return BlocBuilder<AutomationCubit, AutomationState>(
      builder: (context, state) {
        final summary = AutomationWorkspaceSummary.fromAutomations(
          state.automations,
          workspaceId,
        );
        return _SectionHeader(
          enabledCount: summary.enabledCount,
          nearestNextRunAtMs: summary.nearestNextRunAtMs,
          onOpenPanel: () => unawaited(_openPanel()),
          onAdd: () => unawaited(_openPanel(create: true)),
        );
      },
    );
  }
}

class _SectionHeader extends StatefulWidget {
  const _SectionHeader({
    required this.enabledCount,
    required this.nearestNextRunAtMs,
    required this.onOpenPanel,
    required this.onAdd,
  });

  final int enabledCount;
  final int? nearestNextRunAtMs;
  final VoidCallback onOpenPanel;
  final VoidCallback onAdd;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final subtitle = _subtitle(l10n);
    final hoverTint = cs.onSurface.withValues(alpha: 0.05);

    return TpHover(
      onTap: widget.onOpenPanel,
      hoverColor: hoverTint,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.bolt_rounded,
              size: context.tpIconSizes.md,
              color: cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: styles.lg,
                  children: [
                    TextSpan(
                      text: widget.enabledCount > 0
                          ? l10n.automationsHeaderCount(widget.enabledCount)
                          : l10n.automationsSidebarTitle,
                    ),
                    if (subtitle != null)
                      TextSpan(
                        text: ' · $subtitle',
                        style: styles.lgColored(cs.onSurfaceVariant,),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TpIconButton(
              icon: Icons.add_rounded,
              compact: true,
              size: TpIconButton.kCompactSize,
              tooltip: l10n.automationsNew,
              onTap: widget.onAdd,
            ),
          ],
        ),
      ),
    );
  }

  String? _subtitle(AppLocalizations l10n) {
    final next = widget.nearestNextRunAtMs;
    if (next == null) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(next);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
