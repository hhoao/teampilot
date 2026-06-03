import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../chat_page.dart';
import 'home_workspace_conversation_panel.dart';
import 'home_workspace_project_rail.dart';

/// Apifox-style project detail page body: a narrow icon rail, the
/// "Conversations" panel (renamed from 接口管理), and the existing chat
/// workspace_shell on the right. The title bar/tabs come from
/// [HomeWorkspaceShell].
class HomeWorkspaceProjectPage extends StatelessWidget {
  const HomeWorkspaceProjectPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    final project = context.select<ChatCubit, AppProject?>(
      (c) => _findProject(c.state.projects, projectId),
    );

    if (project == null) {
      return _MissingProject(label: l10n.homeWorkspaceEmptyProjects);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeWorkspaceProjectRail(
          brandColor: cs.primary,
          onInvite: () => context.go('/team-config'),
        ),
        HomeWorkspaceConversationPanel(project: project),
        const Expanded(child: ChatPage()),
      ],
    );
  }

  static AppProject? _findProject(List<AppProject> projects, String id) {
    for (final p in projects) {
      if (p.projectId == id) return p;
    }
    return null;
  }
}

class _MissingProject extends StatelessWidget {
  const _MissingProject({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
    );
  }
}
