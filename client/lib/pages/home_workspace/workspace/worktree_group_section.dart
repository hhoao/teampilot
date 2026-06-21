import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/session_worktree_grouping.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_toast/app_toast.dart';
import '../../../theme/app_toast_theme.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'worktree_delete_dialog.dart';
import 'workspace_session_actions.dart';

/// Collapse-set key for a group: the worktree path, or a sentinel for the
/// orphan group (which has no path). Kept in one place so the sidebar and the
/// section agree on the key.
String worktreeGroupCollapseKey(WorktreeGroup group) =>
    group.worktree?.path ?? '<orphan>';

/// One collapsible worktree group in [WorkspaceSidebar]: a branch header (with
/// management menu) plus its session tiles. Selecting the header makes the
/// worktree the workspace's current one; the caret toggles collapse.
class WorktreeGroupSection extends StatelessWidget {
  const WorktreeGroupSection({
    required this.group,
    required this.workspace,
    required this.isPersonal,
    required this.profileId,
    required this.sessionTeamFilter,
    required this.collapsed,
    required this.isCurrent,
    super.key,
  });

  final WorktreeGroup group;
  final Workspace workspace;
  final bool isPersonal;
  final String profileId;
  final String sessionTeamFilter;
  final bool collapsed;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final wt = group.worktree;
    final label = wt == null ? l10n.worktreeOrphanGroup : wt.shortBranch;
    // Only linked (non-main, non-orphan) worktrees can be removed and started in.
    final manageable = wt != null && !wt.isMainWorktree;
    final selectable = wt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isCurrent
              ? cs.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: selectable
                ? () =>
                    context.read<WorktreeCubit>().setCurrentWorktree(wt.path)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  AppIconButton(
                    icon: collapsed
                        ? Icons.chevron_right_rounded
                        : Icons.expand_more_rounded,
                    compact: true,
                    size: AppIconButton.kCompactSize,
                    tooltip: null,
                    onTap: () => context
                        .read<WorktreeCubit>()
                        .toggleCollapsed(worktreeGroupCollapseKey(group)),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.prominent.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${group.sessions.length}',
                    style: styles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  if (wt != null)
                    _GroupMenu(
                      worktreePath: wt.path,
                      manageable: manageable,
                      onNewConversation: () {
                        context
                            .read<WorktreeCubit>()
                            .setCurrentWorktree(wt.path);
                        unawaited(
                          createSessionInWorktree(
                            context,
                            workspace,
                            isPersonal: isPersonal,
                            worktreePath: wt.path,
                            sessionTeamId: sessionTeamFilter,
                            personalIdentityId: profileId,
                          ),
                        );
                      },
                      onDelete: () => unawaited(
                        _confirmAndRemove(context, wt.path, label),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          ...group.sessions.map(
            (session) => SidebarSessionTile(
              key: ValueKey('worktree-session-${session.sessionId}'),
              session: session,
              contentLeftInset: 18,
              tapThrottleKeyPrefix: 'worktree_sidebar_session',
              onTap: () {
                // Selecting a session makes its worktree the current one so the
                // terminal, file tree and source control all reflect it (§7).
                if (wt != null) {
                  context.read<WorktreeCubit>().setCurrentWorktree(wt.path);
                }
                unawaited(
                  openWorkspaceSessionTab(
                    context,
                    workspace,
                    session,
                    isPersonal: isPersonal,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAndRemove(
    BuildContext context,
    String worktreePath,
    String branchLabel,
  ) async {
    final chatCubit = context.read<ChatCubit>();
    final repo = context.read<SessionRepository>();
    final cubit = context.read<WorktreeCubit>();
    final l10n = context.l10n;
    final result = await showWorktreeDeleteDialog(
      context,
      branchLabel: branchLabel,
      sessionCount: group.sessions.length,
    );
    if (result == null) return;
    try {
      final wt = group.worktree;
      await GitWorktreeService().remove(
        cubit.state.repoPath,
        worktreePath,
        force: result.force,
        deleteBranch:
            result.deleteBranch ? wt?.shortBranch : null,
      );
      if (result.deleteSessions) {
        for (final session in group.sessions) {
          await chatCubit.deleteSession(repo, session.sessionId);
        }
      }
      await cubit.load(cubit.state.repoPath);
    } on Object catch (error) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        message: l10n.worktreeDeleteFailed(error.toString()),
        variant: AppToastVariant.error,
      );
    }
  }
}

class _GroupMenu extends StatelessWidget {
  const _GroupMenu({
    required this.worktreePath,
    required this.manageable,
    required this.onNewConversation,
    required this.onDelete,
  });

  final String worktreePath;
  final bool manageable;
  final VoidCallback onNewConversation;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      size: AppIconButton.kCompactSize,
      triggerBuilder: (context, controller) => AppIconButton(
        icon: Icons.more_horiz_rounded,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: null,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      buildMenuChildren: (context, controller) => [
        SidebarActionMenuItem(
          icon: Icons.edit_outlined,
          label: l10n.worktreeNewConversationHere,
          menuController: controller,
          onTap: onNewConversation,
        ),
        SidebarActionMenuItem(
          icon: Icons.copy_rounded,
          label: l10n.worktreeMenuCopyPath,
          menuController: controller,
          onTap: () => Clipboard.setData(ClipboardData(text: worktreePath)),
        ),
        if (manageable)
          SidebarActionMenuItem(
            icon: Icons.delete_outline_rounded,
            label: l10n.worktreeMenuRemove,
            menuController: controller,
            onTap: onDelete,
          ),
      ],
    );
  }
}
