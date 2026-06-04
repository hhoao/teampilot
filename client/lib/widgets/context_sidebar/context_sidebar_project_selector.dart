part of '../context_sidebar.dart';

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
          size: AppIconSizes.md,
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
              Icon(Icons.folder_outlined, size: AppIconSizes.md, color: labelColor),
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
