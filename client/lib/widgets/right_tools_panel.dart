import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/storage/app_storage.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import 'file_tree_node.dart';
import 'member_presence_indicator.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  String? _syncedPresenceTeamId;
  ChatCubit? _chatCubit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatCubit = context.read<ChatCubit>();
  }

  @override
  void dispose() {
    _chatCubit?.stopPresencePolling();
    super.dispose();
  }

  static String _sessionCwd(ChatCubit chatCubit) {
    final tabs = chatCubit.state.tabs;
    final index = chatCubit.state.activeTabIndex;
    if (index >= 0 && index < tabs.length) {
      final cwd = tabs[index].subtitle;
      if (cwd.isNotEmpty) {
        return cwd;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final teamCubit = context.watch<TeamCubit>();
    final chatCubit = context.watch<ChatCubit>();
    final team = teamCubit.state.selectedTeam;
    final teamId = team?.id;
    if (teamId != _syncedPresenceTeamId) {
      _syncedPresenceTeamId = teamId;
      final cubit = _chatCubit;
      final teamSnapshot = team;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cubit?.syncPresenceTeam(teamSnapshot);
      });
    }
    if (team == null) return const SizedBox.shrink();

    final members = [...team.members]
      ..sort((a, b) {
        if (a.name == 'team-lead') return -1;
        if (b.name == 'team-lead') return 1;
        return 0;
      });
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    final panels = <Widget>[
      if (widget.preferences.membersVisible)
        _MembersPanel(
          members: members,
          memberPresence: chatCubit.state.memberPresence,
          selectedMemberId: chatCubit.state.selectedMemberId,
          onSelected: (id) {
            final member = team.members.firstWhere((m) => m.id == id);
            unawaited(context.read<ChatCubit>().openMemberTab(team, member));
            maybeDismissDrawer();
          },
          onOpen: (id) {
            final member = team.members.firstWhere((m) => m.id == id);
            unawaited(context.read<ChatCubit>().openMemberTab(team, member));
            maybeDismissDrawer();
          },
          onLaunchAll: throttledAsync('right_tools_launch_all', () async {
            await context.read<ChatCubit>().launchAllMembers(team);
            maybeDismissDrawer();
          }),
        ),
      if (widget.preferences.fileTreeVisible)
        _FileTreePanel(team: team, cwd: _sessionCwd(chatCubit)),
    ];
    return Container(
      key: widget.panelKey,
      color: cs.workspaceSubtleSurface,
      child: widget.preferences.toolsArrangement == ToolsArrangement.tabs
          ? _TabbedToolsPanel(
              panels: panels,
              preferences: widget.preferences,
            )
          : _StackedToolsPanel(
              panels: panels,
              preferences: widget.preferences,
            ),
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
    required this.memberPresence,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
    required this.onLaunchAll,
  });

  final List<TeamMemberConfig> members;
  final Map<String, MemberPresence> memberPresence;
  final String selectedMemberId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onOpen;
  final VoidCallback onLaunchAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
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
                final presence =
                    memberPresence[member.id] ?? const MemberPresence.offline();
                final statusLabel = memberPresenceStatusLabel(l10n, presence);
                final meta = [
                  member.provider,
                  member.model,
                ].where((v) => v.isNotEmpty).join(' / ');
                final subtitle = meta.isEmpty
                    ? statusLabel
                    : '$statusLabel · $meta';
                final titleColor = selected
                    ? cs.onSecondaryContainer
                    : cs.onSurface;
                final subtitleColor = selected
                    ? cs.onSecondaryContainer.withValues(alpha: 0.74)
                    : cs.onSurfaceVariant;
                return Container(
                  key: AppKeys.memberRow(member.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: selected ? cs.secondaryContainer : cs.workspaceInset,
                    borderRadius: BorderRadius.circular(8),
                    child: Tooltip(
                      message: '$statusLabel · ${member.name}',
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(member.name),
                        textColor: titleColor,
                        iconColor: titleColor,
                        subtitle: Text(
                          subtitle,
                          style: TextStyle(color: subtitleColor),
                        ),
                        trailing: MemberPresenceIndicator(presence: presence),
                        onTap: () => onSelected(member.id),
                      ),
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
  final _cubit = FileTreeCubit(fs: AppStorage.fs);
  final _filterController = TextEditingController();
  final _listScrollController = ScrollController();

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

  Future<void> _revealActiveEditorFile() async {
    final active = context.read<EditorCubit>().state.activePath;
    if (active == null) return;

    _filterController.clear();
    final ok = await _cubit.revealPath(active);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.fileTreeRevealFailed)),
      );
      return;
    }
    _scheduleRevealScroll();
  }

  void _scheduleRevealScroll([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final target = _cubit.state.revealPath;
      if (target == null) return;

      if (!_listScrollController.hasClients) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        }
        return;
      }

      final rows = visibleFileTreeRows(
        state: _cubit.state,
        pathContext: _cubit.fs.pathContext,
      );
      final index = visibleRowIndexForPath(
        rows,
        target,
        _cubit.fs.pathContext,
      );
      if (index == null) {
        if (attempt < 12) {
          _scheduleRevealScroll(attempt + 1);
        } else if (mounted) {
          _cubit.clearRevealPath();
        }
        return;
      }

      final position = _listScrollController.position;
      final viewport = position.viewportDimension;
      final rowTop = index * kFileTreeRowExtent;
      final targetOffset = (rowTop - viewport * 0.35).clamp(
        0.0,
        position.maxScrollExtent,
      );
      await _listScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      if (mounted) {
        _cubit.clearRevealPath();
      }
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    _listScrollController.dispose();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FileTreeCubit, FileTreeState>(
        builder: (context, state) {
          return Container(
            key: AppKeys.fileTreePanel,
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const actionSlotWidth = 28.0;
                    final showInlineActions =
                        constraints.maxWidth >= actionSlotWidth * 3;
                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.fileTree,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (showInlineActions)
                          ..._buildFileTreeHeaderActions(
                            l10n: l10n,
                            state: state,
                          )
                        else
                          _FileTreeHeaderOverflowMenu(
                            l10n: l10n,
                            showHiddenFiles: state.showHiddenFiles,
                            canCopy: state.rootPath.isNotEmpty,
                            onReveal: () =>
                                unawaited(_revealActiveEditorFile()),
                            onToggleHidden: _cubit.toggleShowHidden,
                            onCopy: () {
                              if (state.rootPath.isNotEmpty) {
                                Clipboard.setData(
                                  ClipboardData(text: state.rootPath),
                                );
                              }
                            },
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _filterController,
                        decoration: InputDecoration(
                          hintText: l10n.filterFiles,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          suffixIcon: _filterController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _filterController.clear();
                                    _cubit.setFilter('');
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) {
                          _cubit.setFilter(v);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      if (state.rootExists)
                        Text(
                          state.rootPath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        )
                      else
                        Text(
                          'Directory unavailable',
                          style: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: state.rootExists
                            ? _buildFileList(state, cs.onSurface)
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

  List<Widget> _buildFileTreeHeaderActions({
    required AppLocalizations l10n,
    required FileTreeState state,
  }) {
    return [
      _fileTreeHeaderIconButton(
        tooltip: l10n.fileTreeRevealActiveFile,
        onPressed: () => unawaited(_revealActiveEditorFile()),
        icon: const Icon(Icons.my_location_outlined, size: 16),
      ),
      _fileTreeHeaderIconButton(
        tooltip: state.showHiddenFiles
            ? 'Hide hidden files'
            : 'Show hidden files',
        onPressed: _cubit.toggleShowHidden,
        icon: Icon(
          state.showHiddenFiles
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 16,
        ),
      ),
      _fileTreeHeaderIconButton(
        tooltip: l10n.copy,
        onPressed: () {
          if (state.rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: state.rootPath));
          }
        },
        icon: const Icon(Icons.copy, size: 14),
      ),
    ];
  }

  Widget _buildFileList(FileTreeState state, Color textColor) {
    final rows = visibleFileTreeRows(
      state: state,
      pathContext: _cubit.fs.pathContext,
    );
    if (rows.isEmpty) {
      return Text(
        '(empty)',
        style: TextStyle(
          fontSize: 12,
          color: textColor.withValues(alpha: 0.35),
        ),
      );
    }
    return ListView.builder(
      controller: _listScrollController,
      itemCount: rows.length,
      itemExtent: kFileTreeRowExtent,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.isEmptyPlaceholder) {
          return SizedBox(
            height: kFileTreeRowExtent,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: row.depth * 16 + 22),
                child: Text(
                  '(empty)',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          );
        }
        return FileTreeNode(
          path: row.path,
          entry: row.entry,
          depth: row.depth,
          cubit: _cubit,
          textColor: textColor,
        );
      },
    );
  }
}

const _fileTreeHeaderButtonConstraints = BoxConstraints(
  minWidth: 28,
  minHeight: 22,
);

Widget _fileTreeHeaderIconButton({
  required String tooltip,
  required VoidCallback onPressed,
  required Widget icon,
}) {
  return SizedBox(
    height: 22,
    width: 28,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: _fileTreeHeaderButtonConstraints,
    ),
  );
}

