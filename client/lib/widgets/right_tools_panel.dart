import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';

class RightToolsPanel extends StatelessWidget {
  const RightToolsPanel({
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final team = teamCubit.state.selectedTeam;
    if (team == null) return const SizedBox.shrink();

    final members = [...team.members]
      ..sort((a, b) {
        if (a.name == 'team-lead') return -1;
        if (b.name == 'team-lead') return 1;
        return 0;
      });
    final panels = <Widget>[
      if (preferences.membersVisible)
        _MembersPanel(
          members: members,
          selectedMemberId: chatCubit.state.selectedMemberId,
          onSelected: (id) {
            final member =
                team.members.firstWhere((m) => m.id == id);
            context.read<ChatCubit>().openMemberTab(team, member);
          },
          onOpen: (id) {
            final member =
                team.members.firstWhere((m) => m.id == id);
            context.read<ChatCubit>().openMemberTab(team, member);
          },
          onLaunchAll: () {
            context.read<ChatCubit>().launchAllMembers(team);
          },
          isMemberRunning: (id) =>
              context.read<ChatCubit>().isMemberRunning(id),
        ),
      if (preferences.fileTreeVisible) _FileTreePanel(team: team),
    ];
    return Container(
      key: panelKey,
      color: colors.rightPanelBackground,
      child: preferences.toolsArrangement == ToolsArrangement.tabs
          ? _TabbedToolsPanel(panels: panels, preferences: preferences)
          : _StackedToolsPanel(panels: panels, preferences: preferences),
    );
  }
}

class _StackedToolsPanel extends StatelessWidget {
  const _StackedToolsPanel(
      {required this.panels, required this.preferences});

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (panels.length == 1) return panels.single;
    return Column(
      children: [
        Expanded(
          flex: (preferences.membersSplit * 100).round(),
          child: panels.first,
        ),
        Divider(height: 1, color: colors.subtleBorder),
        Expanded(
          flex: ((1 - preferences.membersSplit) * 100).round(),
          child: panels.last,
        ),
      ],
    );
  }
}

class _TabbedToolsPanel extends StatelessWidget {
  const _TabbedToolsPanel(
      {required this.panels, required this.preferences});

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = <Tab>[
      if (preferences.membersVisible) Tab(text: l10n.members),
      if (preferences.fileTreeVisible) Tab(text: l10n.fileTree),
    ];
    return DefaultTabController(
      length: panels.length,
      child: Column(
        children: [
          TabBar(tabs: tabs),
          Expanded(child: TabBarView(children: panels)),
        ],
      ),
    );
  }
}

class _MembersPanel extends StatelessWidget {
  const _MembersPanel({
    required this.members,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
    required this.onLaunchAll,
    required this.isMemberRunning,
  });

  final List<TeamMemberConfig> members;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onOpen;
  final VoidCallback onLaunchAll;
  final bool Function(String memberId) isMemberRunning;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      key: AppKeys.membersPanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.members,
                  style: TextStyle(
                    color: textBase.withValues(alpha: 0.58),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              SizedBox(
                height: 22,
                child: IconButton(
                  tooltip: l10n.openTeam,
                  onPressed: onLaunchAll,
                  icon: const Icon(Icons.keyboard_double_arrow_right,
                      size: 18),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 22),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final selected = member.id == selectedMemberId;
                final running = isMemberRunning(member.id);
                return Container(
                  key: AppKeys.memberRow(member.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected
                        ? colors.selectedMemberBg
                        : colors.unselectedMemberBg,
                    borderRadius: BorderRadius.circular(8),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      title: Text(member.name),
                      subtitle: Text(
                        [member.provider, member.model]
                            .where((v) => v.isNotEmpty)
                            .join(' / '),
                      ),
                      trailing: Container(
                        key: AppKeys.memberOpenButton(member.id),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: running
                              ? colors.accentGreen
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      onTap: () => onSelected(member.id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTreePanel extends StatelessWidget {
  const _FileTreePanel({required this.team});

  final TeamConfig team;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Container(
      key: AppKeys.fileTreePanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(title: l10n.fileTree, action: l10n.copy),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.filterFiles,
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  team.workingDirectory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textBase.withValues(alpha: 0.56), fontSize: 12),
                ),
                const SizedBox(height: 12),
                const _FileLine(
                    icon: Icons.folder_outlined, label: 'client'),
                const _FileLine(
                    icon: Icons.folder_outlined, label: 'docs'),
                const _FileLine(
                    icon: Icons.description_outlined, label: 'README.md'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Row(
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
        Text(action, style: TextStyle(color: colors.linkText)),
      ],
    );
  }
}

class _FileLine extends StatelessWidget {
  const _FileLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
