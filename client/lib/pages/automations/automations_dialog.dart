import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/automation_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation_tab_scope.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'automation_editor_dialog.dart';
import 'automation_sort.dart';
import 'automations_list_body.dart';

/// Workspace-scoped automations list in a modal dialog.
class AutomationsDialog extends StatefulWidget {
  const AutomationsDialog({
    required this.filterTabScope,
    this.filterSessionId,
    super.key,
  });

  final AutomationTabScope filterTabScope;
  final String? filterSessionId;

  @override
  State<AutomationsDialog> createState() => _AutomationsDialogState();
}

class _AutomationsDialogState extends State<AutomationsDialog> {
  AutomationEnabledFilter _enabledFilter = AutomationEnabledFilter.all;

  Future<void> _create() async {
    final saved = await AutomationEditorDialog.show(
      context,
      launchProfileId: widget.filterTabScope.launchProfileId,
      workspaceId: widget.filterTabScope.workspaceId,
      sessionId: widget.filterSessionId,
    );
    if (saved != null && mounted) {
      await context.read<AutomationCubit>().loadForTabScope(
        widget.filterTabScope,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return AppDialog(
      maxWidth: 720,
      maxHeight: maxHeight,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: l10n.automationsTitle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 132,
                  child: AppDropdownField<AutomationEnabledFilter>(
                    items: const [
                      AutomationEnabledFilter.all,
                      AutomationEnabledFilter.enabledOnly,
                    ],
                    initialItem: _enabledFilter,
                    decoration: AppDropdownDecorations.themed(context),
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
                AppIconButton(
                  icon: Icons.add_rounded,
                  tooltip: l10n.automationsNew,
                  onTap: () => unawaited(_create()),
                ),
              ],
            ),
          ),
          Flexible(
            child: AutomationsListBody(
              filterTabScope: widget.filterTabScope,
              filterSessionId: widget.filterSessionId,
              enabledFilter: _enabledFilter,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [AutomationsDialog] from the workspace sidebar or session menu.
Future<void> showAutomationsPanelDialog(
  BuildContext context, {
  required AutomationTabScope filterTabScope,
  String? filterSessionId,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AutomationsDialog(
      filterTabScope: filterTabScope,
      filterSessionId: filterSessionId,
    ),
  );
}
