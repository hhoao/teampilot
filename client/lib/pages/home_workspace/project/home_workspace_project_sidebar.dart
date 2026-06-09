import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/chat_cubit.dart';
import '../../../cubits/project_profile_cubit.dart';
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
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'project_session_actions.dart';

/// Shared resize limits for [HomeWorkspaceProjectSidebar].
class HomeWorkspaceProjectSidebarLayout {
  const HomeWorkspaceProjectSidebarLayout._();

  static const double defaultWidth = 280;
  static const double minWidth = 220;
  static const double maxWidth = 480;
}

/// Project conversation sidebar (personal and team workbenches).
class HomeWorkspaceProjectSidebar extends StatefulWidget {
  const HomeWorkspaceProjectSidebar({required this.project, super.key});

  final AppProject project;

  @override
  State<HomeWorkspaceProjectSidebar> createState() =>
      _HomeWorkspaceProjectSidebarState();
}

class _HomeWorkspaceProjectSidebarState
    extends State<HomeWorkspaceProjectSidebar> {
  final _searchController = TextEditingController();
  var _searchQuery = '';

  bool get _isPersonal => widget.project.teamId.isEmpty;

  @override
  void initState() {
    super.initState();
    if (_isPersonal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ProjectProfileCubit>().load(widget.project.projectId);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final sessions = sessionsForProject(
      widget.project,
      context.select<ChatCubit, List<AppSession>>((c) => c.state.sessions),
    );
    final filteredSessions = filterSessionsByQuery(
      sessions,
      query: _searchQuery,
      emptyTitleFallback: l10n.defaultNewChatSessionTitle,
    );

    return Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isPersonal) ...[
            _DefaultCliDropdown(projectId: widget.project.projectId),
            const SizedBox(height: 12),
          ],
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
          _ConversationSearchField(
            controller: _searchController,
            hint: l10n.homeWorkspaceSearchHint,
            onChanged: (value) => setState(() => _searchQuery = value),
            onClear: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ),
          Expanded(
            child: sessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
                : filteredSessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoSearchResults)
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: filteredSessions.length,
                    itemBuilder: (context, index) {
                      final session = filteredSessions[index];
                      return SidebarSessionTile(
                        session: session,
                        tapThrottleKeyPrefix: 'project_sidebar_session',
                        onTap: () => unawaited(
                          openProjectSessionTab(
                            context,
                            widget.project,
                            session,
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

  Future<void> _startNewConversation(
    BuildContext context, {
    CliTool? cli,
  }) async {
    await createAndOpenProjectConversation(context, widget.project, cli: cli);
  }
}

class _DefaultCliDropdown extends StatelessWidget {
  const _DefaultCliDropdown({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final registry = CliToolRegistryScope.of(context);
    final state = context.watch<ProjectProfileCubit>().state;
    final ready =
        state.projectId == projectId &&
        state.status == ProjectProfileLoadStatus.ready &&
        state.profile != null;
    final cli = state.profile?.cli ?? CliTool.claude;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ready)
            const LinearProgressIndicator(minHeight: 2)
          else
            AppDropdownField<String>(
              key: ValueKey('project-sidebar-cli-$projectId-${cli.value}'),
              items: [for (final def in registry.launchable) def.id.value],
              initialItem: cli.value,
              decoration: AppDropdownDecorations.themed(context),
              onChanged: (value) {
                if (value == null) return;
                unawaited(
                  context.read<ProjectProfileCubit>().setCli(
                    CliTool.decode(value),
                  ),
                );
              },
              itemBuilder: (context, value) => cliDropdownRow(
                context,
                cli: CliTool.decode(value),
                label: cliDisplayName(
                  registry.tryGet(CliTool.decode(value))!,
                  l10n,
                ),
                registry: registry,
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarActionTile extends StatefulWidget {
  const _SidebarActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SidebarActionTile> createState() => _SidebarActionTileState();
}

class _SidebarActionTileState extends State<_SidebarActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final background = _hovered
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
                Icon(widget.icon, size: AppIconSizes.md, color: cs.onSurface),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.label,
                    style: styles.prominent.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
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

class _ConversationSearchField extends StatelessWidget {
  const _ConversationSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainer,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: AppIconSizes.md,
            color: cs.onSurfaceVariant,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: cs.primary),
          ),
          suffixIcon: controller.text.isNotEmpty
              ? AppIconButton(
                  icon: Icons.clear,
                  iconSize: AppIconButton.kCompactIconSize,
                  size: AppIconButton.kCompactSize,
                  onTap: onClear,
                )
              : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _EmptyConversations extends StatelessWidget {
  const _EmptyConversations({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: AppIconSizes.md,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: styles.bodySmall.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
