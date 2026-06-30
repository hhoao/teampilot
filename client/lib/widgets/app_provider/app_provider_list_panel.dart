import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/app_provider_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_provider_config.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../utils/app_keys.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../dropdown/app_dropdown_field.dart';
import '../menu/sidebar_action_menu.dart';
import '../settings/focus_gated_text_field.dart';
import 'brand_dropdown_rows.dart';
import 'provider_brand_icon.dart';

class AppProviderListPanel extends StatefulWidget {
  const AppProviderListPanel({
    this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onImport,
    required this.onEdit,
    required this.onDelete,
    this.hubStyle = false,
    super.key,
  });

  /// When omitted, selection is read from [AppProviderCubit].
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final Future<void> Function() onImport;
  final ValueChanged<AppProviderConfig> onEdit;
  final ValueChanged<String> onDelete;
  final bool hubStyle;

  @override
  State<AppProviderListPanel> createState() => _AppProviderListPanelState();
}

class _ProviderListHeaderState {
  const _ProviderListHeaderState({
    required this.isLoading,
    required this.selectedCli,
  });

  final bool isLoading;
  final CliTool selectedCli;

  @override
  bool operator ==(Object other) {
    return other is _ProviderListHeaderState &&
        other.isLoading == isLoading &&
        other.selectedCli == selectedCli;
  }

  @override
  int get hashCode => Object.hash(isLoading, selectedCli);
}

class _AppProviderListPanelState extends State<AppProviderListPanel> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AppProviderConfig> _filterProviders(List<AppProviderConfig> providers) {
    if (_query.isEmpty) return providers;
    final q = _query.toLowerCase();
    return providers
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.id.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final headerBg = widget.hubStyle ? cs.workspacePage : cs.workspaceCard;

