import 'dart:async';

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/team_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../repositories/session_repository.dart';
import '../../../theme/app_text_styles.dart';

/// The "Conversations" tree panel (renamed from Apifox's 接口管理). Lists the
/// sessions that belong to [project] and opens the tapped one in the embedded
/// workspace_shell via [ChatCubit.openSessionTab].
class HomeWorkspaceConversationPanel extends StatelessWidget {
  const HomeWorkspaceConversationPanel({required this.project, super.key});

  final AppProject project;

  static const double defaultWidth = 260;
  static const double minWidth = 200;
  static const double maxWidth = 480;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final sessions = context.select<ChatCubit, List<AppSession>>(
      (c) => c.state.sessions
          .where((s) => s.projectId == project.projectId)
          .toList(),
    );
    final activeSessionId = context.select<ChatCubit, String?>(
      (c) => c.state.activeSessionId,
    );

    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            title: l10n.homeWorkspaceConversations,
            addTooltip: l10n.homeWorkspaceNewConversation,
            onAdd: () => unawaited(_addConversation(context)),
          ),
          _SearchBox(hint: l10n.homeWorkspaceSearchHint),
          Expanded(
            child: sessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return _ConversationRow(
                        session: session,
                        active: session.sessionId == activeSessionId,
                        onTap: () => _openSession(context, session),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openSession(BuildContext context, AppSession session) {
    final chatCubit = context.read<ChatCubit>();
    final team = context.read<TeamCubit>().state.selectedTeam;
    final repo = context.read<SessionRepository>();
    final fallback = context.l10n.defaultNewChatSessionTitle;

    chatCubit.selectSession(session.sessionId);

    final leads =
        team?.members.where((m) => m.id == 'team-lead').toList() ??
            const <TeamMemberConfig>[];
    final TeamMemberConfig? lead = leads.isEmpty ? null : leads.first;

    unawaited(
      chatCubit.openSessionTab(
        session,
        team: lead != null ? team : null,
        member: lead,
        repo: repo,
        emptyDisplayTitleFallback: fallback,
      ),
    );
  }

  Future<void> _addConversation(BuildContext context) async {
    final chatCubit = context.read<ChatCubit>();
    final repo = context.read<SessionRepository>();
    final team = context.read<TeamCubit>().state.selectedTeam;
    final teamId = team?.id ?? project.teamId;

    try {
      final session = await chatCubit.createSession(
        project.projectId,
        repo,
        sessionTeamId: teamId,
        rosterMembers: team?.members ?? const [],
      );
      if (!context.mounted) return;
      _openSession(context, session);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.l10n.homeWorkspaceNewConversation}: $error'),
        ),
      );
    }
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.addTooltip,
    required this.onAdd,
  });

  final String title;
  final String addTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: styles.bodyStrong.copyWith(color: cs.onSurface),
            ),
          ),
          Tooltip(
            message: addTooltip,
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(7),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  Icons.add_rounded,
                  size: AppIconSizes.md,
                  color: cs.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: AppIconSizes.md, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(hint, style: styles.bodySmall.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
            )),
          ],
        ),
      ),
    );
  }
}

class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    required this.session,
    required this.active,
    required this.onTap,
  });

  final AppSession session;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final l10n = context.l10n;
    final active = widget.active;
    final title = widget.session.resolveDisplayTitle(
      l10n.defaultNewChatSessionTitle,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? cs.primary.withValues(alpha: 0.14)
                : _hovered
                    ? cs.onSurface.withValues(alpha: 0.05)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: AppIconSizes.md,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.body.copyWith(
                    color: active ? cs.primary : cs.onSurface,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined,
              size: AppIconSizes.md, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
