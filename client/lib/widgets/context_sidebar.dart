import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../widgets/dropdown/custom_dropdown.dart';
import '../widgets/dropdown/flashskyai_dropdown_decoration.dart';

/// Matches [_ProjectHeader] label start: `padding.left` + chevron + gap + folder + gap.
const double _kSidebarTreeTextInset = 12 + 16 + 6 + 16 + 6;

class ContextSidebar extends StatefulWidget {
  const ContextSidebar({this.onNewProject, super.key});

  final VoidCallback? onNewProject;

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

    return Container(
      key: AppKeys.contextSidebar,
      width: double.infinity,
      color: colors.sidebarBackground,
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SkillTile(
                  onTap: () {
                    context.go('/skills');
                  },
                ),
                const SizedBox(height: 14),
                _TeamSelector(
                  teams: teamCubit.state.teams,
                  selected: selected,
                  onSelect: teamCubit.selectTeam,
                  onAddTeam: () => teamCubit.addTeam(),
                ),
                const SizedBox(height: 14),
                _TeamConfigTile(
                  onTap: () {
                    context.go('/team-config');
                  },
                ),
                const SizedBox(height: 14),
                _SidebarSectionTitle(
                  title: l10n.projects,
                  actionLabel: '+',
                  onAction: widget.onNewProject,
                ),
                Expanded(
                  child: _showSessions
                      ? const _ProjectList()
                      : const SizedBox.shrink(),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _SettingsTile(
                  onTap: () {
                    context.go('/config/layout');
                  },
                ),
              ],
            ),
    );
  }
}

/// Most recently touched session time for a project (for ordering).
int _projectRecency(AppProject project, List<AppSession> allSessions) {
  var max = project.updatedAt;
  for (final s in allSessions) {
    if (s.projectId != project.projectId) continue;
    final t = s.updatedAt != 0 ? s.updatedAt : s.createdAt;
    if (t > max) max = t;
  }
  return max;
}

List<AppSession> _sessionsForProject(AppProject project, List<AppSession> all) {
  final byId = {for (final s in all) s.sessionId: s};
  final ordered = <AppSession>[];
  for (final id in project.sessionIds) {
    final s = byId[id];
    if (s != null) ordered.add(s);
  }
  for (final s in all) {
    if (s.projectId != project.projectId) continue;
    if (ordered.any((x) => x.sessionId == s.sessionId)) continue;
    ordered.add(s);
  }
  return ordered;
}

class _ProjectList extends StatelessWidget {
  const _ProjectList();

  @override
  Widget build(BuildContext context) {
    final projects = context.select<ChatCubit, List<AppProject>>(
      (cubit) => cubit.state.projects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (cubit) => cubit.state.sessions,
    );
    final l10n = context.l10n;

    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          l10n.noSessions,
          style: TextStyle(
            color: Theme.of(context)
                .textTheme
                .bodySmall
                ?.color
                ?.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      );
    }

    final sorted = List<AppProject>.from(projects)
      ..sort((a, b) => _projectRecency(b, sessions).compareTo(_projectRecency(a, sessions)));

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final project = sorted[index];
        final list = _sessionsForProject(project, sessions);
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == sorted.length - 1 ? 0 : 10,
          ),
          child: _ProjectGroup(
            project: project,
            sessions: list,
          ),
        );
      },
    );
  }
}

class _ProjectGroup extends StatefulWidget {
  const _ProjectGroup({required this.project, required this.sessions});

  final AppProject project;
  final List<AppSession> sessions;

  @override
  State<_ProjectGroup> createState() => _ProjectGroupState();
}

