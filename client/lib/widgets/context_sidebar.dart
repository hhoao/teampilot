import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubits/chat_cubit.dart';
import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_project.dart';
import '../models/app_session.dart';
import '../models/team_config.dart';
import '../repositories/session_repository.dart';
import '../services/app_storage.dart';
import '../services/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/project_path_picker.dart';
import '../utils/project_path_utils.dart';
import '../widgets/app_outline_text_field.dart';
import '../widgets/dropdown/flashsky_dropdown_field.dart';
import '../widgets/dropdown/flashskyai_dropdown_decoration.dart';
import 'project_details_dialog.dart';

/// Matches [_ProjectHeader] label start: `padding.left` + chevron + gap + folder + gap.
const double _kSidebarTreeTextInset = 12 + 16 + 6 + 16 + 6;

void _navigateToSessionInChat(BuildContext context, AppSession session) {
  final l10n = context.l10n;
  final teamCubit = context.read<TeamCubit>();
  final chatCubit = context.read<ChatCubit>();

  chatCubit.selectSession(session.sessionId);

  final matchingTeam = teamCubit.state.selectedTeam;
  if (matchingTeam == null) return;

  final lead = matchingTeam.members.where((m) => m.name == 'team-lead');
  final repo = context.read<SessionRepository>();
  if (lead.isNotEmpty) {
    unawaited(
      chatCubit.openSessionTab(
        session,
        team: matchingTeam,
        member: lead.first,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
  } else {
    unawaited(
      chatCubit.openSessionTab(
        session,
        repo: repo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
      ),
    );
    chatCubit.addSystemMessage('FlashskyAI requires a member named team-lead.');
  }

  goFromSidebar(context, '/chat');
}

Future<void> _createSessionAndOpenChat(
  BuildContext context,
  String projectId,
) async {
  final repo = context.read<SessionRepository>();
  final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
  final session = await context.read<ChatCubit>().createSession(
    projectId,
    repo,
    sessionTeamId: teamId,
  );
  if (!context.mounted) return;
  _navigateToSessionInChat(context, session);
}

AppProject? _mostRecentProject(
  List<AppProject> projects,
  List<AppSession> sessions,
) {
  if (projects.isEmpty) return null;
  final sorted = List<AppProject>.from(projects)
    ..sort(
      (a, b) =>
          _projectRecency(b, sessions).compareTo(_projectRecency(a, sessions)),
    );
  return sorted.first;
}

Future<void> _startNewChat(BuildContext context) async {
  closeAndroidDrawerIfOpen(context);
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
  final projects = chatCubit.state.visibleProjects;
  final sessions = chatCubit.state.visibleSessions;

  final project = _mostRecentProject(projects, sessions);
  if (project != null) {
    await _createSessionAndOpenChat(context, project.projectId);
    return;
  }

  try {
    await chatCubit.createProjectWithFirstSession(
      AppStorage.cwd,
      repo,
      sessionTeamId: teamId,
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.l10n.defaultNewChatSessionTitle}: $error')),
    );
    return;
  }
  if (!context.mounted) return;

  final created = context.read<ChatCubit>().state.visibleSessions;
  if (created.isEmpty) return;
  final newest = created.reduce(
    (a, b) => a.createdAt >= b.createdAt ? a : b,
  );
  _navigateToSessionInChat(context, newest);
}

String _teamCliDisplayLabel(dynamic l10n, TeamCli cli) {
  return switch (cli) {
    TeamCli.flashskyai => l10n.appProviderToolFlashskyai,
    TeamCli.codex => l10n.appProviderToolCodex,
    TeamCli.claude => l10n.appProviderToolClaude,
  };
}

Future<void> _promptAddTeam(BuildContext context, TeamCubit teamCubit) async {
  final l10n = context.l10n;
  final result = await showDialog<({String name, TeamCli cli})?>(
    context: context,
    builder: (dialogContext) => _AddTeamDialog(l10n: l10n),
  );
  if (result == null || !context.mounted) return;
  await teamCubit.addTeam(result.name, cli: result.cli);
}

/// Owns the team name [TextEditingController] for the add-team dialog.
///
/// The dialog route can still be animating after [showDialog]'s future
/// completes; disposing the controller in the caller would race updates
/// against a still-mounted [TextField].
class _AddTeamDialog extends StatefulWidget {
  const _AddTeamDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_AddTeamDialog> createState() => _AddTeamDialogState();
}

class _AddTeamDialogState extends State<_AddTeamDialog> {
  late final TextEditingController _nameController;
  TeamCli _selectedCli = TeamCli.flashskyai;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.addTeamTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppOutlineTextField(
            key: AppKeys.teamNameDialogField,
            controller: _nameController,
            autofocus: true,
            labelText: l10n.teamName,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.teamCliLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.teamCliSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final cli in TeamCli.values)
            RadioListTile<TeamCli>(
              value: cli,
              groupValue: _selectedCli,
              onChanged: cli.isLaunchSupported
                  ? (value) {
                      if (value == null) return;
                      setState(() => _selectedCli = value);
                    }
                  : null,
              title: Text(_teamCliDisplayLabel(l10n, cli)),
              subtitle: cli.isLaunchSupported
                  ? null
                  : Text(l10n.teamCliComingSoon),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, (name: name, cli: _selectedCli));
          },
          child: Text(l10n.add),
        ),
      ],
    );
  }
}

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
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final teamCubit = context.watch<TeamCubit>();
    final selected = teamCubit.state.selectedTeam;

    return Container(
      key: AppKeys.contextSidebar,
      width: double.infinity,
      color: cs.surfaceContainer,
      padding: const EdgeInsets.all(13),
      child: selected == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TeamSelector(
                  teams: teamCubit.state.teams,
                  selected: selected,
                  onSelect: (id) => unawaited(teamCubit.selectTeam(id)),
                  onAddTeam: () => _promptAddTeam(context, teamCubit),
                ),
                const SizedBox(height: 14),
                _TeamConfigTile(
                  onTap: () => goFromSidebar(context, '/team-config'),
                ),
                const SizedBox(height: 8),
                _NewChatTile(
                  onTap: () => unawaited(_startNewChat(context)),
                ),
                const SizedBox(height: 14),
                _SidebarSectionTitle(
                  title: l10n.projects,
                  actionLabel: '+',
                  actionTooltip: l10n.newProjectTooltip,
                  onAction: widget.onNewProject,
                ),
                Expanded(
                  child: _showSessions
                      ? const _ProjectList()
                      : const SizedBox.shrink(),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _SkillTile(onTap: () => goFromSidebar(context, '/skills')),
                const SizedBox(height: 8),
                _PluginTile(onTap: () => goFromSidebar(context, '/plugins')),
                const SizedBox(height: 8),
                _SettingsTile(
                  onTap: () => goFromSidebar(
                    context,
                    Platform.isAndroid ? '/config' : '/config/layout',
                  ),
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
      (cubit) => cubit.state.visibleProjects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (cubit) => cubit.state.visibleSessions,
    );
    final l10n = context.l10n;

    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          l10n.noSessions,
          style: TextStyle(
            color: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      );
    }

    final sorted = List<AppProject>.from(projects)
      ..sort(
        (a, b) => _projectRecency(
          b,
          sessions,
        ).compareTo(_projectRecency(a, sessions)),
      );

    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final project = sorted[index];
        final list = _sessionsForProject(project, sessions);
        return Padding(
          padding: EdgeInsets.only(bottom: index == sorted.length - 1 ? 0 : 10),
          child: _ProjectGroup(project: project, sessions: list),
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
              ? p.primaryPath.split(RegExp(r'[/\\]')).last
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
          onViewDetails: p.projectId.isNotEmpty
              ? () =>
                    showProjectDetailsDialog(context, p, widget.sessions.length)
              : null,
          onAddDirectory: p.projectId.isNotEmpty
              ? () => _addProjectDirectory(context, p)
              : null,
          onOpenFolder: p.primaryPath.isNotEmpty
              ? () => _openFolder(p.primaryPath)
              : null,
          onCopyPath: p.primaryPath.isNotEmpty
              ? () => _copyPath(context, p.primaryPath)
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
    unawaited(_createSessionAndOpenChat(context, projectId));
  }

  void _openFolder(String path) {
    Process.run(_openCommand, [path]);
  }

  String get _openCommand {
    if (Platform.isMacOS) return 'open';
    if (Platform.isWindows) return 'start';
    return 'xdg-open';
  }

  Future<void> _addProjectDirectory(
    BuildContext context,
    AppProject project,
  ) async {
    final path = await pickProjectDirectoryPath(context);
    if (path == null || path.trim().isEmpty || !context.mounted) return;
    final l10n = context.l10n;
    final trimmed = normalizeProjectPath(path);
    if (projectPathsEqual(trimmed, project.primaryPath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectDirectoryAlreadyPrimary)),
      );
      return;
    }
    if (projectPathsContains(project.additionalPaths, trimmed)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectDirectoryAlreadyAdded)),
      );
      return;
    }
    final repo = context.read<SessionRepository>();
    await context.read<ChatCubit>().addProjectDirectory(repo, project, trimmed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.projectDirectoryAdded)));
  }

  void _copyPath(BuildContext context, String path) {
    Clipboard.setData(ClipboardData(text: path));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.pathCopied(path)),
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
    final repo = context.read<SessionRepository>();
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
                  repo,
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
    this.onViewDetails,
    this.onAddDirectory,
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
  final VoidCallback? onViewDetails;
  final VoidCallback? onAddDirectory;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onCopyPath;
  final VoidCallback? onDelete;

  @override
  State<_ProjectHeader> createState() => _ProjectHeaderState();
}