enum _FileTreeHeaderAction { reveal, toggleHidden, copy }

class _FileTreeHeaderOverflowMenu extends StatelessWidget {
  const _FileTreeHeaderOverflowMenu({
    required this.l10n,
    required this.showHiddenFiles,
    required this.canCopy,
    required this.onReveal,
    required this.onToggleHidden,
    required this.onCopy,
  });

  final AppLocalizations l10n;
  final bool showHiddenFiles;
  final bool canCopy;
  final VoidCallback onReveal;
  final VoidCallback onToggleHidden;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      width: 28,
      child: PopupMenuButton<_FileTreeHeaderAction>(
        tooltip: l10n.fileTree,
        padding: EdgeInsets.zero,
        constraints: _fileTreeHeaderButtonConstraints,
        icon: const Icon(Icons.more_vert, size: 16),
        onSelected: (action) {
          switch (action) {
            case _FileTreeHeaderAction.reveal:
              onReveal();
            case _FileTreeHeaderAction.toggleHidden:
              onToggleHidden();
            case _FileTreeHeaderAction.copy:
              onCopy();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _FileTreeHeaderAction.reveal,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.my_location_outlined, size: 18),
              title: Text(l10n.fileTreeRevealActiveFile),
            ),
          ),
          PopupMenuItem(
            value: _FileTreeHeaderAction.toggleHidden,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                showHiddenFiles
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              title: Text(
                showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
              ),
            ),
          ),
          PopupMenuItem(
            value: _FileTreeHeaderAction.copy,
            enabled: canCopy,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.copy, size: 18),
              title: Text(l10n.copy),
            ),
          ),
        ],
      ),
    );
  }
}