class _ProjectGroupState extends State<_ProjectGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.sessions.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = widget.project;
    final displayName = p.effectiveDisplay.isNotEmpty
        ? p.effectiveDisplay
        : (p.primaryPath.isNotEmpty
            ? p.primaryPath.split(Platform.pathSeparator).last
            : l10n.unknownFolder);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectHeader(
          name: displayName,
          path: p.primaryPath,
          sessionCount: widget.sessions.length,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          onNewSession: () => _createSession(context, p.projectId),
          onOpenFolder: p.primaryPath.isNotEmpty
              ? () => _openFolder(p.primaryPath)
              : null,
          onCopyPath: p.primaryPath.isNotEmpty
              ? () => _copyPath(p.primaryPath)
              : null,
          onDelete: p.projectId.isNotEmpty
              ? () => _confirmDeleteProject(context, p, displayName)
              : null,
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.sessions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  _SessionTileEntry(session: widget.sessions[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: 2),
      ],
    );
  }

  void _createSession(BuildContext context, String projectId) {
    unawaited(
      context.read<ChatCubit>().createSession(
            projectId,
            SessionRepository(),
          ),
    );
  }

  void _openFolder(String path) {
    Process.run(_openCommand, [path]);
  }

  String get _openCommand {
    if (Platform.isMacOS) return 'open';
    if (Platform.isWindows) return 'start';
    return 'xdg-open';
  }

  void _copyPath(String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Path copied: $path'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmDeleteProject(
    BuildContext context,
    AppProject project,
    String name,
  ) {
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteProject),
        content: Text(l10n.deleteProjectConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              unawaited(
                context.read<ChatCubit>().deleteProject(
                      SessionRepository(),
                      project.projectId,
                    ),
              );
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}

class _ProjectHeader extends StatefulWidget {
  const _ProjectHeader({
    required this.name,
    required this.path,
    required this.sessionCount,
    required this.expanded,
    required this.onToggle,
    required this.onNewSession,
    this.onOpenFolder,
    this.onCopyPath,
    this.onDelete,
  });

  final String name;
  final String path;
  final int sessionCount;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onNewSession;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onCopyPath;
  final VoidCallback? onDelete;

  @override
  State<_ProjectHeader> createState() => _ProjectHeaderState();
}

class _ProjectHeaderState extends State<_ProjectHeader> {
  var _hovered = false;
  var _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final colors = AppColors.of(context);
    final showActions = _hovered || _menuOpen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 4,
                        top: 8,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            widget.expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                            color: textBase.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.folder_outlined,
                            size: 16,
                            color: textBase.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (showActions) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: widget.onNewSession,
                  child: Tooltip(
                    message: l10n.newSessionTooltip,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.add,
                        size: 16,
                        color: colors.linkText,
                      ),
                    ),
                  ),
                ),
                if (widget.onOpenFolder != null ||
                    widget.onCopyPath != null ||
                    widget.onDelete != null)
                  PopupMenuButton<String>(
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: textBase.withValues(alpha: 0.5),
                    ),
                    onOpened: () => setState(() => _menuOpen = true),
                    onCanceled: () => setState(() => _menuOpen = false),
                    onSelected: (value) {
                      setState(() => _menuOpen = false);
                      switch (value) {
                        case 'openFolder':
                          widget.onOpenFolder?.call();
                          break;
                        case 'copyPath':
                          widget.onCopyPath?.call();
                          break;
                        case 'delete':
                          widget.onDelete?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (widget.onOpenFolder != null)
                        PopupMenuItem(
                          value: 'openFolder',
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.openFolder),
                            ],
                          ),
                        ),
                      if (widget.onCopyPath != null)
                        PopupMenuItem(
                          value: 'copyPath',
                          child: Row(
                            children: [
                              const Icon(Icons.copy, size: 18),
                              const SizedBox(width: 8),
                              Text(l10n.copyFolderPath),
                            ],
                          ),
                        ),
                      if (widget.onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 18,
                                  color:
                                      Theme.of(context).colorScheme.error),
                              const SizedBox(width: 8),
                              Text(l10n.deleteProject),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    ));
  }
}

class _SessionTileEntry extends StatefulWidget {
  const _SessionTileEntry({required this.session});

  final AppSession session;

  @override
  State<_SessionTileEntry> createState() => _SessionTileEntryState();
}

