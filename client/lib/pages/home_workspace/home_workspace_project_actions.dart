import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/team_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_project.dart';
import '../../repositories/session_repository.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/project_display_name.dart';
import '../../widgets/app_dialog.dart';

/// Whether [location] is the workbench route for [projectId].
bool isViewingProjectRoute(String location, String projectId) {
  final segments = Uri.parse(location).pathSegments;
  return segments.length >= 3 &&
      segments[0] == 'home-v2' &&
      segments[1] == 'project' &&
      segments[2] == projectId;
}

/// Closes a delete confirmation dialog and navigates away from a deleted
/// project without [Navigator.pop], which can empty GoRouter's stack when the
/// widget that opened the dialog unmounts during the async delete.
void completeProjectDeleteNavigation(
  GoRouter router, {
  required String deletedProjectId,
  required String currentLocation,
}) {
  if (isViewingProjectRoute(currentLocation, deletedProjectId)) {
    router.go('/home-v2');
    return;
  }
  router.go(currentLocation);
}

Future<void> showRenameHomeWorkspaceProjectDialog(
  BuildContext context,
  AppProject project,
) async {
  final l10n = context.l10n;
  final controller = TextEditingController(text: project.display);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(
            title: l10n.homeWorkspaceRenameProject,
            onClose: () => Navigator.of(ctx).pop(false),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: project.localizedName(l10n)),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  final display = controller.text;
  controller.dispose();
  if (saved != true || !context.mounted) return;
  final repo = context.read<SessionRepository>();
  await context.read<ChatCubit>().updateProjectMetadata(
    repo,
    project.projectId,
    display: display,
  );
}

Future<void> cloneHomeWorkspaceProject(
  BuildContext context,
  AppProject project,
) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final team = context.read<TeamCubit>().state.selectedTeam;
  final baseName = project.localizedName(l10n);
  final display = l10n.homeWorkspaceCloneProjectDisplayName(baseName);

  try {
    final cloned = await context.read<ChatCubit>().cloneProject(
      repo,
      project.projectId,
      display: display,
      rosterMembers: team?.members ?? const [],
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: l10n.homeWorkspaceCloneProjectSuccess(baseName),
      variant: AppToastVariant.success,
    );
    context.go('/home-v2/project/${cloned.projectId}');
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceCloneProjectFailed}: $error',
      variant: AppToastVariant.error,
    );
  }
}

Future<void> confirmDeleteHomeWorkspaceProject(
  BuildContext context,
  AppProject project,
) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final chatCubit = context.read<ChatCubit>();
  final name = project.localizedName(l10n);
  final router = GoRouter.of(context);
  final currentLocation = GoRouterState.of(context).uri.toString();
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AppDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: l10n.deleteProject),
          const SizedBox(height: 16),
          Text(l10n.deleteProjectConfirm(name)),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: throttledAsync(
                  'home_workspace_card_delete_project',
                  () async {
                    await chatCubit.deleteProject(
                      repo,
                      project.projectId,
                    );
                    completeProjectDeleteNavigation(
                      router,
                      deletedProjectId: project.projectId,
                      currentLocation: currentLocation,
                    );
                  },
                ),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
