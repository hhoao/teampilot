import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_toast_theme.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/identity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/workspace_display_name.dart';
import '../../widgets/app_dialog.dart';

/// Whether [location] is the workbench route for [workspaceId].
bool isViewingWorkspaceRoute(String location, String workspaceId) {
  final segments = Uri.parse(location).pathSegments;
  return segments.length >= 3 &&
      segments[0] == 'home-v2' &&
      segments[1] == 'workspace' &&
      segments[2] == workspaceId;
}

/// Navigates away from a deleted workspace when the workbench route is active.
/// Call after the delete confirmation dialog has been closed.
void completeWorkspaceDeleteNavigation(
  GoRouter router, {
  required String deletedWorkspaceId,
  required String currentLocation,
}) {
  if (isViewingWorkspaceRoute(currentLocation, deletedWorkspaceId)) {
    router.go('/home-v2');
    return;
  }
  router.go(currentLocation);
}

Future<void> showRenameWorkspaceDialog(
  BuildContext context,
  Workspace workspace, {
  String? title,
}) async {
  final l10n = context.l10n;
  final display = await showAppTextPromptDialog(
    context,
    title: title ?? l10n.homeWorkspaceRenameWorkspace,
    initialText: workspace.display,
    hintText: workspace.localizedName(l10n),
    confirmLabel: l10n.save,
  );
  if (display == null || !context.mounted) return;
  final repo = context.read<SessionRepository>();
  await context.read<ChatCubit>().updateWorkspaceMetadata(
    repo,
    workspace.workspaceId,
    display: display,
  );
}

Future<void> cloneWorkspace(
  BuildContext context,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final team = context.read<IdentityCubit>().state.selectedTeam;
  final baseName = workspace.localizedName(l10n);
  final display = l10n.homeWorkspaceCloneWorkspaceDisplayName(baseName);

  try {
    final cloned = await context.read<ChatCubit>().cloneWorkspace(
      repo,
      workspace.workspaceId,
      display: display,
      rosterMembers: team?.members ?? const [],
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: l10n.homeWorkspaceCloneWorkspaceSuccess(baseName),
      variant: AppToastVariant.success,
    );
    context.go('/home-v2/workspace/${cloned.workspaceId}');
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceCloneWorkspaceFailed}: $error',
      variant: AppToastVariant.error,
    );
  }
}

Future<void> confirmDeleteWorkspace(
  BuildContext context,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final chatCubit = context.read<ChatCubit>();
  final name = workspace.localizedName(l10n);
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
          AppDialogHeader(title: l10n.deleteWorkspace),
          const SizedBox(height: 16),
          Text(l10n.deleteWorkspaceConfirm(name)),
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
                  'home_workspace_card_delete_workspace',
                  () async {
                    await chatCubit.deleteWorkspace(
                      repo,
                      workspace.workspaceId,
                    );
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                    completeWorkspaceDeleteNavigation(
                      router,
                      deletedWorkspaceId: workspace.workspaceId,
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