class _SessionTileEntryState extends State<_SessionTileEntry> {
  var _hovered = false;
  /// Keeps the overflow menu mounted while the popup is open; otherwise moving
  /// the pointer onto the overlay triggers [MouseRegion.onExit] and removes
  /// the [PopupMenuButton] before a menu item can be selected.
  var _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final selected = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.activeSessionId == session.sessionId,
    );
    final l10n = context.l10n;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _SidebarTile(
        key: AppKeys.sessionTile(session.sessionId),
        title: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
        selected: selected,
        contentLeftInset: _kSidebarTreeTextInset,
        onTap: () {
          final teamCubit = context.read<TeamCubit>();
          final chatCubit = context.read<ChatCubit>();

          chatCubit.selectSession(session.sessionId);

          final matchingTeam = teamCubit.state.selectedTeam;
          if (matchingTeam == null) return;

          final lead = matchingTeam.members.where((m) => m.name == 'team-lead');
          if (lead.isNotEmpty) {
            chatCubit.openSessionTab(
              session,
              team: matchingTeam,
              member: lead.first,
              repo: context.read<SessionRepository>(),
              emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
            );
          } else {
            chatCubit.openSessionTab(
              session,
              repo: context.read<SessionRepository>(),
              emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
            );
            chatCubit.addSystemMessage(
              'FlashskyAI requires a member named team-lead.',
            );
          }

          context.go('/chat');
        },
        trailing: SizedBox(
            width: 24,
            height: 24,
            child: _hovered || _menuOpen
                ? PopupMenuButton<String>(
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: const Icon(Icons.more_horiz, size: 16),
                    onOpened: () => setState(() => _menuOpen = true),
                    onCanceled: () => setState(() => _menuOpen = false),
                    onSelected: (value) {
                      setState(() => _menuOpen = false);
                      switch (value) {
                        case 'rename':
                          _showRenameDialog(context, session, l10n);
                          break;
                        case 'delete':
                          _showDeleteDialog(context, session, l10n);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(l10n.renameConversation),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.deleteConversation),
                      ),
                    ],
                  )
                : null,
          ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) {
    final controller = TextEditingController(
      text: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameConversationTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.conversationName,
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              unawaited(
                context.read<ChatCubit>().renameSession(
                  SessionRepository(),
                  session.sessionId,
                  value.trim(),
                ),
              );
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                unawaited(
                  context.read<ChatCubit>().renameSession(
                    SessionRepository(),
                    session.sessionId,
                    value,
                  ),
                );
              }
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) {
    final name = session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConversation),
        content: Text(l10n.deleteConversationConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              unawaited(
                context.read<ChatCubit>().deleteSession(
                  SessionRepository(),
                  session.sessionId,
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
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

class _SkillTile extends StatelessWidget {
  const _SkillTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.skillsSidebarLabel,
                style: TextStyle(fontWeight: FontWeight.w700, color: textBase),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamConfigTile extends StatelessWidget {
  const _TeamConfigTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.groups_2_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.teamConfig,
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
    this.onAddTeam,
  });

  final List<TeamConfig> teams;
  final TeamConfig selected;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAddTeam;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final decoration = FlashskyDropdownDecorations.sidebarTeam(context);

    return Row(
      children: [
        Expanded(
          child: DropdownFlutter<TeamConfig>(
            items: teams,
            initialItem: selected,
            excludeSelected: false,
            hintText: l10n.selectTeam,
            decoration: decoration,
            closedHeaderPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            expandedHeaderPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            listItemPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
            overlayHeight: 280,
            onChanged: (team) {
              if (team != null && team.id != selected.id) {
                onSelect(team.id);
              }
            },
            headerBuilder: (context, team, _) => Text(
              team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: decoration.headerStyle,
            ),
            listItemBuilder: (context, team, isSelected, _) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: decoration.listItemStyle,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (onAddTeam != null) ...[
          const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: onAddTeam,
              child: Tooltip(
                message: l10n.addTeamTooltip,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.teamSelectorBorder),
                    color: colors.teamSelectorBackground,
                  ),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: colors.linkText,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
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
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      color: colors.linkText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
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
    this.subtitle = '',
    required this.selected,
    this.onTap,
    this.trailing,
    this.contentLeftInset = 0,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  /// Extra left padding so row text lines up with folder names (file tree).
  final double contentLeftInset;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            contentLeftInset,
            6,
            8,
            6,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: colors.selectedBorder)
                : null,
          ),
          // Do not use [CrossAxisAlignment.stretch] here: [_SidebarTile] is used
          // inside [ListView] items, which get an unbounded max height on the main
          // axis; stretch would force children to infinite height and assert.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onTap,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (subtitle.isNotEmpty) ...[
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
