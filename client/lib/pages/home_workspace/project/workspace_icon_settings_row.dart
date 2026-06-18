import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/workspace_icon.dart';

class WorkspaceIconSettingsRow extends StatelessWidget {
  const WorkspaceIconSettingsRow({
    required this.workspace,
    this.showDividerBelow = true,
    super.key,
  });

  final Workspace workspace;
  final bool showDividerBelow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 168,
                child: Text(
                  l10n.workspaceIcon,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              WorkspaceIcon.fromWorkspace(
                workspace,
                size: 48,
                borderRadius: 14,
                padding: 8,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => unawaited(_editIcon(context)),
                child: Text(l10n.edit),
              ),
            ],
          ),
        ),
        if (showDividerBelow)
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
    );
  }

  Future<void> _editIcon(BuildContext context) async {
    final error = await context.read<ChatCubit>().editWorkspaceIcon(
      context,
      context.read<SessionRepository>(),
      workspace,
    );
    if (error == null || !context.mounted) return;
    AppToast.show(context, message: error, variant: AppToastVariant.error);
  }
}
