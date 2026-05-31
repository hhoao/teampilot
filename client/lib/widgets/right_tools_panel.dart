import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app_provider_cubit.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/editor_cubit.dart';
import '../cubits/file_tree_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../models/app_provider_config.dart';
import '../services/file_tree/file_tree_visible_rows.dart';
import '../services/storage/app_storage.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/layout_preferences.dart';
import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../services/cli/registry/cli_tool_registry_scope.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../utils/team_member_naming.dart';
import '../widgets/team/team_lead_badge.dart';
import 'app_icon_button.dart';
import 'file_tree_node.dart';
import 'menu/sidebar_action_menu.dart';
import 'split_layout.dart';
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
    final cubit = context.read<ChatCubit>();
    if (!identical(_chatCubit, cubit)) {
      _chatCubit?.detachPresenceUi();
      _chatCubit = cubit;
      cubit.attachPresenceUi();
    }
  }

  @override
  void dispose() {
    _chatCubit?.detachPresenceUi();
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
        if (TeamMemberNaming.isTeamLead(a)) return -1;
        if (TeamMemberNaming.isTeamLead(b)) return 1;
        return a.name.compareTo(b.name);
      });
    void maybeDismissDrawer() {
      if (widget.dismissDrawerOnAction) {
        Navigator.of(context).maybePop();
      }
    }

    final panels = <Widget>[
      if (widget.preferences.membersVisible)
        _MembersPanel(
          teamCli: team.cli,
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
          ? _TabbedToolsPanel(panels: panels, preferences: widget.preferences)
          : _StackedToolsPanel(panels: panels, preferences: widget.preferences),
    );
  }
}

class _StackedToolsPanel extends StatelessWidget {
  const _StackedToolsPanel({required this.panels, required this.preferences});

  final List<Widget> panels;
  final LayoutPreferences preferences;

