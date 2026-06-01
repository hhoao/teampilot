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
import '../models/default_team_roster.dart';
import '../models/team_config.dart';
import '../services/cli/registry/cli_display_name.dart';
import '../services/cli/registry/cli_tool_registry_scope.dart';
import '../repositories/session_repository.dart';
import '../services/storage/app_storage.dart';
import '../services/app/platform_utils.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import '../utils/project_path_picker.dart';
import '../utils/project_path_utils.dart';
import 'dropdown/app_dropdown_field.dart';
import '../theme/app_text_styles.dart';
import '../theme/workspace_surface_layers.dart';
import 'dropdown/app_dropdown_decoration.dart';
import 'dropdown/dropdown_menu_item_button.dart';
import 'dropdown/popover/app_popover.dart';
import 'menu/sidebar_action_menu.dart';
import 'project_details_dialog.dart';
import 'app_icon_button.dart';

const double _kSidebarSessionTileInset = 12;

/// Matches [_NewChatTile] / [_TeamConfigTile] inner padding for left alignment.
const double _kSidebarNavRowPadding = 10;

void _navigateToSessionInChat(BuildContext context, AppSession session) {
  final l10n = context.l10n;
  final teamCubit = context.read<TeamCubit>();
  final chatCubit = context.read<ChatCubit>();

  chatCubit.selectSession(session.sessionId);

  final matchingTeam = teamCubit.state.selectedTeam;
  if (matchingTeam == null) return;

  final lead = matchingTeam.members.where((m) => m.id == 'team-lead');
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
  final team = context.read<TeamCubit>().state.selectedTeam;
  final teamId = team?.id ?? '';
  final session = await context.read<ChatCubit>().createSession(
    projectId,
    repo,
    sessionTeamId: teamId,
    rosterMembers: team?.members ?? const [],
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

String _projectDisplayName(AppProject project, AppLocalizations l10n) {
  if (project.effectiveDisplay.isNotEmpty) return project.effectiveDisplay;
  if (project.primaryPath.isNotEmpty) {
    return project.primaryPath.split(RegExp(r'[/\\]')).last;
  }
  return l10n.unknownFolder;
}

List<AppProject> _sortedProjects(
  List<AppProject> projects,
  List<AppSession> sessions,
) {
  final sorted = List<AppProject>.from(projects)
    ..sort(
      (a, b) =>
          _projectRecency(b, sessions).compareTo(_projectRecency(a, sessions)),
    );
  return sorted;
}

AppProject? _resolveSelectedProject(
  List<AppProject> projects,
  List<AppSession> sessions,
  String? selectedProjectId,
) {
  if (projects.isEmpty) return null;
  if (selectedProjectId != null) {
    for (final p in projects) {
      if (p.projectId == selectedProjectId) return p;
    }
  }
  return _mostRecentProject(projects, sessions);
}

Future<void> _startNewChat(
  BuildContext context, {
  String? preferredProjectId,
}) async {
  closeAndroidDrawerIfOpen(context);
  final chatCubit = context.read<ChatCubit>();
  final repo = context.read<SessionRepository>();
  final teamId = context.read<TeamCubit>().state.selectedTeam?.id ?? '';
  final projects = chatCubit.state.visibleProjects;
  final sessions = chatCubit.state.visibleSessions;

  AppProject? project;
  if (preferredProjectId != null && preferredProjectId.isNotEmpty) {
    for (final p in projects) {
      if (p.projectId == preferredProjectId) {
        project = p;
        break;
      }
    }
  }
  project ??= _mostRecentProject(projects, sessions);
  if (project != null) {
    await _createSessionAndOpenChat(context, project.projectId);
    return;
  }

  try {
    final team = context.read<TeamCubit>().state.selectedTeam;
    await chatCubit.createProjectWithFirstSession(
      AppStorage.cwd,
      repo,
      sessionTeamId: teamId,
      rosterMembers: team?.members ?? const [],
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${context.l10n.defaultNewChatSessionTitle}: $error'),
      ),
    );
    return;
  }
  if (!context.mounted) return;

  final created = context.read<ChatCubit>().state.visibleSessions;
  if (created.isEmpty) return;
  final newest = created.reduce((a, b) => a.createdAt >= b.createdAt ? a : b);
  _navigateToSessionInChat(context, newest);
}

Future<void> _promptAddTeam(BuildContext context, TeamCubit teamCubit) async {
  final l10n = context.l10n;
  final result = await showDialog<
      ({String name, TeamCli cli, TeamMode teamMode})?>(
    context: context,
    builder: (dialogContext) => _AddTeamDialog(l10n: l10n),
  );
  if (result == null || !context.mounted) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  await teamCubit.addTeam(
    result.name,
    cli: result.cli,
    teamMode: result.teamMode,
    members: DefaultTeamRoster.localized(l10n, joinedAt: now),
  );
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
  TeamMode _selectedMode = TeamMode.native;
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
    final launchable = CliToolRegistryScope.of(context).launchable.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return AlertDialog(
      title: Text(l10n.addTeamTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: AppKeys.teamNameDialogField,
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.teamName),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.teamModeLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          RadioGroup<TeamMode>(
            groupValue: _selectedMode,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedMode = value);
            },
            child: Column(
              children: [
                RadioListTile<TeamMode>(
                  value: TeamMode.native,
                  title: Text(l10n.teamModeNative),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<TeamMode>(
                  value: TeamMode.mixed,
                  title: Text(l10n.teamModeMixed),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
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
          RadioGroup<TeamCli>(
            groupValue: _selectedCli,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedCli = value);
            },
            child: Column(
              children: [
                for (final def in launchable)
                  RadioListTile<TeamCli>(
                    value: TeamCli.decode(def.id),
                    title: Text(cliDisplayName(def, l10n)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
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
            Navigator.pop(
              context,
              (name: name, cli: _selectedCli, teamMode: _selectedMode),
            );
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
  String? _selectedProjectId;

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
    final teamCubit = context.watch<TeamCubit>();
    final selected = teamCubit.state.selectedTeam;
    final projects = context.select<ChatCubit, List<AppProject>>(
      (cubit) => cubit.state.visibleProjects,
    );
    final sessions = context.select<ChatCubit, List<AppSession>>(
      (cubit) => cubit.state.visibleSessions,
    );
    final sortedProjects = _sortedProjects(projects, sessions);
    final selectedProject = _resolveSelectedProject(
      sortedProjects,
      sessions,
      _selectedProjectId,
    );

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
                  onTap: throttledTap(
                    'context_sidebar_team_config',
                    () => goFromSidebar(context, '/team-config'),
                  ),
                ),
                _NewChatTile(
                  onTap: throttledAsync(
                    'context_sidebar_new_chat',
                    () => _startNewChat(
                      context,
                      preferredProjectId: selectedProject?.projectId,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _showSessions
                      ? _ProjectSelector(
                          projects: sortedProjects,
                          selected: selectedProject,
                          sessions: sessions,
                          onSelect: (project) => setState(
                            () => _selectedProjectId = project.projectId,
                          ),
                          onNewProject: widget.onNewProject,
                        )
                      : const SizedBox.shrink(),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _SettingsTile(
                  onTap: throttledTap(
                    'context_sidebar_settings',
                    () => goFromSidebar(
                      context,
                      Platform.isAndroid ? '/config' : '/config/layout',
                    ),
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

class _ProjectSelector extends StatefulWidget {
  const _ProjectSelector({
    required this.projects,
    required this.selected,
    required this.sessions,
    required this.onSelect,
    this.onNewProject,
  });

  final List<AppProject> projects;
  final AppProject? selected;
  final List<AppSession> sessions;
  final ValueChanged<AppProject> onSelect;
  final VoidCallback? onNewProject;

  @override
  State<_ProjectSelector> createState() => _ProjectSelectorState();
}

class _ProjectSelectorState extends State<_ProjectSelector> {
  late final AppPopoverController _projectPickerController;
  @override
  void initState() {
    super.initState();
    _projectPickerController = AppPopoverController();
  }

  @override
  void dispose() {
    _projectPickerController.dispose();
    super.dispose();
  }

  VoidCallback? get _headerAddAction => widget.onNewProject;

  Widget _projectPickerRow(
    BuildContext context,
    AppProject project,
    AppDropdownDecoration decoration, {
    required bool inList,
  }) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final name = _projectDisplayName(project, l10n);
    final style = inList ? decoration.listItemStyle : decoration.headerStyle;
    return Row(
      children: [
        Icon(
          Icons.folder_outlined,
          size: 16,
          color: cs.onSurfaceVariant.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }

  double? _projectPickerPanelWidth(BoxConstraints constraints) =>
      constraints.maxWidth.isFinite ? constraints.maxWidth : null;

  String? _headerAddTooltip(AppLocalizations l10n) =>
      widget.onNewProject != null ? l10n.newProjectTooltip : null;

  List<Widget> _projectMenuChildren(
    BuildContext context,
    MenuController menuController,
    AppProject project,
    String displayName,
    int sessionCount,
  ) {
    final l10n = context.l10n;
    final hasId = project.projectId.isNotEmpty;
    void select(String value) => _handleProjectMenuSelection(
      context,
      project,
      displayName,
      sessionCount,
      value,
    );

    Widget item({
      required IconData icon,
      required String label,
      required String value,
      bool destructive = false,
    }) {
      return SidebarActionMenuItem(
        icon: icon,
        label: label,
        destructive: destructive,
        menuController: menuController,
        onTap: () => select(value),
      );
    }

    return [
      if (hasId)
        item(
          icon: Icons.info_outline,
          label: l10n.projectDetails,
          value: 'details',
        ),
      if (hasId)
        item(
          icon: Icons.folder_copy_outlined,
          label: l10n.addProjectDirectory,
          value: 'addDirectory',
        ),
      if (project.primaryPath.isNotEmpty)
        item(
          icon: Icons.folder_open,
          label: l10n.openFolder,
          value: 'openFolder',
        ),
      if (project.primaryPath.isNotEmpty)
        item(icon: Icons.copy, label: l10n.copyFolderPath, value: 'copyPath'),
      if (hasId) ...[
        const SidebarActionMenuDivider(),
        item(
          icon: Icons.delete_outline,
          label: l10n.deleteProject,
          value: 'delete',
          destructive: true,
        ),
      ],
    ];
  }

  void _handleProjectMenuSelection(
    BuildContext context,
    AppProject project,
    String displayName,
    int sessionCount,
    String value,
  ) {
    switch (value) {
      case 'details':
        showProjectDetailsDialog(context, project, sessionCount);
        break;
      case 'addDirectory':
        unawaited(_addProjectDirectory(context, project));
        break;
      case 'openFolder':
        _openFolder(project.primaryPath);
        break;
      case 'copyPath':
        _copyPath(context, project.primaryPath);
        break;
      case 'delete':
        _confirmDeleteProject(context, project, displayName);
        break;
    }
  }

  void _openFolder(String path) {
    final command = Platform.isMacOS
        ? 'open'
        : Platform.isWindows
        ? 'start'
        : 'xdg-open';
    Process.run(command, [path]);
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
            onPressed: throttledAsync(
              'context_sidebar_delete_project',
              () async {
                await context.read<ChatCubit>().deleteProject(
                  repo,
                  project.projectId,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final selected = widget.selected;
    final projects = widget.projects;
    final hasProjects = projects.isNotEmpty;
    final sessions = context.read<ChatCubit>().state.visibleSessions;
    final addTooltip = _headerAddTooltip(l10n);
    final addAction = _headerAddAction;
    final pickerDecoration = AppDropdownDecorations.themed(
      context,
      closedFillColor: cs.workspaceCard,
      expandedFillColor: cs.workspaceCard,
      borderRadius: 8,
      listItemFontWeight: FontWeight.w600,
      expandedShadowBlurRadius: 22,
      expandedShadowOffset: const Offset(0, 10),
      expandedShadowAlphaDark: 0.5,
      expandedShadowAlphaLight: 0.12,
      selectedPrimaryAlphaDark: 0.22,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final pickerPanelWidth = _projectPickerPanelWidth(constraints);
        final switchButton = AppPopover(
          controller: _projectPickerController,
          panelWidth: pickerPanelWidth,
          padding: pickerDecoration.menuPadding,
          decoration: pickerDecoration.menuDecoration(),
          anchor: const AppAnchor(
            childAlignment: Alignment.topRight,
            overlayAlignment: Alignment.bottomRight,
            offset: Offset(0, 4),
          ),
          popover: (_) {
            return ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: kAppDropdownDefaultOverlayHeight,
              ),
              child: FocusScope(
                autofocus: true,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: projects.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: kAppDropdownListItemGap),
                  itemBuilder: (context, index) {
                    final project = projects[index];
                    final isSelected = selected?.projectId == project.projectId;
                    return SizedBox(
                      width: double.infinity,
                      child: DropdownMenuItemButton(
                        padding: kAppDropdownListItemPadding,
                        borderRadius: pickerDecoration.listItemBorderRadius,
                        highlightColor: pickerDecoration.listItemHighlightColor,
                        selectedColor: pickerDecoration.listItemSelectedColor,
                        isSelected: isSelected,
                        onTap: () {
                          widget.onSelect(project);
                          _projectPickerController.hide();
                        },
                        child: _projectPickerRow(
                          context,
                          project,
                          pickerDecoration,
                          inList: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          child: AppIconButton(
            icon: Icons.swap_horiz,
            iconSize: AppIconButton.kCompactIconSize,
            size: AppIconButton.kCompactSize,
            tooltip: l10n.switchProjectTooltip,
            enabled: hasProjects,
            onTap: hasProjects ? _projectPickerController.toggle : null,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProjectSectionHeader(
              label: l10n.projects,
              addTooltip: addTooltip,
              onAdd: addAction,
              switchControl: switchButton,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: selected == null
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        l10n.noSessions,
                        style: AppTextStyles.of(context).bodySmall.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _ProjectDirectoryGroup(
                          key: ValueKey(selected.projectId),
                          project: selected,
                          sessions: _sessionsForProject(selected, sessions),
                          onSelect: () => widget.onSelect(selected),
                          buildMenuChildren: (context, controller) =>
                              _projectMenuChildren(
                                context,
                                controller,
                                selected,
                                _projectDisplayName(selected, l10n),
                                _sessionsForProject(selected, sessions).length,
                              ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ProjectDirectoryGroup extends StatelessWidget {
  const _ProjectDirectoryGroup({
    required this.project,
    required this.sessions,
    required this.onSelect,
    required this.buildMenuChildren,
    super.key,
  });

  final AppProject project;
  final List<AppSession> sessions;
  final VoidCallback onSelect;
  final List<Widget> Function(BuildContext context, MenuController controller)
  buildMenuChildren;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectFolderHeader(
          project: project,
          onSelect: onSelect,
          buildMenuChildren: buildMenuChildren,
        ),
        if (sessions.isNotEmpty)
          for (final session in sessions) _SessionTileEntry(session: session),
      ],
    );
  }
}

class _ProjectFolderHeader extends StatefulWidget {
  const _ProjectFolderHeader({
    required this.project,
    required this.onSelect,
    required this.buildMenuChildren,
  });

  final AppProject project;
  final VoidCallback onSelect;
  final List<Widget> Function(BuildContext context, MenuController controller)
  buildMenuChildren;

  @override
  State<_ProjectFolderHeader> createState() => _ProjectFolderHeaderState();
}

class _ProjectFolderHeaderState extends State<_ProjectFolderHeader> {
  var _hovered = false;
  var _menuOpen = false;

  bool get _showActions => _hovered || _menuOpen || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final name = _projectDisplayName(widget.project, l10n);
    final labelColor = cs.onSurfaceVariant.withValues(alpha: 0.85);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: throttledTap(
          'context_sidebar_project_${widget.project.projectId}',
          widget.onSelect,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_kSidebarNavRowPadding, 6, 4, 4),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: labelColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (widget.project.projectId.isNotEmpty)
                SizedBox(
                  width: AppIconButton.kDefaultSize,
                  height: AppIconButton.kDefaultSize,
                  child: _showActions
                      ? SidebarActionMenuIconAnchor(
                          icon: Icon(
                            Icons.more_horiz,
                            size: AppIconButton.kDefaultIconSize,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                          onOpen: () => setState(() => _menuOpen = true),
                          onClose: () => setState(() => _menuOpen = false),
                          buildMenuChildren: widget.buildMenuChildren,
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectSectionHeader extends StatelessWidget {
  const _ProjectSectionHeader({
    required this.label,
    this.addTooltip,
    this.onAdd,
    this.switchControl,
  });

  final String label;
  final String? addTooltip;
  final VoidCallback? onAdd;
  final Widget? switchControl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: _kSidebarNavRowPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (onAdd != null && addTooltip != null)
            AppIconButton(
              icon: Icons.add,
              iconSize: AppIconButton.kCompactIconSize,
              size: AppIconButton.kCompactSize,
              tooltip: addTooltip,
              onTap: onAdd,
            ),
          if (switchControl != null) switchControl!,
        ],
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
  /// the overflow menu before a menu item can be selected.
  var _menuOpen = false;

  Future<void> _showSessionContextMenu(Offset globalPosition) async {
    if (!mounted) return;

    final l10n = context.l10n;
    final session = widget.session;
    setState(() => _menuOpen = true);
    final selected = await showSidebarActionMenu<String>(
      context: context,
      globalPosition: globalPosition,
      itemCount: 2,
      children: [
        SidebarActionMenuPopupItem(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.renameConversation,
        ),
        SidebarActionMenuPopupItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.deleteConversation,
          destructive: true,
        ),
      ],
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
        contentLeftInset: _kSidebarSessionTileInset,
        onTap: throttledTap(
          'context_sidebar_session_${session.sessionId}',
          () => _navigateToSessionInChat(context, session),
        ),
        onSecondaryTapUp: (details) =>
            _showSessionContextMenu(details.globalPosition),
        onLongPress: Platform.isAndroid
            ? _showSessionContextMenuAtCenter
            : null,
        trailing: SizedBox(
          width: AppIconButton.kDefaultSize,
          height: AppIconButton.kDefaultSize,
          child: _showSessionActions
              ? SidebarActionMenuIconAnchor(
                  icon: const Icon(
                    Icons.more_horiz,
                    size: AppIconButton.kDefaultIconSize,
                  ),
                  onOpen: () => setState(() => _menuOpen = true),
                  onClose: () => setState(() => _menuOpen = false),
                  buildMenuChildren: (context, controller) => [
                    SidebarActionMenuItem(
                      icon: Icons.drive_file_rename_outline,
                      label: l10n.renameConversation,
                      menuController: controller,
                      onTap: () => _showRenameDialog(context, session, l10n),
                    ),
                    SidebarActionMenuItem(
                      icon: Icons.delete_outline,
                      label: l10n.deleteConversation,
                      destructive: true,
                      menuController: controller,
                      onTap: () => _showDeleteDialog(context, session, l10n),
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
    final repo = context.read<SessionRepository>();
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
          decoration: InputDecoration(labelText: l10n.conversationName),
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
            onPressed: throttledAsync(
              'context_sidebar_rename_session',
              () async {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  await context.read<ChatCubit>().renameSession(
                    repo,
                    session.sessionId,
                    value,
                  );
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
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
            onPressed: throttledAsync(
              'context_sidebar_delete_session',
              () async {
                await context.read<ChatCubit>().deleteSession(
                  repo,
                  session.sessionId,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
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
              Text(context.l10n.teamConfig),
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
              Icon(Icons.edit_outlined, size: 18, color: textBase),
              const SizedBox(width: 10),
              Text(context.l10n.defaultNewChatSessionTitle),
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
    final decoration = AppDropdownDecorations.themed(
      context,
      closedFillColor: cs.workspaceCard,
      expandedFillColor: cs.workspaceCard,
      borderRadius: 8,
      headerFontWeight: FontWeight.w700,
      listItemFontWeight: FontWeight.w600,
      suffixIconSize: 18,
      expandedShadowBlurRadius: 22,
      expandedShadowOffset: const Offset(0, 10),
      expandedShadowAlphaDark: 0.5,
      expandedShadowAlphaLight: 0.12,
      selectedPrimaryAlphaDark: 0.22,
    );

    return Container(
      margin: const EdgeInsets.only(top: 14),
      // InputDecorator below the closed header adds invisible height; top-align
      // a fixed-size add button with the visible field instead of stretching it.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppDropdownField<TeamConfig>(
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
            AppIconButton(
              icon: Icons.add,
              tooltip: l10n.addTeamTooltip,
              onTap: onAddTeam,
            ),
          ],
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
  /// fighting with the overflow menu (hover patch only behind title).
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
            padding: EdgeInsets.fromLTRB(8 + contentLeftInset, 6, 8, 6),
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
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.of(context).caption.copyWith(
                                color: textBase.withValues(alpha: 0.52),
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
