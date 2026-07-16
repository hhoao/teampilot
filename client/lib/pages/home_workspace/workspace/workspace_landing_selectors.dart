import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/worktree_cubit.dart';
import '../../../models/git_worktree.dart';
import '../../../models/runtime_target.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../utils/workspace/workspace_path_utils.dart';
import '../../../widgets/workspace_folder_directory_row.dart';
import 'workspace_chat_landing_palette.dart';

/// One row in a landing selector menu.
class LaunchSelectorOption {
  const LaunchSelectorOption({
    required this.path,
    required this.label,
    required this.icon,
    this.subtitle,
  });

  final String path;
  final String label;
  final String? subtitle;
  final IconData icon;
}

/// Workspace folder (project) choices for compose landing.
class WorkspaceLandingProjectResolver {
  const WorkspaceLandingProjectResolver({
    required this.workspace,
    this.runtimeTargets = const [],
    this.storedProjectPath,
  });

  final Workspace workspace;
  final List<RuntimeTarget> runtimeTargets;
  final String? storedProjectPath;

  List<LaunchSelectorOption> get options {
    if (workspace.folders.isEmpty) {
      final primary = workspace.firstFolderPath.trim();
      if (primary.isEmpty) return const [];
      return [
        LaunchSelectorOption(
          path: primary,
          label: Workspace.directoryName(primary),
          icon: Icons.folder_outlined,
        ),
      ];
    }

    final isMixed =
        workspaceTopologyOf(workspace.folders) == WorkspaceTopology.mixed;
    return [
      for (final folder in workspace.folders)
        LaunchSelectorOption(
          path: folder.path,
          label: Workspace.directoryName(folder.path),
          subtitle: isMixed
              ? workspaceFolderTargetLabel(runtimeTargets, folder.targetId)
              : null,
          icon: workspaceFolderTargetIcon(folder.targetId),
        ),
    ];
  }

  String resolveSelectedProjectPath() {
    final stored = storedProjectPath?.trim() ?? '';
    final opts = options;
    if (stored.isNotEmpty &&
        opts.any((o) => workspacePathsEqual(o.path, stored))) {
      return stored;
    }
    if (opts.isNotEmpty) return opts.first.path;
    return workspace.firstFolderPath;
  }

  String labelFor(String projectPath) {
    for (final option in options) {
      if (workspacePathsEqual(option.path, projectPath)) {
        return option.label;
      }
    }
    return Workspace.directoryName(projectPath);
  }

  List<TpActionMenuSpec> menuSpecs(String selectedPath) {
    return [
      for (final option in options)
        TpActionMenuSpec.item(
          value: option.path,
          icon: option.icon,
          label: option.label,
          subtitleSuffix: option.subtitle,
          selected: workspacePathsEqual(option.path, selectedPath),
        ),
    ];
  }
}

/// Git worktree choices for the active project on compose landing.
class WorkspaceLandingWorktreeResolver {
  const WorkspaceLandingWorktreeResolver({
    required this.projectPath,
    this.worktreeState,
    this.storedWorktreePath,
    List<GitWorktree> cachedWorktrees = const [],
  }) : _cachedWorktrees = cachedWorktrees;

  final String projectPath;
  final WorktreeState? worktreeState;
  final String? storedWorktreePath;
  final List<GitWorktree> _cachedWorktrees;

  List<LaunchSelectorOption> get options {
    final project = normalizeWorkspacePath(projectPath.trim());
    if (project.isEmpty) return const [];

    final worktrees = _worktreesForProject();
    if (worktrees.isEmpty) {
      return [
        LaunchSelectorOption(
          path: project,
          label: Workspace.directoryName(project),
          icon: Icons.folder_outlined,
        ),
      ];
    }

    return [
      for (final wt in worktrees)
        LaunchSelectorOption(
          path: wt.path,
          label: wt.shortBranch,
          icon: Icons.account_tree_outlined,
        ),
    ];
  }

  List<GitWorktree> _worktreesForProject() {
    final project = normalizeWorkspacePath(projectPath.trim());
    if (project.isEmpty) return const [];
    final state = worktreeState;
    if (state != null &&
        workspacePathsEqual(state.repoPath, project) &&
        state.worktrees.isNotEmpty) {
      return state.worktrees;
    }
    return _cachedWorktrees;
  }

  /// False for non-git folders (empty worktree list after load) and while the
  /// active project's worktree list is still loading.
  bool get showsWorktreeSelector {
    final worktrees = _worktreesForProject();
    if (worktrees.isNotEmpty) return true;
    final state = worktreeState;
    if (state != null &&
        workspacePathsEqual(state.repoPath, projectPath) &&
        state.loading) {
      return false;
    }
    return false;
  }

  String resolveSelectedWorktreePath() {
    final stored = storedWorktreePath?.trim() ?? '';
    final opts = options;
    if (stored.isNotEmpty &&
        opts.any((o) => workspacePathsEqual(o.path, stored))) {
      return stored;
    }
    final state = worktreeState;
    if (state != null &&
        workspacePathsEqual(state.repoPath, projectPath) &&
        state.currentWorktreePath.isNotEmpty &&
        opts.any(
          (o) => workspacePathsEqual(o.path, state.currentWorktreePath),
        )) {
      return state.currentWorktreePath;
    }
    if (opts.isNotEmpty) return opts.first.path;
    return normalizeWorkspacePath(projectPath);
  }