  @override
  Widget build(BuildContext context) {
    if (panels.length == 1) return panels.single;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final minTop = totalHeight * 0.25;
        final maxTop = totalHeight * 0.75;
        return TwoPaneSplitView(
          axis: Axis.vertical,
          fixedChildIndex: 0,
          initialFraction: preferences.membersSplit,
          minSize: minTop,
          maxSize: maxTop,
          dynamicMax: true,
          first: panels.first,
          second: panels.last,
          onSizeChanged: (topHeight) {
            context.read<LayoutCubit>().setMembersSplit(
              (topHeight / totalHeight).clamp(0.25, 0.75),
            );
          },
        );
      },
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
    required this.teamCli,
    required this.members,
    required this.memberPresence,
    required this.selectedMemberId,
    required this.onSelected,
    required this.onOpen,
    required this.onLaunchAll,
  });

  final TeamCli teamCli;
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
    final catalogCli =
        CliToolRegistryScope.maybeOf(
          context,
        )?.tryGet(teamCli.value)?.providerCatalogCli ??
        AppProviderCli.claude;
    final providerLabels = {
      for (final p in context.watch<AppProviderCubit>().state.providersFor(
        catalogCli,
      ))
        p.id: p.name,
    };
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
              AppIconButton(
                icon: Icons.keyboard_double_arrow_right,
                tooltip: l10n.openTeam,
                size: AppIconButton.kCompactSize,
                onTap: onLaunchAll,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final selected = member.id == selectedMemberId;
                final presence =
                    memberPresence[member.id] ?? const MemberPresence.offline();
                final statusLabel = memberPresenceStatusLabel(l10n, presence);
                final providerId = member.provider.trim();
                final providerLabel = providerId.isEmpty
                    ? ''
                    : (providerLabels[providerId] ?? providerId);
                final meta = [
                  providerLabel,
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
                        title: MemberTitleRow(
                          member: member,
                          fallbackName: l10n.memberName,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textColor: titleColor,
                          compactBadge: true,
                        ),
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
      final index = visibleRowIndexForPath(rows, target, _cubit.fs.pathContext);
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
                          BlocBuilder<LayoutCubit, LayoutState>(
                            buildWhen: (previous, next) =>
                                previous.preferences.workspaceTerminalVisible !=
                                next.preferences.workspaceTerminalVisible,
                            builder: (context, layoutState) {
                              final terminalVisible = layoutState
                                  .preferences
                                  .workspaceTerminalVisible;
                              return _FileTreeHeaderOverflowMenu(
                                l10n: l10n,
                                workspaceTerminalVisible: terminalVisible,
                                showHiddenFiles: state.showHiddenFiles,
                                canCopy: state.rootPath.isNotEmpty,
                                onToggleTerminal: () => context
                                    .read<LayoutCubit>()
                                    .setWorkspaceTerminalVisible(
                                      !terminalVisible,
                                    ),
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
                              );
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
                              ? AppIconButton(
                                  icon: Icons.clear,
                                  iconSize: AppIconButton.kCompactIconSize,
                                  size: AppIconButton.kCompactSize,
                                  onTap: () {
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
                          style: AppTextStyles.of(
                            context,
                          ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                        )
                      else
                        Text(
                          'Directory unavailable',
                          style: AppTextStyles.of(context).bodySmall.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
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
      BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (previous, next) =>
            previous.preferences.workspaceTerminalVisible !=
            next.preferences.workspaceTerminalVisible,
        builder: (context, layoutState) {
          final visible = layoutState.preferences.workspaceTerminalVisible;
          return AppIconButton(
            icon: visible ? Icons.terminal : Icons.terminal_outlined,
            iconSize: AppIconButton.kCompactIconSize,
            size: AppIconButton.kCompactSize,
            tooltip: visible
                ? l10n.workspaceTerminalHide
                : l10n.workspaceTerminalShow,
            onTap: () => context
                .read<LayoutCubit>()
                .setWorkspaceTerminalVisible(!visible),
          );
        },
      ),
      AppIconButton(
        icon: Icons.my_location_outlined,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.fileTreeRevealActiveFile,
        onTap: () => unawaited(_revealActiveEditorFile()),
      ),
      AppIconButton(
        icon: state.showHiddenFiles
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
        iconSize: AppIconButton.kCompactIconSize,
        size: AppIconButton.kCompactSize,
        tooltip: state.showHiddenFiles
            ? 'Hide hidden files'
            : 'Show hidden files',
        onTap: _cubit.toggleShowHidden,
      ),
      AppIconButton(
        icon: Icons.copy,
        iconSize: 14,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.copy,
        onTap: () {
          if (state.rootPath.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: state.rootPath));
          }
        },
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
        style: AppTextStyles.of(
          context,
        ).bodySmall.copyWith(color: textColor.withValues(alpha: 0.35)),
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
                  style: AppTextStyles.of(
                    context,
                  ).caption.copyWith(color: textColor.withValues(alpha: 0.35)),
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

enum _FileTreeHeaderAction { terminal, reveal, toggleHidden, copy }

class _FileTreeHeaderOverflowMenu extends StatelessWidget {
  const _FileTreeHeaderOverflowMenu({
    required this.l10n,
    required this.workspaceTerminalVisible,
    required this.showHiddenFiles,
    required this.canCopy,
    required this.onToggleTerminal,
    required this.onReveal,
    required this.onToggleHidden,
    required this.onCopy,
  });

  final AppLocalizations l10n;
  final bool workspaceTerminalVisible;
  final bool showHiddenFiles;
  final bool canCopy;
  final VoidCallback onToggleTerminal;
  final VoidCallback onReveal;
  final VoidCallback onToggleHidden;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SidebarActionMenuButton(
        tooltip: l10n.fileTree,
        icon: const Icon(Icons.more_vert, size: AppIconButton.kCompactIconSize),
        size: AppIconButton.kCompactSize,
        specs: [
          SidebarActionMenuSpec.item(
            value: _FileTreeHeaderAction.terminal,
            icon: workspaceTerminalVisible
                ? Icons.terminal
                : Icons.terminal_outlined,
            label: workspaceTerminalVisible
                ? l10n.workspaceTerminalHide
                : l10n.workspaceTerminalShow,
          ),
          SidebarActionMenuSpec.item(
            value: _FileTreeHeaderAction.reveal,
            icon: Icons.my_location_outlined,
            label: l10n.fileTreeRevealActiveFile,
          ),
          SidebarActionMenuSpec.item(
            value: _FileTreeHeaderAction.toggleHidden,
            icon: showHiddenFiles
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            label: showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
          ),
          SidebarActionMenuSpec.item(
            value: _FileTreeHeaderAction.copy,
            icon: Icons.copy,
            label: l10n.copy,
            enabled: canCopy,
          ),
        ],
        onSelected: (action) {
          switch (action as _FileTreeHeaderAction) {
            case _FileTreeHeaderAction.terminal:
              onToggleTerminal();
            case _FileTreeHeaderAction.reveal:
              onReveal();
            case _FileTreeHeaderAction.toggleHidden:
              onToggleHidden();
            case _FileTreeHeaderAction.copy:
              onCopy();
          }
        },
    );
  }
}