class _ProjectHeaderState extends State<_ProjectHeader> {
  var _hovered = false;
  var _menuOpen = false;

  bool get _hasOverflowMenu =>
      widget.onViewDetails != null ||
      widget.onAddDirectory != null ||
      widget.onOpenFolder != null ||
      widget.onCopyPath != null ||
      widget.onDelete != null;

  bool get _showActions => _hovered || _menuOpen || Platform.isAndroid;

  List<PopupMenuEntry<String>> _projectMenuEntries(BuildContext context) {
    final l10n = context.l10n;
    return [
      if (widget.onViewDetails != null)
        PopupMenuItem(
          value: 'details',
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 8),
              Text(l10n.projectDetails),
            ],
          ),
        ),
      if (widget.onAddDirectory != null)
        PopupMenuItem(
          value: 'addDirectory',
          child: Row(
            children: [
              const Icon(Icons.create_new_folder_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.addProjectDirectory),
            ],
          ),
        ),
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
              Icon(
                Icons.delete_outline,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(l10n.deleteProject),
            ],
          ),
        ),
    ];
  }

  void _handleProjectMenuSelection(String value) {
    switch (value) {
      case 'details':
        widget.onViewDetails?.call();
        break;
      case 'addDirectory':
        widget.onAddDirectory?.call();
        break;
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
  }

  Future<void> _showProjectContextMenu(Offset globalPosition) async {
    if (!mounted || !_hasOverflowMenu) return;
    final overlayObject = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final anchor = overlayObject.globalToLocal(globalPosition);
    setState(() => _menuOpen = true);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlayObject.size,
      ),
      items: _projectMenuEntries(context),
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    _handleProjectMenuSelection(selected);
  }

  void _showProjectContextMenuAtCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    unawaited(_showProjectContextMenu(center));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onLongPress: Platform.isAndroid && _hasOverflowMenu
              ? _showProjectContextMenuAtCenter
              : null,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Keep action controls in the layout when hidden: [PopupMenuButton]
                  // uses a tall minimum touch target, so toggling visibility used to
                  // change the row height on hover.
                  Visibility(
                    visible: _showActions,
                    maintainSize: true,
                    maintainState: true,
                    maintainAnimation: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                        if (_hasOverflowMenu)
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
                              _handleProjectMenuSelection(value);
                            },
                            itemBuilder: _projectMenuEntries,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  Future<void> _showSessionContextMenu(Offset globalPosition) async {
    if (!mounted) return;
    final overlayObject = Overlay.maybeOf(context)?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;

    final l10n = context.l10n;
    final session = widget.session;
    final anchor = overlayObject.globalToLocal(globalPosition);
    setState(() => _menuOpen = true);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlayObject.size,
      ),
      items: _sessionOverflowMenuEntries(l10n),
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    switch (selected) {
      case 'rename':
        _showRenameDialog(context, session, l10n);
        break;
      case 'delete':
        _showDeleteDialog(context, session, l10n);
        break;
    }
  }

  List<PopupMenuEntry<String>> _sessionOverflowMenuEntries(
    AppLocalizations l10n,
  ) {
    return [
      PopupMenuItem(value: 'rename', child: Text(l10n.renameConversation)),
      PopupMenuItem(value: 'delete', child: Text(l10n.deleteConversation)),
    ];
  }

  void _showSessionContextMenuAtCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    unawaited(_showSessionContextMenu(center));
  }

  bool get _showSessionActions => _hovered || _menuOpen || Platform.isAndroid;

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
        rowHovered: _hovered || _menuOpen,
        contentLeftInset: _kSidebarTreeTextInset,
        onTap: () => _navigateToSessionInChat(context, session),
        onSecondaryTapUp: (details) =>
            _showSessionContextMenu(details.globalPosition),
        onLongPress: Platform.isAndroid
            ? _showSessionContextMenuAtCenter
            : null,
        trailing: SizedBox(
          width: 24,
          height: 24,
          child: _showSessionActions
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
                  itemBuilder: (context) => _sessionOverflowMenuEntries(l10n),
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
    final repo = context.read<SessionRepository>();
    final controller = TextEditingController(
      text: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameConversationTitle),
        content: AppOutlineTextField(
          controller: controller,
          autofocus: true,
          labelText: l10n.conversationName,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              unawaited(
                context.read<ChatCubit>().renameSession(
                  repo,
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
                    repo,
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
    final repo = context.read<SessionRepository>();
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
                  repo,
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

class _PluginTile extends StatelessWidget {
  const _PluginTile({required this.onTap});

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
              Icon(Icons.widgets_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.pluginsSidebarLabel,
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

class _NewChatTile extends StatelessWidget {
  const _NewChatTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Material(
      key: AppKeys.newChatSidebarTile,
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(Icons.add_comment_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(
                context.l10n.defaultNewChatSessionTitle,
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
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final decoration = FlashskyDropdownDecorations.sidebarTeam(context);

    return Row(
      children: [
        Expanded(
          child: FlashskyDropdownField<TeamConfig>(
            items: teams,
            initialItem: selected,
            hintText: l10n.selectTeam,
            decoration: decoration,
            itemLabel: (team) => team.name,
            onChanged: (team) {
              if (team != null && team.id != selected.id) {
                onSelect(team.id);
              }
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
                    border: Border.all(color: cs.outlineVariant),
                    color: cs.surfaceContainer,
                  ),
                  child: Icon(Icons.add, size: 18, color: cs.onSurface),
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
    this.actionTooltip,
    this.onAction,
  });

  final String title;
  final String actionLabel;
  final String? actionTooltip;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
            Builder(
              builder: (context) {
                final action = Material(
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
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
                final tip = actionTooltip;
                if (tip != null && tip.isNotEmpty) {
                  return Tooltip(message: tip, child: action);
                }
                return action;
              },
            ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  // ignore: unused_element_parameter
  const _SidebarTile({
    required this.title,
    required this.selected,
    // ignore: unused_element_parameter
    this.subtitle = '',
    this.rowHovered = false,
    this.onTap,
    this.onSecondaryTapUp,
    this.onLongPress,
    this.trailing,
    this.contentLeftInset = 0,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;

  /// From parent [MouseRegion] (and menu-open), not [InkWell] — avoids ink
  /// fighting with [PopupMenuButton] (hover patch only behind title).
  final bool rowHovered;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// Extra left padding so row text lines up with folder names (file tree).
  final double contentLeftInset;

  Color _materialFillColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    if (selected) {
      return rowHovered
          ? Color.alphaBlend(hoverTint, cs.primaryContainer)
          : cs.primaryContainer;
    }
    if (rowHovered) {
      return Color.alphaBlend(hoverTint, cs.surfaceContainer);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: _materialFillColor(context),
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapUp: onSecondaryTapUp,
          onLongPress: onLongPress,
          child: Container(
            padding: EdgeInsets.fromLTRB(contentLeftInset, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected ? Border.all(color: cs.primaryContainer) : null,
            ),
            // Do not use [CrossAxisAlignment.stretch] here: [_SidebarTile] is used
            // inside [ListView] items, which get an unbounded max height on the main
            // axis; stretch would force children to infinite height and assert.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
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
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