    return Material(
      key: AppKeys.llmProviderList,
      color: widget.hubStyle ? Colors.transparent : cs.workspaceCard,
      shape: widget.hubStyle
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: cs.outlineVariant),
            ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: BlocSelector<AppProviderCubit, AppProviderState,
                _ProviderListHeaderState>(
              selector: (state) => _ProviderListHeaderState(
                isLoading: state.isLoading,
                selectedCli: state.selectedCli,
              ),
              builder: (context, header) {
                final cubit = context.read<AppProviderCubit>();
                return _ProviderListControls(
                  search: _search,
                  onQueryChanged: (value) => setState(() => _query = value),
                  onAdd: widget.onAdd,
                  onImport: widget.onImport,
                  isLoading: header.isLoading,
                  selectedCli: header.selectedCli,
                  onCliChanged: cubit.setSelectedCli,
                );
              },
            ),
          ),
          Expanded(
            child: BlocSelector<AppProviderCubit, AppProviderState,
                List<AppProviderConfig>>(
              selector: (state) => state.providers,
              builder: (context, allProviders) {
                final providers = _filterProviders(allProviders);
                if (providers.isEmpty) {
                  return Center(child: Text(l10n.selectProvider));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: providers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final provider = providers[index];
                    return _ProviderListTileHost(
                      key: ValueKey(provider.id),
                      provider: provider,
                      hubStyle: widget.hubStyle,
                      selectedIdOverride: widget.selectedId,
                      onTap: () => widget.onSelect(provider.id),
                      onEdit: () => widget.onEdit(provider),
                      onDelete: () => widget.onDelete(provider.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderListTileHost extends StatelessWidget {
  const _ProviderListTileHost({
    required this.provider,
    required this.hubStyle,
    required this.selectedIdOverride,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final AppProviderConfig provider;
  final bool hubStyle;
  final String? selectedIdOverride;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (hubStyle) {
      return RepaintBoundary(
        child: _ProviderListTile(
          provider: provider,
          selected: false,
          hubStyle: hubStyle,
          onTap: onTap,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      );
    }

    if (selectedIdOverride != null) {
      return RepaintBoundary(
        child: _ProviderListTile(
          provider: provider,
          selected: provider.id == selectedIdOverride,
          hubStyle: hubStyle,
          onTap: onTap,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      );
    }

    return BlocSelector<AppProviderCubit, AppProviderState, bool>(
      selector: (state) => state.selectedId == provider.id,
      builder: (context, selected) {
        return RepaintBoundary(
          child: _ProviderListTile(
            provider: provider,
            selected: selected,
            hubStyle: hubStyle,
            onTap: onTap,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        );
      },
    );
  }
}

class _ProviderListControls extends StatelessWidget {
  const _ProviderListControls({
    required this.search,
    required this.onQueryChanged,
    required this.onAdd,
    required this.onImport,
    required this.isLoading,
    required this.selectedCli,
    required this.onCliChanged,
  });

  final TextEditingController search;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onAdd;
  final Future<void> Function() onImport;
  final bool isLoading;
  final CliTool selectedCli;
  final ValueChanged<CliTool> onCliChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  l10n.providerList,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.sectionTitle,
                ),
              ),
              SidebarActionMenuButton(
                tooltip: l10n.add,
                icon: Icon(Icons.add),
                size: 32,
                specs: [
                  SidebarActionMenuSpec.item(
                    value: 'add',
                    icon: Icons.add,
                    label: l10n.addProvider,
                  ),
                  SidebarActionMenuSpec.item(
                    value: 'import',
                    icon: Icons.upload_file_outlined,
                    label: l10n.appProviderImport,
                    enabled: !isLoading,
                  ),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'add':
                      onAdd();
                    case 'import':
                      onImport();
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: AppDropdownField<CliTool>(
            items: CliTool.values,
            initialItem: selectedCli,
            itemBuilder: cliDropdownItemBuilder(
              registry: CliToolRegistryScope.maybeOf(context),
              l10n: l10n,
            ),
            onChanged: (cli) {
              if (cli != null) onCliChanged(cli);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: FocusGatedTextField(
            controller: search,
            decoration: InputDecoration(
              hintText: l10n.filterProviders,
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
            onChanged: (v) => onQueryChanged(v.trim()),
          ),
        ),
      ],
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.provider,
    required this.selected,
    required this.hubStyle,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AppProviderConfig provider;
  final bool selected;
  final bool hubStyle;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final subtitle = provider.cli == CliTool.flashskyai
        ? l10n.providerListModelCount(provider.flashskyaiModelCount)
        : l10n.appProviderToolLabel(provider.cli);
    final titleColor = selected ? cs.onPrimaryContainer : cs.onSurface;
    final subtitleColor = selected
        ? cs.onPrimaryContainer.withValues(alpha: 0.74)
        : cs.onSurfaceVariant;
    final tileColor = selected
        ? cs.primaryContainer
        : hubStyle
        ? cs.workspaceSubtleSurface
        : cs.workspaceInset;
    final titleStyle = selected
        ? styles.bodyStrongColored(titleColor)
        : styles.bodyColored(titleColor, fontWeight: FontWeight.w500);

    return ListTile(
      selected: selected,
      tileColor: tileColor,
      selectedTileColor: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      iconColor: titleColor,
      textColor: titleColor,
      leading: ProviderBrandIcon.fromConfig(
        provider,
        size: 32,
        borderRadius: 8,
      ),
      title: Text(
        provider.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: styles.bodySmallColored(subtitleColor),
      ),
      trailing: hubStyle
          ? Icon(Icons.chevron_right, color: titleColor)
          : SidebarActionMenuButton(
              icon: Icon(Icons.more_horiz, color: titleColor),
              specs: [
                SidebarActionMenuSpec.item(
                  value: 'edit',
                  icon: Icons.edit_outlined,
                  label: l10n.edit,
                ),
                SidebarActionMenuSpec.item(
                  value: 'delete',
                  icon: Icons.delete_outline,
                  label: l10n.delete,
                  destructive: true,
                ),
              ],
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    onEdit();
                  case 'delete':
                    onDelete();
                }
              },
            ),
      onTap: onTap,
      onLongPress: onEdit,
    );
  }
}
