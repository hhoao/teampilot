import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/project_sessions.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'project_session_actions.dart';

/// Hub-style left rail: project management, new chat, and this project's sessions.
class HomeWorkspaceProjectSidebar extends StatelessWidget {
  const HomeWorkspaceProjectSidebar({
    required this.project,
    this.manageActive = false,
    super.key,
  });

  final AppProject project;
  final bool manageActive;

  static const double defaultWidth = 280;
  static const double minWidth = 220;
  static const double maxWidth = 400;

  bool get _isPersonal => project.teamId.isEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    // Project page lists every session in this project; team-scope filtering
    // applies to the global hub sidebar, not the per-project conversation list.
    final sessions = sessionsForProject(
      project,
      context.select<ChatCubit, List<AppSession>>((c) => c.state.sessions),
    );

    return ColoredBox(
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarActionTile(
              key: AppKeys.homeWorkspaceProjectManagementTile,
              icon: Icons.tune_outlined,
              label: l10n.homeWorkspaceProjectManagement,
              selected: manageActive,
              onTap: throttledTap(
                'project_sidebar_manage',
                () => context.go(
                  '/home-v2/project/${project.projectId}?view=manage',
                ),
              ),
            ),
            const SizedBox(height: 6),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _SidebarActionTile(
                      key: AppKeys.newChatSidebarTile,
                      icon: Icons.edit_outlined,
                      label: l10n.homeWorkspaceNewConversation,
                      onTap: throttledAsync(
                        'project_sidebar_new_chat',
                        () => _startNewConversation(context),
                      ),
                    ),
                  ),
                  if (_isPersonal) ...[
                    const SizedBox(width: 6),
                    _NewConversationCliMenu(
                      onPickCli: (cli) => throttledAsync(
                        'project_sidebar_new_chat_cli_${cli.value}',
                        () => _startNewConversation(context, cli: cli),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                l10n.homeWorkspaceConversationsSection,
                style: AppTextStyles.of(context).bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? Center(
                      child: Text(
                        l10n.homeWorkspaceNoConversations,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.of(
                          context,
                        ).bodySmall.copyWith(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return SidebarSessionTile(
                          session: session,
                          tapThrottleKeyPrefix: 'project_sidebar_session',
                          onTap: () async {
                            if (manageActive) {
                              context.go(
                                '/home-v2/project/${project.projectId}',
                              );
                            }
                            await openProjectSessionTab(
                              context,
                              project,
                              session,
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startNewConversation(
    BuildContext context, {
    CliTool? cli,
  }) async {
    if (manageActive) {
      context.go('/home-v2/project/${project.projectId}');
    }
    await createAndOpenProjectConversation(context, project, cli: cli);
  }
}

class _NewConversationCliMenu extends StatelessWidget {
  const _NewConversationCliMenu({required this.onPickCli});

  final VoidCallback Function(CliTool cli) onPickCli;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final registry = CliToolRegistryScope.of(context);

    return MenuAnchor(
      builder: (context, controller, child) {
        return Tooltip(
          message: l10n.homeWorkspaceNewConversationChooseCli,
          child: Material(
            key: AppKeys.newChatCliMenuButton,
            color: cs.primary,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(
                    Icons.add_rounded,
                    size: AppIconSizes.md,
                    color: cs.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      menuChildren: [
        for (final def in registry.launchable)
          MenuItemButton(
            onPressed: onPickCli(def.id),
            child: Text(cliDisplayName(def, l10n)),
          ),
      ],
    );
  }
}

class _SidebarActionTile extends StatefulWidget {
  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final selected = widget.selected;
    final background = selected
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: AppIconSizes.md,
                  color: selected ? cs.primary : cs.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: styles.prominent.copyWith(
                      color: selected ? cs.primary : cs.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