  String labelFor(String selectedPath) {
    for (final option in options) {
      if (workspacePathsEqual(option.path, selectedPath)) {
        return option.label;
      }
    }
    return Workspace.directoryName(selectedPath);
  }

  List<TpActionMenuSpec> menuSpecs(String selectedPath) {
    return [
      for (final option in options)
        TpActionMenuSpec.item(
          value: option.path,
          icon: option.icon,
          label: option.label,
          subtitleSuffix: option.subtitle,
          selected: workspacePathsEqual(option.path, selectedPath),
        ),
    ];
  }
}

/// Compose-landing header: project folder + worktree selectors.
class WorkspaceLandingHeaderRow extends StatelessWidget {
  const WorkspaceLandingHeaderRow({
    required this.projectLabel,
    required this.projectHintWhenEmpty,
    required this.projectMenuSpecs,
    required this.onProjectSelected,
    this.showWorktreeSelector = true,
    this.worktreeLabel = '',
    this.worktreeHintWhenEmpty = '',
    this.worktreeMenuSpecs = const [],
    this.onWorktreeSelected,
    super.key,
  });

  final String projectLabel;
  final String projectHintWhenEmpty;
  final List<TpActionMenuSpec> projectMenuSpecs;
  final ValueChanged<Object?> onProjectSelected;
  final bool showWorktreeSelector;
  final String worktreeLabel;
  final String worktreeHintWhenEmpty;
  final List<TpActionMenuSpec> worktreeMenuSpecs;
  final ValueChanged<Object?>? onWorktreeSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.tpSpacing;

    // Loose flex keeps chips content-sized and left-packed; max width still
    // constrains labels so they ellipsize instead of overflowing.
    return Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: WorkspaceLandingSelectorBar(
            compact: true,
            label: projectLabel,
            hintWhenEmpty: projectHintWhenEmpty,
            menuSpecs: projectMenuSpecs,
            onSelected: onProjectSelected,
          ),
        ),
        if (showWorktreeSelector) ...[
          SizedBox(width: spacing.sm),
          Flexible(
            fit: FlexFit.loose,
            child: WorkspaceLandingSelectorBar(
              compact: true,
              label: worktreeLabel,
              hintWhenEmpty: worktreeHintWhenEmpty,
              menuSpecs: worktreeMenuSpecs,
              onSelected: onWorktreeSelected,
            ),
          ),
        ],
      ],
    );
  }
}

/// Minimal header selector: text + optional dropdown menu.
class WorkspaceLandingSelectorBar extends StatelessWidget {
  const WorkspaceLandingSelectorBar({
    required this.label,
    required this.hintWhenEmpty,
    this.menuSpecs = const [],
    this.onSelected,
    this.compact = false,
    super.key,
  });

  final String label;
  final String hintWhenEmpty;
  final List<TpActionMenuSpec> menuSpecs;
  final ValueChanged<Object?>? onSelected;

  /// When true, content-sizes under a loose [Flexible] in [WorkspaceLandingHeaderRow].
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = WorkspaceChatLandingPalette(cs);
    final icons = context.tpIconSizes;
    final isEmpty = label.trim().isEmpty;
    final display = isEmpty ? hintWhenEmpty : label.trim();
    final foreground = isEmpty
        ? palette.hint.withValues(alpha: 0.85)
        : palette.muted.withValues(alpha: 0.88);
    final selectable = menuSpecs.isNotEmpty && onSelected != null;
    final labelWidget = Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TpTextStyles.of(context).mdColored(foreground),
    );
    if (!selectable) {
      if (compact) return labelWidget;
      return Row(children: [Flexible(child: labelWidget)]);
    }

    final expandIcon = Icon(
      Icons.expand_more,
      size: icons.md,
      color: foreground.withValues(alpha: isEmpty ? 0.9 : 0.65),
    );

    // Compact: min-sized row with a max-width label so ellipsis works without
    // stretching the chip across the Flexible slot.
    final menuRow = compact
        ? LayoutBuilder(
            builder: (context, constraints) {
              final maxLabelWidth = constraints.maxWidth.isFinite
                  ? (constraints.maxWidth - icons.md).clamp(
                      0.0,
                      double.infinity,
                    )
                  : double.infinity;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxLabelWidth),
                    child: labelWidget,
                  ),
                  expandIcon,
                ],
              );
            },
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [labelWidget, expandIcon],
          );

    final menu = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: TpActionMenuIconAnchor(
        minWidth: 240,
        triggerBuilder: (context, controller) => _LandingSelectorMenuTrigger(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: menuRow,
        ),
        buildMenuChildren: (context, controller) =>
            buildTpActionMenuChildren(
              context: context,
              specs: menuSpecs,
              menuController: controller,
              onSelect: onSelected!,
            ),
      ),
    );

    if (compact) return menu;
    return Align(alignment: Alignment.centerLeft, child: menu);
  }
}

class _LandingSelectorMenuTrigger extends StatefulWidget {
  const _LandingSelectorMenuTrigger({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_LandingSelectorMenuTrigger> createState() =>
      _LandingSelectorMenuTriggerState();
}

class _LandingSelectorMenuTriggerState
    extends State<_LandingSelectorMenuTrigger> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverColor = cs.onSurface.withValues(alpha: 0.05);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// Re-export legacy names used by tests during transition.
typedef LaunchDirectoryOption = LaunchSelectorOption;
typedef WorkspaceLandingDirectoryResolver = WorkspaceLandingProjectResolver;
