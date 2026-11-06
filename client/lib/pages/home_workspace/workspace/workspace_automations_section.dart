import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/automation_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/automation_list_scope.dart';
import '../../../models/workspace.dart';
import '../../../pages/automations/automations_dialog.dart';

/// Workspace sidebar entry for scheduled tasks — opens the workspace panel.
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
    unawaited(context.read<AutomationCubit>().loadForWorkspace(workspaceId));
  }

  Future<void> _openPanel() async {
    final workspaceId = widget.workspace.workspaceId;
    await showAutomationsPanelDialog(
      context,
      listScope: AutomationListScope.workspace(workspaceId),
    );
    if (!mounted) return;
    await context.read<AutomationCubit>().loadForWorkspace(workspaceId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return TpHover(
      onTap: () => unawaited(_openPanel()),
      hoverColor: cs.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.alarm_rounded,
            size: context.tpIconSizes.md,
            color: cs.onSurface,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.automationsSidebarTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.lg,
            ),
          ),
        ],
      ),
    );
  }
}
