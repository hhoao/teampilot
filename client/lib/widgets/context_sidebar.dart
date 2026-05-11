import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../theme/app_theme.dart';
import '../utils/app_keys.dart';
import '../utils/logger.dart';
import '../utils/perf.dart';

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
                  _SkillTile(
                    onTap: () {
                      FramePerf.mark('nav skills');
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
                      FramePerf.mark('nav team config');
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
                      final sw = Stopwatch()..start();
                      FramePerf.mark('nav settings layout');
                      context.go('/config/layout');
                      appLogger.d(
                        '[perf] context.go /config/layout: ${sw.elapsedMilliseconds}ms',
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _ProjectList extends StatelessWidget {
  const _ProjectList();

  @override
  Widget build(BuildContext context) {
    final sessions = context.select<ChatCubit, List<FlashskySession>>(
      (cubit) => cubit.state.sessions,
    );
    final l10n = context.l10n;

    // Group sessions by cwd
    final groups = <String, List<FlashskySession>>{};
    for (final s in sessions) {
      groups.putIfAbsent(s.cwd, () => []).add(s);
    }

    if (groups.isEmpty) {
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

    // Sort groups by the most recent session in each group
    final sortedEntries = groups.entries.toList()
      ..sort((a, b) {
        final aMax = a.value
            .map((s) => s.startedAt)
            .reduce((x, y) => x > y ? x : y);
        final bMax = b.value
            .map((s) => s.startedAt)
            .reduce((x, y) => x > y ? x : y);
        return bMax.compareTo(aMax);
      });

    return ListView.builder(
      itemCount: sortedEntries.length,
      itemBuilder: (context, index) {
        final entry = sortedEntries[index];
        return _ProjectGroup(
          cwd: entry.key,
          sessions: entry.value,
        );
      },
    );
  }
}

class _ProjectGroup extends StatefulWidget {
  const _ProjectGroup({required this.cwd, required this.sessions});

  final String cwd;
  final List<FlashskySession> sessions;

  @override
  State<_ProjectGroup> createState() => _ProjectGroupState();
}

class _ProjectGroupState extends State<_ProjectGroup> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dirName = widget.cwd.isNotEmpty
        ? widget.cwd.split(Platform.pathSeparator).last
        : l10n.unknownFolder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectHeader(
          name: dirName,
          path: widget.cwd,
          sessionCount: widget.sessions.length,
          expanded: _expanded,
          onToggle: () => setState(() => _expanded = !_expanded),
          onNewSession: () => _createSession(context, widget.cwd),
          onOpenFolder: widget.cwd.isNotEmpty
              ? () => _openFolder(widget.cwd)
              : null,
          onCopyPath: widget.cwd.isNotEmpty
              ? () => _copyPath(widget.cwd)
              : null,
          onDelete: widget.cwd.isNotEmpty
              ? () => _confirmDeleteProject(context, widget.cwd, dirName)
              : null,
        ),
        if (_expanded)
          ...widget.sessions.map(
            (s) => _SessionTileEntry(session: s),
          ),
        const SizedBox(height: 4),
      ],
    );
  }

  void _createSession(BuildContext context, String cwd) {
    context.read<ChatCubit>().createSession(cwd, const SessionRepository());
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
    String cwd,
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
              final cubit = context.read<ChatCubit>();
              final repo = const SessionRepository();
              for (final s in widget.sessions) {
                cubit.deleteSession(repo, s.sessionId);
              }
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
          color: _hovered ? colors.selectedBackground : colors.unselectedBackground,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _hovered ? colors.selectedBorder : colors.unselectedBorder,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggle,
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: 10,
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
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: textBase,
                                  ),
                                ),
                                if (widget.path.isNotEmpty)
                                  Text(
                                    '${widget.sessionCount} sessions',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: textBase.withValues(alpha: 0.45),
                                      fontSize: 10,
                                    ),
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
                        case 'copyPath':
                          widget.onCopyPath?.call();
                        case 'delete':
                          widget.onDelete?.call();
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

  final FlashskySession session;

  @override
  State<_SessionTileEntry> createState() => _SessionTileEntryState();
}

class _SessionTileEntryState extends State<_SessionTileEntry> {
  var _hovered = false;

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
        title: session.display.isNotEmpty ? session.display : session.kind,
        subtitle: session.cwd,
        selected: selected,
        indent: true,
        onTap: () {
          FramePerf.mark('nav session ${session.sessionId}');
          final teamCubit = context.read<TeamCubit>();
          final chatCubit = context.read<ChatCubit>();

          chatCubit.selectSession(session.sessionId);

          TeamConfig? matchingTeam;
          if (session.sessionTeam.isNotEmpty) {
            final lastDash = session.sessionTeam.lastIndexOf('-');
            if (lastDash > 0) {
              final teamName = session.sessionTeam.substring(0, lastDash);
              for (final t in teamCubit.state.teams) {
                if (t.name == teamName) {
                  matchingTeam = t;
                  break;
                }
              }
            }
          }
          matchingTeam ??= teamCubit.state.selectedTeam;
          if (matchingTeam == null) return;

          if (teamCubit.state.selectedTeam?.id != matchingTeam.id) {
            teamCubit.selectTeam(matchingTeam.id);
          }

          final lead = matchingTeam.members.where((m) => m.name == 'team-lead');
          if (lead.isNotEmpty) {
            chatCubit.openSessionTab(session, team: matchingTeam, member: lead.first, repo: const SessionRepository());
          } else {
            chatCubit.openSessionTab(session, repo: const SessionRepository());
            chatCubit.addSystemMessage(
              'FlashskyAI requires a member named team-lead.',
            );
          }

          context.go('/chat');
        },
        trailing: _hovered
            ? PopupMenuButton<String>(
                tooltip: '',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz, size: 16),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      _showRenameDialog(context, session, l10n);
                    case 'delete':
                      _showDeleteDialog(context, session, l10n);
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
    );
  }

  void _showRenameDialog(
    BuildContext context,
    FlashskySession session,
    AppLocalizations l10n,
  ) {
    final controller = TextEditingController(
      text: session.display.isNotEmpty ? session.display : session.kind,
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
              context.read<ChatCubit>().renameSession(
                const SessionRepository(),
                session.sessionId,
                value.trim(),
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
                context.read<ChatCubit>().renameSession(
                  const SessionRepository(),
                  session.sessionId,
                  value,
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
    FlashskySession session,
    AppLocalizations l10n,
  ) {
    final name = session.display.isNotEmpty ? session.display : session.kind;
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
              context.read<ChatCubit>().deleteSession(
                const SessionRepository(),
                session.sessionId,
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
    return Row(
      children: [
        Expanded(
          child: PopupMenuButton<String>(
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
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.trailing,
    this.indent = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16.0 : 0, bottom: 8),
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
            child: Row(
              children: [
                Expanded(
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
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
