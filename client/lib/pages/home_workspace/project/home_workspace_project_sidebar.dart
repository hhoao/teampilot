import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../../cubits/app_provider_cubit.dart';
import '../../../cubits/chat_cubit.dart';
import '../../../cubits/project_profile_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/project_profile.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../theme/app_text_styles.dart';
import '../../../utils/app_keys.dart';
import '../../../utils/app_session_sort.dart';
import '../../../utils/debounce/debounce.dart';
import '../../../utils/project_sessions.dart';
import '../../../widgets/app_icon_button.dart';
import '../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../widgets/menu/sidebar_action_menu.dart';
import '../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../widgets/sidebar_session_tile.dart';
import 'config/project_cli_config_helpers.dart';
import 'config/project_cli_defaults_section.dart';
import 'project_search_dialog.dart';
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
  static const _emptySessions = <AppSession>[];

  bool get _isPersonal => widget.project.teamId.isEmpty;

  AppSessionSort _sessionSort = AppSessionSort.recentlyUpdated;

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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final rawSessions = context.select<ChatCubit, List<AppSession>>((c) {
      final grouped = groupSessionsByProjectId(c.state.sessions);
      final bucket = grouped[widget.project.projectId];
      if (bucket == null || bucket.isEmpty) {
        return sessionsForProject(widget.project, _emptySessions);
      }
      return sessionsForProject(widget.project, bucket);
    });
    final sortedSessions = sortAppSessions(rawSessions, sort: _sessionSort);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isPersonal) ...[
            _DefaultCliDropdown(projectId: widget.project.projectId),
            const SizedBox(height: 12),
          ],
          _SidebarActionTile(
            key: AppKeys.newChatSidebarTile,
            icon: Icons.edit_outlined,
            label: l10n.homeWorkspaceNewConversation,
            onTap: throttledAsync(
              'project_sidebar_new_chat',
              () => _startNewConversation(context),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.homeWorkspaceConversationsSection,
                    style: AppTextStyles.of(context).bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _SessionSortButton(
                  sort: _sessionSort,
                  onChanged: (s) => setState(() => _sessionSort = s),
                ),
                const SizedBox(width: 2),
                AppIconButton(
                  icon: Icons.search_rounded,
                  compact: true, size: AppIconButton.kCompactSize,
                  tooltip: l10n.projectSearchTitle,
                  onTap: throttledTap(
                    'project_sidebar_search',
                    () => unawaited(
                      showProjectSearchDialog(context, project: widget.project),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: sortedSessions.isEmpty
                ? _EmptyConversations(label: l10n.homeWorkspaceNoConversations)
                : ReorderableListView.builder(
                    padding: EdgeInsets.zero,
                    buildDefaultDragHandles: false,
                    itemCount: sortedSessions.length,
                    onReorder: (oldIndex, newIndex) {
                      final chatCubit = context.read<ChatCubit>();
                      if (oldIndex < sortedSessions.length) {
                        unawaited(
                          chatCubit.touchSession(
                            sortedSessions[oldIndex].sessionId,
                          ),
                        );
                      }
                    },
                    itemBuilder: (context, index) {
                      final session = sortedSessions[index];
                      return SidebarSessionTile(
                        key: ValueKey(
                          'project-sidebar-session-${session.sessionId}',
                        ),
                        session: session,
                        index: index,
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
    final registry = CliToolRegistryScope.of(context);
    final state = context.watch<ProjectProfileCubit>().state;
    context.watch<AppProviderCubit>();
    final ready =
        state.projectId == projectId &&
        state.status == ProjectProfileLoadStatus.ready &&
        state.profile != null;
    if (!ready) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final profile = state.profile!;
    final providerState = context.read<AppProviderCubit>().state;
    final configuredItems = _configuredCliValues(
      profile: profile,
      registry: registry,
      providerState: providerState,
    );
    final selectedCli = profile.cli;
    final initialItem = configuredItems.contains(selectedCli.value)
        ? selectedCli.value
        : (configuredItems.isNotEmpty ? configuredItems.first : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppDropdownField<String>(
              key: ValueKey(
                'project-sidebar-cli-$projectId-${initialItem ?? 'none'}',
              ),
              items: configuredItems,
              initialItem: initialItem,
              hintText: l10n.projectCliNotConfiguredHint,
              enabled: configuredItems.isNotEmpty,
              onEmptyTap: () => unawaited(
                showProjectCliDefaultsDialog(
                  context,
                  projectId: projectId,
                ),
              ),
              decoration: AppDropdownDecorations.themed(context),
              onChanged: (value) {
                if (value == null) return;
                unawaited(
                  context.read<ProjectProfileCubit>().setCli(
                    CliTool.decode(value),
                  ),
                );
              },
              itemBuilder: (context, value) {
                final cli = CliTool.decode(value);
                final definition = registry.tryGet(cli)!;
                return cliDropdownRow(
                  context,
                  cli: cli,
                  label: cliDisplayName(definition, l10n),
                  registry: registry,
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.tune_outlined,
            tooltip: l10n.projectCliDefaultsTitle,
            onTap: throttledTap(
              'project_sidebar_cli_configure',
              () => unawaited(
                showProjectCliDefaultsDialog(
                  context,
                  projectId: projectId,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _configuredCliValues({
  required ProjectProfile profile,
  required CliToolRegistry registry,
  required AppProviderState providerState,
}) {
  final values = <String>[];
  for (final def in registry.launchable) {
    final cli = def.id;
    final supportsCatalog = projectCliSupportsProviderCatalog(cli, registry);
    final providers = providerState.providersFor(cli);
    final selectedProvider = projectCliSelectedProvider(
      profile,
      cli,
      providers,
    );
    if (!projectCliIsConfigured(
      profile,
      cli,
      registry,
      selectedProvider: selectedProvider,
      supportsProviderCatalog: supportsCatalog,
    )) {
      continue;
    }
    values.add(cli.value);
  }
  values.sort();
  return values;
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
                Icon(widget.icon, size: context.appIconSizes.md, color: cs.onSurface),
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

class _SessionSortButton extends StatelessWidget {
  const _SessionSortButton({required this.sort, required this.onChanged});

  final AppSessionSort sort;
  final ValueChanged<AppSessionSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SidebarActionMenuIconAnchor(
      size: AppIconButton.kCompactSize,
      triggerBuilder: (context, controller) => AppIconButton(
        icon: Icons.sort_rounded,
        compact: true,
        size: AppIconButton.kCompactSize,
        tooltip: l10n.sessionSortTooltip,
        onTap: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      buildMenuChildren: (context, controller) {
        return [
          for (final value in AppSessionSort.values)
            SidebarActionMenuItem(
              icon: _iconForSessionSort(value),
              label: _labelForSessionSort(value, l10n),
              trailing: sort == value
                  ? Icon(
                      Icons.check,
                      size: context.appIconSizes.md,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    )
                  : null,
              menuController: controller,
              onTap: () => onChanged(value),
            ),
        ];
      },
    );
  }

  static String _labelForSessionSort(
    AppSessionSort sort,
    AppLocalizations l10n,
  ) =>
      switch (sort) {
        AppSessionSort.recentlyUpdated => l10n.sessionSortRecentlyUpdated,
        AppSessionSort.createdDesc => l10n.sessionSortCreatedDesc,
      };

  static IconData _iconForSessionSort(AppSessionSort sort) => switch (sort) {
    AppSessionSort.recentlyUpdated => Icons.update_rounded,
    AppSessionSort.createdDesc => Icons.event_rounded,
  };
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
              size: context.appIconSizes.md,
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
