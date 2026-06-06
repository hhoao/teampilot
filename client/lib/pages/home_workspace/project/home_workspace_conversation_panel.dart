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
import '../../../utils/project_sessions.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/sidebar_session_tile.dart';

/// The "Conversations" tree panel (renamed from Apifox's 接口管理). Lists the
/// sessions that belong to [project] and opens the tapped one in the embedded
/// workspace_shell via [ChatCubit.openSessionTab].
class HomeWorkspaceConversationPanel extends StatefulWidget {
  const HomeWorkspaceConversationPanel({required this.project, super.key});

  final AppProject project;

  static const double defaultWidth = 260;
  static const double minWidth = 200;
  static const double maxWidth = 480;

  @override
  State<HomeWorkspaceConversationPanel> createState() =>
      _HomeWorkspaceConversationPanelState();
}

class _HomeWorkspaceConversationPanelState
    extends State<HomeWorkspaceConversationPanel> {
  final _searchController = TextEditingController();
  var _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final sessions = sessionsForProject(
      widget.project,
      context.select<ChatCubit, List<AppSession>>((c) => c.state.sessions),
    );
    final filteredSessions = filterSessionsByQuery(
      sessions,
      query: _searchQuery,
      emptyTitleFallback: l10n.defaultNewChatSessionTitle,
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
          _ConversationSearchField(
            controller: _searchController,
            hint: l10n.homeWorkspaceSearchHint,
            onChanged: (value) => setState(() => _searchQuery = value),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
          Expanded(
            child: sessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
                : filteredSessions.isEmpty
                    ? _EmptyConversations(
                        label: l10n.homeWorkspaceNoSearchResults,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        itemCount: filteredSessions.length,
                        itemBuilder: (context, index) {
                          final session = filteredSessions[index];
                          return SidebarSessionTile(
                            session: session,
                            contentLeftInset: 0,
                            tapThrottleKeyPrefix: 'home_workspace_session',
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
    final repo = context.read<SessionRepository>();
    final fallback = context.l10n.defaultNewChatSessionTitle;
    final isPersonal = widget.project.teamId.isEmpty;

    chatCubit.selectSession(session.sessionId);

    if (isPersonal) {
      unawaited(
        chatCubit.openSessionTab(
          session,
          team: null,
          member: null,
          repo: repo,
          emptyDisplayTitleFallback: fallback,
        ),
      );
      return;
    }

    final team = context.read<TeamCubit>().state.selectedTeam;
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
    final isPersonal = widget.project.teamId.isEmpty;
    final team = isPersonal ? null : context.read<TeamCubit>().state.selectedTeam;
    final teamId = isPersonal ? '' : (team?.id ?? widget.project.teamId);

    try {
      final session = await chatCubit.createSession(
        widget.project.projectId,
        repo,
        sessionTeamId: teamId,
        rosterMembers: isPersonal ? const [] : (team?.members ?? const []),
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

class _ConversationSearchField extends StatelessWidget {
  const _ConversationSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: AppIconSizes.md,
            color: cs.onSurfaceVariant,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? AppIconButton(
                  icon: Icons.clear,
                  iconSize: AppIconButton.kCompactIconSize,
                  size: AppIconButton.kCompactSize,
                  onTap: onClear,
                )
              : null,
        ),
        onChanged: onChanged,
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
          Icon(
            Icons.forum_outlined,
            size: AppIconSizes.md,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
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
