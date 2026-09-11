import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_session.dart';
import '../../../models/workspace.dart';
import '../../../utils/session/session_project_grouping.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'workspace_session_actions.dart';
import 'workspace_sidebar_row_metrics.dart';

const String _projectOrphanKey = '<project-orphan>';

class ProjectTreeSection extends StatefulWidget {
  const ProjectTreeSection({
    required this.groups,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    super.key,
  });

  final List<ProjectSessionGroup> groups;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;

  @override
  State<ProjectTreeSection> createState() => _ProjectTreeSectionState();
}

class _ProjectTreeSectionState extends State<ProjectTreeSection> {
  final Set<String> _collapsedPaths = <String>{};

  String _groupKey(ProjectSessionGroup group) =>
      group.projectPath ?? _projectOrphanKey;

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups
        .where((group) => group.sessions.isNotEmpty)
        .toList(growable: false);
    if (groups.isEmpty) {
      return TpEmptyState(
        icon: Icons.forum_outlined,
        title: context.l10n.homeWorkspaceNoConversations,
        centered: true,
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final groupKey = _groupKey(group);
        final collapsed = _collapsedPaths.contains(groupKey);
        return _ProjectTreeGroup(
          group: group,
          workspace: widget.workspace,
          tabScopeId: widget.tabScopeId,
          highlightSessionId: widget.highlightSessionId,
          collapsed: collapsed,
          onToggle: () => setState(() {
            if (collapsed) {
              _collapsedPaths.remove(groupKey);
            } else {
              _collapsedPaths.add(groupKey);
            }
          }),
        );
      },
    );
  }
}

class _ProjectTreeGroup extends StatefulWidget {
  const _ProjectTreeGroup({
    required this.group,
    required this.workspace,
    required this.tabScopeId,
    required this.highlightSessionId,
    required this.collapsed,
    required this.onToggle,
    super.key,
  });

  final ProjectSessionGroup group;
  final Workspace workspace;
  final String tabScopeId;
  final String? highlightSessionId;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_ProjectTreeGroup> createState() => _ProjectTreeGroupState();
}

class _ProjectTreeGroupState extends State<_ProjectTreeGroup> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.group.isOther
        ? context.l10n.projectTreeOther
        : widget.group.label;
    final icon = _hovered
        ? widget.collapsed
              ? Icons.chevron_right_rounded
              : Icons.expand_more_rounded
        : Icons.folder_outlined;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpHoverRow(
          key: ValueKey(
            'project-tree-node-${widget.group.projectPath ?? '<project-orphan>'}',
          ),
          padding: kWorkspaceSidebarRowPadding,
          hoverColor: workspaceSidebarRowHoverFill(cs),
          onHoverChanged: (hovered) => setState(() => _hovered = hovered),
          onTap: widget.onToggle,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(child: Icon(icon, size: context.tpIconSizes.md)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!widget.collapsed)
          for (final session in widget.group.sessions)
            _sessionTile(context, session),
      ],
    );
  }

  Widget _sessionTile(BuildContext context, AppSession session) {
    return SidebarSessionTile(
      key: ValueKey('project-tree-session-${session.sessionId}'),
      session: session,
      highlightSessionId: widget.highlightSessionId,
      onTap: () => openWorkspaceSessionTab(
        context,
        widget.workspace,
        session,
        tabScopeId: widget.tabScopeId,
      ),
    );
  }
}
