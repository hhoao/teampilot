import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/automation_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation_list_scope.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import 'automation_editor_dialog.dart';
import 'automation_sort.dart';
import 'automations_list_body.dart';

/// Workspace-scoped automations list in a modal dialog.
class AutomationsDialog extends StatefulWidget {
  const AutomationsDialog({required this.listScope, super.key});

  final AutomationListScope listScope;

  @override
  State<AutomationsDialog> createState() => _AutomationsDialogState();
}

class _AutomationsDialogState extends State<AutomationsDialog> {
  AutomationEnabledFilter _enabledFilter = AutomationEnabledFilter.all;

  Future<void> _create() async {
    final scope = widget.listScope;
    final saved = await AutomationEditorDialog.show(
      context,
      workspaceId: scope.isWorkspace || scope.isSession ? scope.workspaceId : null,
      sessionId: scope.sessionId,
    );
    if (saved != null && mounted) {
      await _reload();
    }
  }

  Future<void> _reload() async {
    final cubit = context.read<AutomationCubit>();
    final scope = widget.listScope;
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
      return;
    }
    await cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hostPad = _pageHostPadding(context);

    return TpDialogPageShell(
      title: l10n.automationsTitle,
      mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
      fillBody: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 132,
            child: TpSelect<AutomationEnabledFilter>(
              items: const [
                AutomationEnabledFilter.all,
                AutomationEnabledFilter.enabledOnly,
              ],
              initialItem: _enabledFilter,
              decoration: TpSelectDecorations.themed(context),
              itemLabel: (f) => switch (f) {
                AutomationEnabledFilter.all => l10n.automationsFilterAll,
                AutomationEnabledFilter.enabledOnly =>
                  l10n.automationsFilterEnabled,
                AutomationEnabledFilter.disabledOnly =>
                  l10n.automationsFilterDisabled,
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() => _enabledFilter = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          TpIconButton(
            icon: Icons.add_rounded,
            tooltip: l10n.automationsNew,
            onTap: () => unawaited(_create()),
          ),
        ],
      ),
      child: Padding(
        padding: hostPad,
        child: AutomationsListBody(
          listScope: widget.listScope,
          enabledFilter: _enabledFilter,
          shrinkWrap: false,
        ),
      ),
    );
  }
}

EdgeInsets _pageHostPadding(BuildContext context) {
  final narrow =
      MediaQuery.sizeOf(context).width <
      WorkspacePanePolicy.narrowBreakpointWidth;
  return narrow ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : EdgeInsets.zero;
}

/// Opens [AutomationsDialog] from the workspace sidebar or session menu.
Future<void> showAutomationsPanelDialog(
  BuildContext context, {
  required AutomationListScope listScope,
}) {
  return showTpDialog<void>(
    context: context,
    presentation: TpDialogPresentation.page,
    mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
    maxWidth: 720,
    builder: (_) => AutomationsDialog(listScope: listScope),
  );
}
