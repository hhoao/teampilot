import 'package:flutter/material.dart';

import '../utils/app_keys.dart';
import '../controllers/chat_controller.dart';
import '../l10n/app_localizations.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../theme/app_theme.dart';

typedef OpenMemberCallback = Future<void> Function(String memberId);

class RightToolsPanel extends StatelessWidget {
  const RightToolsPanel({
    required this.team,
    required this.chatController,
    required this.onOpenMember,
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    super.key,
  });

  final TeamConfig team;
  final ChatController chatController;
  final OpenMemberCallback onOpenMember;
  final LayoutPreferences preferences;
  final Key panelKey;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final members = [...team.members]
      ..sort((a, b) {
        if (a.name == 'team-lead') {
          return -1;
        }
        if (b.name == 'team-lead') {
          return 1;
        }
        return 0;
      });
    final panels = <Widget>[
      if (preferences.membersVisible)
        _MembersPanel(
          members: members,
          selectedMemberId: chatController.selectedMemberId,
          onSelected: chatController.selectMember,
          onOpen: onOpenMember,
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
  const _StackedToolsPanel({required this.panels, required this.preferences});

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (panels.length == 1) {
      return panels.single;
    }
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
  const _TabbedToolsPanel({required this.panels, required this.preferences});

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
  });

  final List<TeamMemberConfig> members;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final OpenMemberCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    return Container(
      key: AppKeys.membersPanel,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelTitle(title: l10n.members, action: l10n.openTeam),
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final selected = member.id == selectedMemberId;
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      title: Text(member.name),
                      subtitle: Text(
                        [
                          member.provider,
                          member.model,
                        ].where((value) => value.isNotEmpty).join(' / '),
                      ),
                      trailing: IconButton(
                        key: AppKeys.memberOpenButton(member.id),
                        tooltip: l10n.openMember,
                        onPressed: () => onOpen(member.id),
                        icon: const Icon(Icons.open_in_new, size: 18),
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
                    color: textBase.withValues(alpha: 0.56),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                const _FileLine(icon: Icons.folder_outlined, label: 'client'),
                const _FileLine(icon: Icons.folder_outlined, label: 'docs'),
                const _FileLine(
                  icon: Icons.description_outlined,
                  label: 'README.md',
                ),
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
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
