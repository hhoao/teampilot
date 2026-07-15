import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../utils/workspace_display_name.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../widgets/workspace_icon.dart';

/// Picks an open workspace to launch an Expert Hub member into. Returns the
/// selected [workspaceId], or `null` when dismissed.
Future<String?> showExpertWorkspacePickerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => const ExpertWorkspacePickerDialog(),
  );
}

class ExpertWorkspacePickerDialog extends StatelessWidget {
  const ExpertWorkspacePickerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final workspaces = context.select<ChatCubit, List<Workspace>>(
      (c) => c.state.workspaces,
    );

    return TpDialog(
      maxWidth: 480,
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      scrollable: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.expertHubLaunchInWorkspace),
          const SizedBox(height: 8),
          for (final workspace in workspaces)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: WorkspaceIcon(
                workspace: workspace,
                size: 36,
                borderRadius: 10,
                padding: 6,
              ),
              title: Text(
                workspace.localizedName(l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.of(context).pop(workspace.workspaceId),
            ),
        ],
      ),
    );
  }
}
