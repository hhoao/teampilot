import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/session.dart';
import '../models/team_config.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../utils/perf.dart';

class ContextSidebar extends StatefulWidget {
  const ContextSidebar({this.onNewSession, super.key});

  final VoidCallback? onNewSession;

  @override
  State<ContextSidebar> createState() => _ContextSidebarState();
}

class _ContextSidebarState extends State<ContextSidebar> {
  var _showSessions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _showSessions = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final selected = teamCubit.state.selectedTeam;

    return PipelinePerf(
      label: 'context sidebar',
      child: Container(
        key: AppKeys.contextSidebar,
        width: double.infinity,
        color: colors.sidebarBackground,
        padding: const EdgeInsets.all(13),
        child: selected == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TeamSelector(
                    teams: teamCubit.state.teams,
                    selected: selected,
                    onSelect: teamCubit.selectTeam,
                  ),
                  const SizedBox(height: 14),
                  _SidebarSectionTitle(
                    title: l10n.teamSessions,
                    actionLabel: '+',
                    onAction: widget.onNewSession,
                  ),
                  Expanded(
                    child: _showSessions
                        ? const _SessionList()
                        : const SizedBox.shrink(),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    onTap: () {
                      final sw = Stopwatch()..start();
                      FramePerf.mark('nav settings team');
                      context.go('/config/team');
                      print(
                        '[perf] context.go /config/team: ${sw.elapsedMilliseconds}ms',
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList();

  @override
  Widget build(BuildContext context) {
    final sessions = context.select<ChatCubit, List<FlashskySession>>(
      (cubit) => cubit.state.sessions,
    );
    return ListView.builder(
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        return _SessionTileEntry(session: sessions[index]);
      },
    );
  }
}

class _SessionTileEntry extends StatelessWidget {
  const _SessionTileEntry({required this.session});

  final FlashskySession session;

  @override
  Widget build(BuildContext context) {
    final selected = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.activeSessionId == session.sessionId,
    );
    return _SidebarTile(
      key: AppKeys.sessionTile(session.sessionId),
      title: session.display.isNotEmpty ? session.display : session.kind,
      subtitle: session.cwd,
      selected: selected,
      onTap: () {
        FramePerf.mark('nav session ${session.sessionId}');
        final teamCubit = context.read<TeamCubit>();
        final chatCubit = context.read<ChatCubit>();

        chatCubit.selectSession(session.sessionId);

        TeamConfig? matchingTeam;
        if (session.cwd.isNotEmpty) {
          for (final t in teamCubit.state.teams) {
            if (t.workingDirectory.trim() == session.cwd.trim()) {
              matchingTeam = t;
              break;
            }
          }
        }
        matchingTeam ??= teamCubit.state.selectedTeam;
        if (matchingTeam == null) return;

        if (teamCubit.state.selectedTeam?.id != matchingTeam.id) {
          teamCubit.selectTeam(matchingTeam.id);
        }

        final lead =
            matchingTeam.members.where((m) => m.name == 'team-lead');
        if (lead.isNotEmpty) {
          chatCubit.openMemberTab(matchingTeam, lead.first);
        } else {
          chatCubit.addSystemMessage(
              'FlashskyAI requires a member named team-lead.');
        }

        context.go('/chat');
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.sidebarSettingsButton,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.tune_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamSelector extends StatelessWidget {
  const _TeamSelector({
    required this.teams,
    required this.selected,
    required this.onSelect,
  });

  final List<TeamConfig> teams;
  final TeamConfig selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.selectTeam,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final team in teams)
          PopupMenuItem(value: team.id, child: Text(team.name)),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colors.teamSelectorBackground,
          border: Border.all(color: colors.teamSelectorBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  const _SidebarSectionTitle({
    required this.title,
    required this.actionLabel,
    this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: textBase.withValues(alpha: 0.58),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (actionLabel.isNotEmpty)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel,
                style: TextStyle(color: colors.linkText),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? colors.selectedBackground
            : colors.unselectedBackground,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? colors.selectedBorder
                    : colors.unselectedBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textBase,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textBase.withValues(alpha: 0.52),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
