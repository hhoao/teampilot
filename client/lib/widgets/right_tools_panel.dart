import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../models/team_config.dart';
import '../utils/app_keys.dart';
import 'app_outline_text_field.dart';
import 'file_tree_node.dart';

class RightToolsPanel extends StatelessWidget {
  const RightToolsPanel({
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;

  static String _sessionCwd(ChatCubit chatCubit) {
    final tabs = chatCubit.state.tabs;
    final index = chatCubit.state.activeTabIndex;
    if (index >= 0 && index < tabs.length) {
      final cwd = tabs[index].subtitle;
      if (cwd.isNotEmpty && Directory(cwd).existsSync()) {
        return cwd;
      }
    }
    return Directory.current.path;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            final member = team.members.firstWhere((m) => m.id == id);
            unawaited(context.read<ChatCubit>().openMemberTab(team, member));
          },
          onOpen: (id) {
            final member = team.members.firstWhere((m) => m.id == id);
            unawaited(context.read<ChatCubit>().openMemberTab(team, member));
          },
          onLaunchAll: () {
            unawaited(context.read<ChatCubit>().launchAllMembers(team));
          },
          isMemberRunning: (id) =>
              context.read<ChatCubit>().isMemberRunning(id),
        ),
      if (preferences.fileTreeVisible)
        _FileTreePanel(team: team, cwd: _sessionCwd(chatCubit)),
    ];
    return Container(
      key: panelKey,
      color: cs.surfaceContainerLow,
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
    final cs = Theme.of(context).colorScheme;
    if (panels.length == 1) return panels.single;
    return Column(
      children: [
        Expanded(
          flex: (preferences.membersSplit * 100).round(),
          child: panels.first,
        ),
        Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
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
          TabBar(tabs: tabs, isScrollable: true),
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
    final cs = Theme.of(context).colorScheme;
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
                  icon: const Icon(Icons.keyboard_double_arrow_right, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 22,
                  ),
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
                        ? cs.secondaryContainer
                        : cs.surfaceContainerHigh,
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
                        ].where((v) => v.isNotEmpty).join(' / '),
                      ),
                      trailing: Container(
                        key: AppKeys.memberOpenButton(member.id),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: running
                              ? cs.secondary
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

class _FileTreePanel extends StatefulWidget {
  const _FileTreePanel({required this.team, required this.cwd});

  final TeamConfig team;
  final String cwd;

  @override
  State<_FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<_FileTreePanel> {
  final _cubit = FileTreeCubit();
  final _filterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncRoot();
  }

  @override
  void didUpdateWidget(covariant _FileTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd) {
      _syncRoot();
    }
  }

  void _syncRoot() {
    _cubit.setRoot(widget.cwd);
  }

  @override
  void dispose() {
    _filterController.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);

    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FileTreeCubit, FileTreeState>(
        builder: (context, state) {
          final rootExists =
              state.rootPath.isNotEmpty &&
              Directory(state.rootPath).existsSync();
          return Container(
            key: AppKeys.fileTreePanel,
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.fileTree,
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
                      width: 28,
                      child: IconButton(
                        tooltip: state.showHiddenFiles
                            ? 'Hide hidden files'
                            : 'Show hidden files',
                        onPressed: () => _cubit.toggleShowHidden(),
                        icon: Icon(
                          state.showHiddenFiles
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 22,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 22,
                      width: 28,
                      child: IconButton(
                        tooltip: l10n.copy,
                        onPressed: () {
                          if (state.rootPath.isNotEmpty) {
                            Clipboard.setData(
                              ClipboardData(text: state.rootPath),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 22,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppOutlineTextField(
                        controller: _filterController,
                        hintText: l10n.filterFiles,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _filterController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _filterController.clear();
                                  _cubit.setFilter('');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        onChanged: (v) {
                          _cubit.setFilter(v);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      if (rootExists)
                        Text(
                          state.rootPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textBase.withValues(alpha: 0.56),
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          'Directory unavailable',
                          style: TextStyle(
                            color: textBase.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: rootExists
                            ? ListView(
                                children: [
                                  for (final entry in _cubit.entriesFor(
                                    state.rootPath,
                                  ))
                                    FileTreeNode(
                                      path: entry.path,
                                      entity: entry,
                                      depth: 0,
                                      cubit: _cubit,
                                      textColor: textBase,
                                    ),
                                  if (_cubit.entriesFor(state.rootPath).isEmpty)
                                    Text(
                                      '(empty)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textBase.withValues(alpha: 0.35),
                                      ),
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
