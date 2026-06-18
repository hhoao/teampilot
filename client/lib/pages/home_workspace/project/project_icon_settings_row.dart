import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../repositories/session_repository.dart';
import '../../../widgets/project_icon.dart';

class ProjectIconSettingsRow extends StatelessWidget {
  const ProjectIconSettingsRow({
    required this.project,
    this.showDividerBelow = true,
    super.key,
  });

  final Workspace project;
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
                  l10n.projectIcon,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ProjectIcon.fromProject(
                project,
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
    final error = await context.read<ChatCubit>().editProjectIcon(
      context,
      context.read<SessionRepository>(),
      project,
    );
    if (error == null || !context.mounted) return;
    AppToast.show(context, message: error, variant: AppToastVariant.error);
  }
}
