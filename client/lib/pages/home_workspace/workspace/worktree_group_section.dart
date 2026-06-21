import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/worktree_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../repositories/session_repository.dart';
import '../../../services/git/git_worktree_service.dart';
import '../../../services/git/worktree_removal.dart';
import '../../../services/storage/runtime_storage_context.dart';
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

/// Worktree create/remove run local `git`, so management is desktop-local only
/// (v1). Native and WSL backends can spawn local git; SSH/Android hide controls.
bool worktreeManagementEnabled() =>
    RuntimeStorageContext.isInstalled &&
    (RuntimeStorageContext.current.mode == StorageBackendMode.native ||
        RuntimeStorageContext.current.mode == StorageBackendMode.wsl);

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
    this.worktreeService,
    super.key,
  });

  final WorktreeGroup group;
  final Workspace workspace;
  final bool isPersonal;
  final String profileId;
  final String sessionTeamFilter;
  final bool collapsed;
  final bool isCurrent;

  /// Injectable for tests; defaults to [GitWorktreeService.resolve].
  final GitWorktreeService? worktreeService;

  GitWorktreeService get _service =>
      worktreeService ?? GitWorktreeService.resolve();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final wt = group.worktree;
    final label = wt == null ? l10n.worktreeOrphanGroup : wt.shortBranch;
    // Only linked (non-main, non-orphan) worktrees can be removed, and only on
    // desktop-local backends where local `git worktree remove` is meaningful.
    final manageable =
        wt != null && !wt.isMainWorktree && worktreeManagementEnabled();
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
                ? () => unawaited(
                      activateWorktreeGroup(
                        context,
                        workspace,
                        isPersonal: isPersonal,
                        worktreePath: wt.path,
                        groupSessions: group.sessions,
                      ),
                    )
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
        if (!collapsed && group.sessions.isNotEmpty)
          _GroupSessionList(
            key: ValueKey('wt-sessions-${worktreeGroupCollapseKey(group)}'),
            sessions: group.sessions,
            workspace: workspace,
            isPersonal: isPersonal,
          ),
        if (!collapsed && group.sessions.isEmpty && wt != null)
          _EmptyGroupCta(
            onTap: () {
              context.read<WorktreeCubit>().setCurrentWorktree(wt.path);
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
    // A running agent's cwd would vanish under it — make the user stop first.
    final working = chatCubit.state.workingSessionIds;
    final hasBusy =
        group.sessions.any((s) => working.contains(s.sessionId));
    if (hasBusy) {
      AppToast.show(
        context,
        message: l10n.worktreeDeleteBusyWarning,
        variant: AppToastVariant.error,
      );
      return;
    }
    final dirty = await _service.isDirty(worktreePath);
    if (!context.mounted) return;
    final result = await showWorktreeDeleteDialog(
      context,
      branchLabel: branchLabel,
      sessionCount: group.sessions.length,
      requireForce: dirty,
    );
    if (result == null) return;
    try {
      await removeWorktreeWithSessions(
        service: _service,
        repoPath: cubit.state.repoPath,
        worktreePath: worktreePath,
        worktree: group.worktree,
        options: WorktreeDeleteOptions(
          force: result.force,
          deleteBranch: result.deleteBranch,
          deleteSessions: result.deleteSessions,
        ),
        sessionsInGroup: group.sessions,
        deleteSession: (id) => chatCubit.deleteSession(repo, id),
      );
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

class _EmptyGroupCta extends StatelessWidget {
  const _EmptyGroupCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 8, 8),
        child: Row(
          children: [
            Icon(Icons.add_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.worktreeNewConversationHere,
                style: AppTextStyles.of(context).bodySmall.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

/// Session tiles for one worktree group, capped at [_cap] with a "show
/// more / show less" toggle so a busy worktree doesn't flood the sidebar.
class _GroupSessionList extends StatefulWidget {
  const _GroupSessionList({
    required this.sessions,
    required this.workspace,
    required this.isPersonal,
    super.key,
  });

  final List<AppSession> sessions;
  final Workspace workspace;
  final bool isPersonal;

  @override
  State<_GroupSessionList> createState() => _GroupSessionListState();
}

class _GroupSessionListState extends State<_GroupSessionList> {
  static const _cap = 5;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final all = widget.sessions;
    final overflow = all.length - _cap;
    final visible = (_showAll || overflow <= 0) ? all : all.take(_cap).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final session in visible)
          SidebarSessionTile(
            key: ValueKey('worktree-session-${session.sessionId}'),
            session: session,
            contentLeftInset: 18,
            tapThrottleKeyPrefix: 'worktree_sidebar_session',
            onTap: () => unawaited(
              openWorkspaceSessionTab(
                context,
                widget.workspace,
                session,
                isPersonal: widget.isPersonal,
              ),
            ),
          ),
        if (overflow > 0)
          InkWell(
            onTap: () => setState(() => _showAll = !_showAll),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 8, 6),
              child: Text(
                _showAll ? l10n.worktreeShowLess : l10n.worktreeShowMore(overflow),
                style: AppTextStyles.of(context).bodySmall.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
